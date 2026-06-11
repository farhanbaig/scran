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
}

enum SupabaseError: Error, LocalizedError {
    case notAuthenticated
    case http(status: Int, body: String)
    case decoding
    case offline
    case quotaExceeded(used: Int, limit: Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You're not signed in yet."
        case .http(let s, _):   return "Server error (\(s))."
        case .decoding:         return "Couldn't read the server's reply."
        case .offline:          return "You appear to be offline."
        case .quotaExceeded:    return "Daily AI scan limit reached."
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

    /// Ensure we have a valid session, signing in anonymously on first launch and
    /// refreshing the access token when it's near expiry.
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
        // Fall back to a fresh anonymous sign-in.
        let s = try await signInAnonymously()
        store(s)
        return s
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

    private func decodeSession(from req: URLRequest) async throws -> SupabaseSession {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SupabaseError.decoding }
        guard (200...299).contains(http.statusCode) else {
            throw SupabaseError.http(status: http.statusCode,
                                     body: String(data: data, encoding: .utf8) ?? "")
        }
        struct AuthResponse: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Int?
            let user: User
            struct User: Decodable { let id: String }
        }
        guard let r = try? JSONDecoder().decode(AuthResponse.self, from: data) else {
            throw SupabaseError.decoding
        }
        return SupabaseSession(
            accessToken: r.access_token,
            refreshToken: r.refresh_token,
            userId: r.user.id,
            expiresAt: Date().addingTimeInterval(TimeInterval(r.expires_in ?? 3600))
        )
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
