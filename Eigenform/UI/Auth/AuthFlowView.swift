import AuthenticationServices
import SwiftUI

/// The wall in front of the app: coordinates sign-in, sign-up, password
/// reset, and the post-signup verification notice with the same spring
/// transitions the workout flow uses.
struct AuthFlowView: View {
    @EnvironmentObject private var auth: AuthController

    private enum Screen: Equatable {
        case signIn
        case signUp
        case forgot
        case verify(email: String)
    }

    @State private var screen: Screen = .signIn

    var body: some View {
        ZStack {
            EF.paper.ignoresSafeArea()

            if !auth.isConfigured {
                ConfigMissingView()
            } else {
                switch screen {
                case .signIn:
                    SignInView(
                        onSignUp: { go(.signUp) },
                        onForgot: { go(.forgot) })
                        .transition(.opacity)

                case .signUp:
                    SignUpView(
                        onBack: { go(.signIn) },
                        onNeedsVerification: { go(.verify(email: $0)) })
                        .transition(.opacity)

                case .forgot:
                    ForgotPasswordView(onBack: { go(.signIn) })
                        .transition(.opacity)

                case .verify(let email):
                    VerifyEmailView(email: email, onBack: { go(.signIn) })
                        .transition(.opacity)
                }
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: screen)
    }

    private func go(_ newScreen: Screen) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            screen = newScreen
        }
    }
}

/// Scroll container shared by the auth screens so the keyboard never covers
/// a field, capped at the same reading width as the rest of the app.
private struct AuthPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Sign in

private struct SignInView: View {
    @EnvironmentObject private var auth: AuthController
    var onSignUp: () -> Void
    var onForgot: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isBusy = false
    /// Set when sign-in fails because the address was never verified, so the
    /// resend option only appears when it can actually help.
    @State private var showResend = false
    @State private var resendConfirmation: String?
    /// Raw nonce for the in-flight Apple request; its SHA-256 goes into the
    /// request, the raw value goes to Supabase for verification.
    @State private var appleNonce = ""

    var body: some View {
        AuthPage {
            AuthHeader(title: "EigenForm", subtitle: "Sign in to start training.")

            VStack(spacing: 12) {
                EFEmailField(placeholder: "Email", text: $email)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .efFieldChrome()
            }
            .padding(.top, 32)

            if let errorMessage {
                EFErrorNote(message: errorMessage)
                    .padding(.top, 12)
            }

            if showResend {
                EFGhostButton(title: "Resend verification email", tint: EF.emerald) {
                    resendVerification()
                }
            }
            if let resendConfirmation {
                Text(resendConfirmation)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(EF.emerald)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            EFPrimaryButton(title: "Sign In", isBusy: isBusy) { signIn() }
                .padding(.top, 16)

            EFGhostButton(title: "Forgot password?", action: onForgot)
                .padding(.top, 4)

            AuthDivider()
                .padding(.vertical, 20)

            VStack(spacing: 12) {
                appleButton
                googleButton
            }

            HStack(spacing: 6) {
                Text("New here?")
                    .font(EF.body)
                    .foregroundStyle(EF.dim)
                Button(action: onSignUp) {
                    Text("Create an account")
                        .font(EF.label)
                        .foregroundStyle(EF.emerald)
                }
                .buttonStyle(EFPressStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            appleNonce = AuthController.randomNonce()
            request.requestedScopes = [.fullName, .email]
            request.nonce = AuthController.sha256(appleNonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                run { try await auth.signInWithApple(authorization, nonce: appleNonce) }
            case .failure(let error):
                if (error as? ASAuthorizationError)?.code != .canceled {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .clipShape(Capsule())
    }

    private var googleButton: some View {
        Button {
            run { try await auth.signInWithGoogle() }
        } label: {
            Text("Continue with Google")
                .font(EF.label)
                .foregroundStyle(EF.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(EF.raised, in: Capsule())
                .overlay(Capsule().strokeBorder(EF.hairline))
        }
        .buttonStyle(EFPressStyle())
    }

    private func signIn() {
        let address = email.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your email and password."
            return
        }
        run { try await auth.signIn(email: address, password: password) }
    }

    private func resendVerification() {
        let address = email.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                try await auth.resendVerificationEmail(to: address)
                withAnimation { resendConfirmation = "Verification email sent." }
            } catch {
                withAnimation { errorMessage = error.localizedDescription }
            }
        }
    }

    /// Runs an auth intent with the shared busy/error handling. A sign-in
    /// failure mentioning confirmation means the address was never verified,
    /// which is the one failure the user can fix from here via resend.
    private func run(_ intent: @escaping () async throws -> Void) {
        errorMessage = nil
        resendConfirmation = nil
        isBusy = true
        Task {
            do {
                try await intent()
                // Success flips `auth.phase`; RootView swaps this screen out.
            } catch {
                withAnimation {
                    errorMessage = error.localizedDescription
                    showResend = error.localizedDescription
                        .localizedCaseInsensitiveContains("confirm")
                }
            }
            isBusy = false
        }
    }
}

// MARK: - Sign up

private struct SignUpView: View {
    @EnvironmentObject private var auth: AuthController
    var onBack: () -> Void
    var onNeedsVerification: (String) -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var errorMessage: String?
    @State private var isBusy = false

    var body: some View {
        AuthPage {
            AuthHeader(title: "Create account",
                       subtitle: "Your form history, on every device.")

            VStack(spacing: 12) {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .efFieldChrome()
                EFEmailField(placeholder: "Email", text: $email)
                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                    .efFieldChrome()
                SecureField("Confirm password", text: $confirm)
                    .textContentType(.newPassword)
                    .efFieldChrome()
            }
            .padding(.top, 32)

            Text("At least 8 characters.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(EF.faint)
                .padding(.top, 8)

            if let errorMessage {
                EFErrorNote(message: errorMessage)
                    .padding(.top, 12)
            }

            EFPrimaryButton(title: "Create Account", isBusy: isBusy) { signUp() }
                .padding(.top, 16)

            EFGhostButton(title: "Back to Sign In", action: onBack)
                .padding(.top, 4)
        }
    }

    private func signUp() {
        let address = email.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty, address.contains("@"), address.contains(".") else {
            withAnimation { errorMessage = "Enter a valid email address." }
            return
        }
        guard password.count >= 8 else {
            withAnimation { errorMessage = "Password must be at least 8 characters." }
            return
        }
        guard password == confirm else {
            withAnimation { errorMessage = "Passwords don't match." }
            return
        }

        errorMessage = nil
        isBusy = true
        Task {
            do {
                let signedIn = try await auth.signUp(
                    email: address,
                    password: password,
                    displayName: name.trimmingCharacters(in: .whitespaces))
                // With email confirmation on there's no session yet — show the
                // verification notice. Otherwise RootView takes over.
                if !signedIn {
                    onNeedsVerification(address)
                }
            } catch {
                withAnimation { errorMessage = error.localizedDescription }
            }
            isBusy = false
        }
    }
}

// MARK: - Verify email

private struct VerifyEmailView: View {
    @EnvironmentObject private var auth: AuthController
    let email: String
    var onBack: () -> Void

    @State private var note: String?

    var body: some View {
        AuthPage {
            AuthHeader(title: "Check your email",
                       subtitle: "We sent a verification link to \(email). Tap it on this device and you'll land right back here, signed in.")

            Image(systemName: "envelope.badge")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(EF.emerald)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)

            if let note {
                Text(note)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(EF.emerald)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)
            }

            EFPrimaryButton(title: "Resend Email") {
                Task {
                    do {
                        try await auth.resendVerificationEmail(to: email)
                        withAnimation { note = "Sent again — give it a minute." }
                    } catch {
                        withAnimation { note = error.localizedDescription }
                    }
                }
            }

            EFGhostButton(title: "Back to Sign In", action: onBack)
                .padding(.top, 4)
        }
    }
}

// MARK: - Forgot password

private struct ForgotPasswordView: View {
    @EnvironmentObject private var auth: AuthController
    var onBack: () -> Void

    @State private var email = ""
    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var sent = false

    var body: some View {
        AuthPage {
            AuthHeader(title: "Reset password",
                       subtitle: sent
                           ? "If an account exists for that address, a reset link is on its way. Open it on this device to choose a new password."
                           : "Enter your email and we'll send a reset link.")

            if !sent {
                EFEmailField(placeholder: "Email", text: $email)
                    .padding(.top, 32)

                if let errorMessage {
                    EFErrorNote(message: errorMessage)
                        .padding(.top, 12)
                }

                EFPrimaryButton(title: "Send Reset Link", isBusy: isBusy) { send() }
                    .padding(.top, 16)
            } else {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(EF.emerald)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }

            EFGhostButton(title: "Back to Sign In", action: onBack)
                .padding(.top, 4)
        }
    }

    private func send() {
        let address = email.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else {
            withAnimation { errorMessage = "Enter your email address." }
            return
        }
        errorMessage = nil
        isBusy = true
        Task {
            do {
                try await auth.sendPasswordReset(to: address)
                withAnimation { sent = true }
            } catch {
                withAnimation { errorMessage = error.localizedDescription }
            }
            isBusy = false
        }
    }
}

// MARK: - Missing configuration

/// Shown instead of the sign-in form until SupabaseConfig has real values,
/// so the project still builds and runs before the backend exists.
private struct ConfigMissingView: View {
    var body: some View {
        AuthPage {
            AuthHeader(title: "Backend not configured",
                       subtitle: "Authentication needs a Supabase project.")

            VStack(alignment: .leading, spacing: 14) {
                Label("Create a project at supabase.com", systemImage: "1.circle")
                Label("Follow Eigenform/docs/AUTH_SETUP.md", systemImage: "2.circle")
                Label("Paste the URL and anon key into Auth/SupabaseConfig.swift",
                      systemImage: "3.circle")
            }
            .font(EF.body)
            .foregroundStyle(EF.ink)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EF.raised, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(EF.hairline))
            .padding(.top, 32)
        }
    }
}

#Preview {
    AuthFlowView()
        .environmentObject(AuthController())
}
