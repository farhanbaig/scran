//
//  SupabaseClient.swift
//  scran
//
//  A small, dependency-free Supabase client over URLSession: anonymous auth with
//  token refresh, Edge Function invocation, Storage upload + signed URLs, and a
//  PostgREST helper for the sync queue. The app talks ONLY to Supabase and
//  RevenueCat — no AI provider keys are ever embedded.
//

import Foundation

struct SupabaseSession: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var userId: String
    /// Absolute expiry time of the access token.
    var expiresAt: Date
    var email: String?
    var isAnonymous: Bool = false
}

/// Outcome of an email sign-up: an immediate session, or (when the project has
/// "Confirm email" enabled) a pending state until the user clicks the email link.
enum SignUpResult: Sendable {
    case session(SupabaseSession)
    case confirmationRequired(email: String)
}

enum SupabaseError: Error, LocalizedError {
    case notAuthenticated
    case http(status: Int, body: String)
    case decoding
    case offline
    case quotaExceeded(used: Int, limit: Int)
    /// A GoTrue auth error carrying a user-facing message.
    case auth(message: String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You're not signed in yet."
        case .http(let s, _):   return "Server error (\(s))."
        case .decoding:         return "Couldn't read the server's reply."
        case .offline:          return "You appear to be offline."
        case .quotaExceeded:    return "Daily AI scan limit reached."
        case .auth(let m):      return m
        }
    }
}

/// Thread-safe Supabase client. Declared as an `actor` so it stays off the main
/// actor despite the project's MainActor-by-default isolation.
actor SupabaseClient {
    static let shared = SupabaseClient()

    private let session: URLSession
    private let apiKey = ScranConfig.supabasePublishableKey
    private var current: SupabaseSession?

    private static let refreshKey = "supabase.refresh_token"

    init() {
        let config = URLSessionConfiguration.default
        // Vision Edge Functions (label/plate) can legitimately take a while;
        // allow headroom so a slow scan never trips a client-side timeout.
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: - Auth

    var userId: String? { current?.userId }
    var currentEmail: String? { current?.email }

    /// Ensure we have a valid session, refreshing the access token when it's near
    /// expiry. Accounts are required, so this NO LONGER creates an anonymous user
    /// — it restores a stored session or throws `.notAuthenticated`.
    @discardableResult
    func ensureSession() async throws -> SupabaseSession {
        if let s = current, s.expiresAt.timeIntervalSinceNow > 60 { return s }

        // Try refresh with a persisted refresh token.
        if let refreshToken = current?.refreshToken ?? Keychain.get(Self.refreshKey) {
            if let s = try? await refreshSession(token: refreshToken) {
                store(s)
                return s
            }
        }
        throw SupabaseError.notAuthenticated
    }

    /// Restore a persisted session at launch. Returns nil if none/expired/offline.
    func restoreSession() async -> SupabaseSession? {
        try? await ensureSession()
    }

    /// Whether a refresh token is persisted (a prior sign-in). Used to keep an
    /// account signed in across an offline launch.
    func hasStoredRefreshToken() -> Bool {
        Keychain.get(Self.refreshKey) != nil
    }

    private func store(_ s: SupabaseSession) {
        current = s
        Keychain.set(s.refreshToken, for: Self.refreshKey)
    }

    func signOutAndWipeLocalSession() {
        current = nil
        Keychain.clear()
    }

    private func signInAnonymously() async throws -> SupabaseSession {
        var req = URLRequest(url: ScranConfig.authURL.appendingPathComponent("signup"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["data": [:]])
        return try await decodeSession(from: req)
    }

    private func refreshSession(token: String) async throws -> SupabaseSession {
        var comps = URLComponents(url: ScranConfig.authURL.appendingPathComponent("token"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": token])
        return try await decodeSession(from: req)
    }

    private struct AuthResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int?
        let user: User
        struct User: Decodable {
            let id: String
            let email: String?
            let is_anonymous: Bool?
        }
    }

    private static func session(from r: AuthResponse) -> SupabaseSession {
        SupabaseSession(
            accessToken: r.access_token,
            refreshToken: r.refresh_token,
            userId: r.user.id,
            expiresAt: Date().addingTimeInterval(TimeInterval(r.expires_in ?? 3600)),
            email: r.user.email,
            isAnonymous: r.user.is_anonymous ?? false)
    }

    private func decodeSession(from req: URLRequest) async throws -> SupabaseSession {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SupabaseError.decoding }
        guard (200...299).contains(http.statusCode) else {
            throw SupabaseError.auth(message: Self.authError(from: data))
        }
        guard let r = try? JSONDecoder().decode(AuthResponse.self, from: data) else {
            throw SupabaseError.decoding
        }
        return Self.session(from: r)
    }

    /// Pull a user-facing message out of a GoTrue error body.
    private static func authError(from data: Data) -> String {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return "Something went wrong. Try again."
        }
        return (o["msg"] as? String) ?? (o["error_description"] as? String)
            ?? (o["error"] as? String) ?? (o["message"] as? String)
            ?? "Something went wrong. Try again."
    }

    // MARK: - Email / Apple auth

    /// Create an account. Returns a session, or `.confirmationRequired` when the
    /// project has email confirmation enabled (no session until the link is clicked).
    func signUpEmail(email: String, password: String, metadata: [String: Any]? = nil) async throws -> SignUpResult {
        var req = URLRequest(url: ScranConfig.authURL.appendingPathComponent("signup"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["email": email, "password": password]
        if let metadata { body["data"] = metadata }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SupabaseError.decoding }
        guard (200...299).contains(http.statusCode) else {
            throw SupabaseError.auth(message: Self.authError(from: data))
        }
        if let r = try? JSONDecoder().decode(AuthResponse.self, from: data) {
            let s = Self.session(from: r)
            store(s)
            return .session(s)
        }
        // No tokens => confirmation required.
        return .confirmationRequired(email: email)
    }

    func signInEmail(email: String, password: String) async throws -> SupabaseSession {
        var comps = URLComponents(url: ScranConfig.authURL.appendingPathComponent("token"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let s = try await decodeSession(from: req)
        store(s)
        return s
    }

    /// Native Sign in with Apple: exchange Apple's identity token for a session.
    func signInWithApple(idToken: String, nonce: String) async throws -> SupabaseSession {
        var comps = URLComponents(url: ScranConfig.authURL.appendingPathComponent("token"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "provider": "apple", "id_token": idToken, "nonce": nonce,
        ])
        let s = try await decodeSession(from: req)
        store(s)
        return s
    }

    /// Create an anonymous session — no account. Usable on THIS device only
    /// (won't sync to others). The user can upgrade later via `convertAnonymous`.
    @discardableResult
    func continueAnonymously() async throws -> SupabaseSession {
        let s = try await signInAnonymously()
        store(s)
        return s
    }

    /// Upgrade the current anonymous user to a permanent email account, keeping
    /// the same user id so all their data carries over. With email confirmation
    /// on, returns `.confirmationRequired` until the link is clicked.
    func convertAnonymous(email: String, password: String) async throws -> SignUpResult {
        let s = try await ensureSession()
        var req = URLRequest(url: ScranConfig.authURL.appendingPathComponent("user"))
        req.httpMethod = "PUT"
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SupabaseError.decoding }
        guard (200...299).contains(http.statusCode) else {
            throw SupabaseError.auth(message: Self.authError(from: data))
        }
        struct U: Decodable { let email: String?; let is_anonymous: Bool?; let email_confirmed_at: String? }
        let u = try? JSONDecoder().decode(U.self, from: data)
        let confirmed = (u?.email_confirmed_at != nil) && (u?.is_anonymous == false)
        if var cur = current {
            cur.email = email
            cur.isAnonymous = u?.is_anonymous ?? cur.isAnonymous
            current = cur
            if confirmed { return .session(cur) }
        }
        return .confirmationRequired(email: email)
    }

    func requestPasswordReset(email: String) async throws {
        var req = URLRequest(url: ScranConfig.authURL.appendingPathComponent("recover"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseError.auth(message: Self.authError(from: data))
        }
    }

    /// Sign out: best-effort server revoke, then clear local session + keychain.
    func signOut() async {
        if let token = current?.accessToken {
            var req = URLRequest(url: ScranConfig.authURL.appendingPathComponent("logout"))
            req.httpMethod = "POST"
            req.setValue(apiKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await session.data(for: req)
        }
        signOutAndWipeLocalSession()
    }

    // MARK: - Authorized request builder

    private func authorizedRequest(url: URL, method: String) async throws -> URLRequest {
        let s = try await ensureSession()
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    // MARK: - Edge Functions

    /// Invoke an Edge Function. Returns raw data; callers decode their contract.
    func invokeFunction(_ name: String, body: [String: Any]) async throws -> Data {
        var req = try await authorizedRequest(
            url: ScranConfig.functionsURL.appendingPathComponent(name), method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SupabaseError.decoding }
        if http.statusCode == 402 {
            // Quota exceeded contract.
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw SupabaseError.quotaExceeded(
                used: obj?["used"] as? Int ?? ScranConfig.freeDailyScans,
                limit: obj?["limit"] as? Int ?? ScranConfig.freeDailyScans)
        }
        guard (200...299).contains(http.statusCode) else {
            throw SupabaseError.http(status: http.statusCode,
                                     body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - PostgREST (sync)

    /// Upsert rows into a table. `onConflict` defaults to the primary key.
    func upsert(table: String, rows: [[String: Any]]) async throws {
        guard !rows.isEmpty else { return }
        var comps = URLComponents(url: ScranConfig.restURL.appendingPathComponent(table),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "on_conflict", value: "id")]
        var req = try await authorizedRequest(url: comps.url!, method: "POST")
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: rows)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw SupabaseError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Select rows from a table (RLS scopes them to the signed-in user). Returns
    /// raw JSON for the caller to decode.
    func select(table: String, query: [URLQueryItem]) async throws -> Data {
        var comps = URLComponents(url: ScranConfig.restURL.appendingPathComponent(table),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        let req = try await authorizedRequest(url: comps.url!, method: "GET")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw SupabaseError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// Call a Postgres RPC and decode the JSON result.
    func rpc<T: Decodable>(_ name: String, args: [String: Any] = [:], returning: T.Type) async throws -> T {
        var req = try await authorizedRequest(
            url: ScranConfig.restURL.appendingPathComponent("rpc/\(name)"), method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: args)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw SupabaseError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw SupabaseError.decoding
        }
        return value
    }

    // MARK: - Storage

    /// Upload a food photo to `food-photos/{userId}/{entryId}.jpg`. Returns the path.
    @discardableResult
    func uploadFoodPhoto(entryId: UUID, jpeg: Data) async throws -> String {
        let s = try await ensureSession()
        let path = "\(s.userId)/\(entryId.uuidString).jpg"
        let url = ScranConfig.storageURL
            .appendingPathComponent("object/food-photos/\(path)")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.httpBody = jpeg
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw SupabaseError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        return path
    }
}
