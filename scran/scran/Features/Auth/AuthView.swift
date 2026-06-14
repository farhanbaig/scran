//
//  AuthView.swift
//  scran
//
//  The account wall. Accounts are required so a user's plan and log follow them
//  across devices (not bound to one phone). Email + password, plus an optional
//  Sign in with Apple button gated behind ScranConfig.appleSignInEnabled.
//

import SwiftUI
import AuthenticationServices
import CryptoKit

/// Branded splash shown while we restore a stored session at launch. Mirrors
/// the onboarding welcome lockup (ClearoMark + wordmark) so launch feels
/// continuous with the rest of the brand.
struct AuthSplash: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                RadialGlow(diameter: 420)
                VStack(spacing: 22) {
                    ClearoMark(size: 150)
                    Text("CLEARO")
                        .font(ScranFont.display(28, relativeTo: .title))
                        .tracking(10)
                        .foregroundStyle(ScranColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scranScreen()
    }
}

struct AuthView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme

    /// Called after a successful sign-in/up (in addition to wiring the session).
    /// Used by onboarding to advance to plan-building, or a sheet to dismiss.
    var onComplete: (() -> Void)? = nil
    /// When set, shows a back chevron (e.g. to return to onboarding questions).
    var onBack: (() -> Void)? = nil
    /// Upgrading an existing anonymous guest to a real account (preserves data).
    /// Hides the "continue without an account" option and uses the convert flow.
    var isUpgrade: Bool = false
    /// Whether to offer the anonymous "this device only" option (onboarding).
    var allowAnonymous: Bool = false

    private enum Mode { case signIn, signUp }
    @State private var mode: Mode
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var info: String?
    @State private var currentNonce: String?
    @State private var showEmailForm = false
    @State private var agreedTerms = false
    @State private var marketingOptIn = true
    @FocusState private var focus: Field?
    private enum Field { case email, password }

    /// True when at least one social provider is configured.
    private var hasSocialProviders: Bool { ScranConfig.appleSignInEnabled }

    /// Email/password auth is hidden for now — sign-in is Apple or continue
    /// without an account. Flip to `true` to bring the email path back (all the
    /// email UI/logic below is preserved).
    private let showEmailAuth = false

    init(startInSignIn: Bool = false, isUpgrade: Bool = false, allowAnonymous: Bool = false,
         onComplete: (() -> Void)? = nil, onBack: (() -> Void)? = nil) {
        _mode = State(initialValue: startInSignIn ? .signIn : .signUp)
        self.isUpgrade = isUpgrade
        self.allowAnonymous = allowAnonymous
        self.onComplete = onComplete
        self.onBack = onBack
    }

    private var emailOK: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.contains(".") && e.count >= 5
    }
    private var termsOK: Bool { mode == .signIn || agreedTerms }
    private var canSubmit: Bool { emailOK && password.count >= 6 && termsOK && !busy }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let info { ScranBanner(kind: .info, text: info) }
                if let error { ScranBanner(kind: .error, text: error) }

                VStack(spacing: 12) {
                    if ScranConfig.appleSignInEnabled { appleButton }

                    // Email/password path — hidden for now (showEmailAuth == false).
                    if showEmailAuth {
                        if hasSocialProviders && !showEmailForm {
                            continueWithEmailButton
                        } else {
                            emailForm
                        }
                    }
                }

                if showEmailAuth && mode == .signUp { consentRows }
                if showEmailAuth { toggleModeButton }
                if allowAnonymous && !isUpgrade { anonymousOption }

                // With email hidden, consent is implicit — surface the links so
                // users can still read what they're agreeing to.
                if !showEmailAuth { legalLine }
            }
            .padding(24)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scranScreen()
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let onBack {
                Button { Haptics.selection(); onBack() } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(ScranColor.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(ScranColor.bg))
                        .overlay(Circle().strokeBorder(ScranColor.lineStrong, lineWidth: 1))
                }
                .accessibilityLabel("Back")
            }
            VStack(spacing: 16) {
                ClearoMark(size: 92)
                VStack(spacing: 10) {
                    Text(headerTitle)
                        .font(ScranFont.display(32, relativeTo: .largeTitle)).textCase(.uppercase)
                        .foregroundStyle(ScranColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(headerSubtitle)
                        .font(ScranFont.body(16, relativeTo: .body))
                        .foregroundStyle(ScranColor.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, onBack == nil ? 12 : 0)
        }
    }

    private var headerTitle: String {
        if isUpgrade { return "Sync your data" }
        return mode == .signUp ? "Save your progress" : "Welcome back"
    }

    private var headerSubtitle: String {
        if isUpgrade {
            return "Sign in with Apple so your plan and log sync to any device. Everything you've logged is kept."
        }
        if mode == .signIn { return "Sign in to pick up exactly where you left off." }
        return showEmailAuth
            ? "Create an account so your plan and your log sync to any device."
            : "Sign in with Apple so your plan and log follow you to any device — or keep going on this phone."
    }

    // MARK: - Providers / form

    private var appleButton: some View {
        // When the email path is hidden, consent is implicit (shown via legalLine)
        // so the button isn't gated on the checkbox.
        let gated = showEmailAuth && !termsOK
        return SignInWithAppleButton(.signIn, onRequest: configureApple, onCompletion: handleApple)
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 54)
            .clipShape(Capsule())
            .disabled(busy || gated)
            .opacity(gated ? 0.5 : 1)
    }

    /// Implicit-consent footer shown when the email/consent form is hidden.
    private var legalLine: some View {
        Text(.init("By continuing you agree to Clearo's [Terms](\(ScranConfig.termsURL.absoluteString)) and [Privacy Policy](\(ScranConfig.privacyURL.absoluteString))."))
            .font(ScranFont.body(12, relativeTo: .footnote))
            .foregroundStyle(ScranColor.textMuted)
            .tint(ScranColor.verified)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private var continueWithEmailButton: some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy) { showEmailForm = true }
            focus = .email
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "envelope")
                Text("Continue with email")
                    .font(ScranFont.body(16, weight: .semibold, relativeTo: .headline))
            }
            .frame(maxWidth: .infinity).frame(height: 52)
            .foregroundStyle(ScranColor.textPrimary)
            .background(Capsule().fill(ScranColor.bg))
            .overlay(Capsule().strokeBorder(ScranColor.lineStrong, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    private var emailForm: some View {
        VStack(spacing: 12) {
            field("Email", text: $email, secure: false, field: .email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
            field("Password", text: $password, secure: true, field: .password)
                .textContentType(mode == .signUp ? .newPassword : .password)

            PrimaryButton(title: busy ? "Please wait…" : (mode == .signUp ? "Create account" : "Sign in"),
                          systemImage: "arrow.right", enabled: canSubmit) { submit() }

            if mode == .signIn {
                Button("Forgot password?") { resetPassword() }
                    .font(ScranFont.body(14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(ScranColor.textMuted)
                    .frame(maxWidth: .infinity).padding(.top, 2)
            }
        }
    }

    // MARK: - Consent

    private var consentRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            checkRow(checked: agreedTerms, toggle: { agreedTerms.toggle() }) {
                // Markdown links are tappable — required so users can actually
                // read what they're agreeing to before consenting.
                Text(.init("I agree to Clearo's [Terms](\(ScranConfig.termsURL.absoluteString)) and [Privacy Policy](\(ScranConfig.privacyURL.absoluteString))"))
                    .font(ScranFont.body(13, relativeTo: .footnote))
                    .foregroundStyle(ScranColor.textMuted)
                    .tint(ScranColor.textPrimary)
            }
            checkRow(checked: marketingOptIn, toggle: { marketingOptIn.toggle() }) {
                Text("Send me occasional tips and product updates.")
                    .font(ScranFont.body(13, relativeTo: .footnote))
                    .foregroundStyle(ScranColor.textMuted)
            }
        }
        .padding(.top, 2)
    }

    private func checkRow<L: View>(checked: Bool, toggle: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button { Haptics.selection(); toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                CheckBox(isOn: checked, size: 22)
                label()
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var anonymousOption: some View {
        VStack(spacing: 6) {
            HStack { Rectangle().fill(ScranColor.line).frame(height: 1) }
                .padding(.vertical, 4)
            Button {
                Haptics.tap(); busy = true; error = nil
                Task {
                    await app.continueAnonymously(context: context)
                    busy = false
                    onComplete?()
                }
            } label: {
                Text("Continue without an account")
                    .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .disabled(busy)
            Text("Your plan stays on this device only — you won't be able to use it on another phone or recover it if the app is deleted.")
                .font(ScranFont.body(12, relativeTo: .caption2))
                .foregroundStyle(ScranColor.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var toggleModeButton: some View {
        Button {
            Haptics.selection()
            error = nil; info = nil
            withAnimation(.snappy) {
                mode = (mode == .signUp) ? .signIn : .signUp
                showEmailForm = !hasSocialProviders || mode == .signIn
            }
        } label: {
            Text(mode == .signUp ? "Already have an account? Sign in"
                                 : "New here? Create an account")
                .font(ScranFont.body(14, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(ScranColor.verified)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Field

    @ViewBuilder
    private func field(_ placeholder: String, text: Binding<String>, secure: Bool, field: Field) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
            }
        }
        .focused($focus, equals: field)
        .font(ScranFont.body(16, relativeTo: .body))
        .foregroundStyle(ScranColor.textPrimary)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ScranColor.bg))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ScranColor.line))
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(ScranColor.line).frame(height: 1)
            Text("or").font(ScranFont.mono(12, relativeTo: .caption)).foregroundStyle(ScranColor.textMuted)
            Rectangle().fill(ScranColor.line).frame(height: 1)
        }
    }

    // MARK: - Email / password

    private func submit() {
        focus = nil
        busy = true; error = nil; info = nil
        let e = email.trimmingCharacters(in: .whitespaces)
        Task {
            defer { busy = false }
            do {
                if mode == .signUp {
                    // Upgrading a guest preserves their data (same user id) via
                    // convert; a fresh user signs up normally.
                    let result = isUpgrade
                        ? try await SupabaseClient.shared.convertAnonymous(email: e, password: password)
                        : try await SupabaseClient.shared.signUpEmail(
                            email: e, password: password, metadata: ["marketing_opt_in": marketingOptIn])
                    switch result {
                    case .session(let s):
                        app.analytics.track(.signedUp(method: isUpgrade ? "upgrade" : "email"))
                        Haptics.success()
                        await app.completeSignIn(s, context: context)
                        onComplete?()
                    case .confirmationRequired(let addr):
                        info = isUpgrade
                            ? "We've emailed a confirmation link to \(addr). Tap it and your account will sync everywhere."
                            : "We've emailed a confirmation link to \(addr). Tap it, then sign in."
                        if !isUpgrade { mode = .signIn; password = "" }
                    }
                } else {
                    let s = try await SupabaseClient.shared.signInEmail(email: e, password: password)
                    app.analytics.track(.signedIn(method: "email"))
                    Haptics.success()
                    await app.completeSignIn(s, context: context)
                    onComplete?()
                }
            } catch {
                Haptics.error()
                self.error = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Try again."
            }
        }
    }

    private func resetPassword() {
        let e = email.trimmingCharacters(in: .whitespaces)
        guard emailOK else { error = "Enter your email above first."; return }
        busy = true; error = nil; info = nil
        Task {
            defer { busy = false }
            try? await SupabaseClient.shared.requestPasswordReset(email: e)
            info = "If an account exists for \(e), we've sent a reset link."
        }
    }

    // MARK: - Apple

    private func configureApple(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.email]
        request.nonce = Self.sha256(nonce)
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                error = "Apple sign-in failed. Try again."
                return
            }
            busy = true; error = nil
            Task {
                defer { busy = false }
                do {
                    let s = try await SupabaseClient.shared.signInWithApple(idToken: token, nonce: nonce)
                    app.analytics.track(.signedIn(method: "apple"))
                    Haptics.success()
                    await app.completeSignIn(s, context: context)
                    onComplete?()
                } catch {
                    Haptics.error()
                    self.error = (error as? LocalizedError)?.errorDescription
                        ?? "Apple sign-in isn't available yet."
                }
            }
        case .failure(let err):
            if (err as? ASAuthorizationError)?.code != .canceled {
                error = "Apple sign-in failed. Try again."
            }
        }
    }

    // MARK: - Nonce helpers

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < chars.count { result.append(chars[Int(random)]); remaining -= 1 }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
