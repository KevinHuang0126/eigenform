import AuthenticationServices
import CryptoKit
import Foundation
import Supabase

/// Owns the Supabase client and publishes auth state for the UI.
///
/// Sessions persist in the Keychain (the SDK default) and refresh silently;
/// the rest of the app only reads `phase` and `user`. Every mutation funnels
/// through the intents below so error handling stays in one place.
@MainActor
final class AuthController: ObservableObject {

    enum Phase: Equatable {
        /// Restoring a persisted session at launch.
        case loading
        case signedOut
        case signedIn
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var user: User?
    /// Set when the user arrives from a password-recovery email link; drives
    /// the "choose a new password" sheet.
    @Published var needsPasswordReset = false

    /// False until `SupabaseConfig` holds real credentials; the auth wall
    /// shows setup instructions instead of a sign-in form.
    let isConfigured: Bool

    /// Workout history rides the same Supabase client and follows the auth
    /// lifecycle (cleared on sign-out), so this controller owns it. Views
    /// observe it directly via `.environmentObject`.
    let history = HistoryStore()

    private var client: SupabaseClient!
    private var stateTask: Task<Void, Never>?

    init() {
        isConfigured = SupabaseConfig.isConfigured
        guard isConfigured else {
            phase = .signedOut
            return
        }
        let client = SupabaseClient(
            supabaseURL: URL(string: SupabaseConfig.projectURL)!,
            supabaseKey: SupabaseConfig.anonKey)
        self.client = client
        history.configure(client: client)

        stateTask = Task { [weak self] in
            for await (event, session) in client.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .passwordRecovery:
                    self.needsPasswordReset = true
                    self.apply(session)
                case .initialSession, .signedIn, .signedOut, .tokenRefreshed, .userUpdated:
                    self.apply(session)
                default:
                    break
                }
            }
        }
    }

    deinit {
        stateTask?.cancel()
    }

    private func apply(_ session: Session?) {
        user = session?.user
        phase = session == nil ? .signedOut : .signedIn
        if session == nil {
            history.clearLocal()
        } else {
            history.retryQueuedSaves()
        }
    }

    // MARK: Derived identity

    var displayName: String {
        if case .string(let name)? = user?.userMetadata["display_name"], !name.isEmpty {
            return name
        }
        return ""
    }

    var email: String { user?.email ?? "" }

    // MARK: Email + password

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    /// Returns true when a session was created immediately; false when the
    /// user must verify their email address first.
    func signUp(email: String, password: String, displayName: String) async throws -> Bool {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: displayName.isEmpty ? nil : ["display_name": .string(displayName)],
            redirectTo: SupabaseConfig.redirectURL)
        return response.session != nil
    }

    func resendVerificationEmail(to email: String) async throws {
        try await client.auth.resend(email: email, type: .signup)
    }

    func sendPasswordReset(to email: String) async throws {
        try await client.auth.resetPasswordForEmail(
            email, redirectTo: SupabaseConfig.recoveryRedirectURL)
    }

    // MARK: Social sign-in

    /// Google runs through the Supabase OAuth flow in an in-app web sheet
    /// (ASWebAuthenticationSession); the SDK completes the PKCE exchange.
    func signInWithGoogle() async throws {
        try await client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: SupabaseConfig.redirectURL)
    }

    /// Native Sign in with Apple: the identity token (bound to `nonce`, which
    /// the button hashed into the request) is exchanged for a session.
    func signInWithApple(_ authorization: ASAuthorization, nonce: String) async throws {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else {
            throw AuthFlowError.appleCredentialUnreadable
        }

        try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple, idToken: idToken, nonce: nonce))

        // Apple shares the name only on the very first authorization — persist
        // it now or lose it.
        if displayName.isEmpty, let components = credential.fullName {
            let name = PersonNameComponentsFormatter.localizedString(
                from: components, style: .default)
            if !name.isEmpty {
                try? await client.auth.update(
                    user: UserAttributes(data: ["display_name": .string(name)]))
            }
        }
    }

    // MARK: Account management

    func updateDisplayName(_ name: String) async throws {
        try await client.auth.update(user: UserAttributes(data: ["display_name": .string(name)]))
    }

    /// Sends confirmation links to both the old and new address (Supabase's
    /// secure email change); the change lands once both are confirmed.
    func changeEmail(to newEmail: String) async throws {
        try await client.auth.update(user: UserAttributes(email: newEmail))
    }

    func updatePassword(_ newPassword: String) async throws {
        try await client.auth.update(user: UserAttributes(password: newPassword))
        needsPasswordReset = false
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    /// Server-side deletion through the `delete_user` RPC (a SECURITY DEFINER
    /// function that removes `auth.uid()` — see docs/AUTH_SETUP.md), then a
    /// best-effort sign-out to clear the Keychain session.
    func deleteAccount() async throws {
        try await client.rpc("delete_user").execute()
        try? await client.auth.signOut()
    }

    // MARK: Deep links

    /// Handles `eigenform://auth-callback` URLs from OAuth redirects and email
    /// links (confirmation, recovery, email change).
    func handleDeepLink(_ url: URL) {
        guard isConfigured, url.scheme == "eigenform" else { return }
        let isRecovery = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.contains { $0.name == "flow" && $0.value == "recovery" } ?? false
        Task {
            do {
                try await client.auth.session(from: url)
                if isRecovery { needsPasswordReset = true }
            } catch {
                // Stale or already-consumed link; nothing actionable.
            }
        }
    }

    // MARK: Apple nonce helpers

    /// Random nonce binding the Apple ID token to this sign-in request, so a
    /// token replayed by a third party won't be accepted by Supabase.
    /// SystemRandomNumberGenerator is cryptographically secure on Apple platforms.
    static func randomNonce(length: Int = 32) -> String {
        let charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._"
        return String((0..<length).map { _ in charset.randomElement()! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum AuthFlowError: LocalizedError {
    case appleCredentialUnreadable

    var errorDescription: String? {
        switch self {
        case .appleCredentialUnreadable:
            return "Apple didn't return a usable credential. Please try again."
        }
    }
}
