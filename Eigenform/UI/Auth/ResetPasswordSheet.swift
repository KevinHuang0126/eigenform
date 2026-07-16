import SwiftUI

/// Presented when the user lands from a password-recovery email link (the
/// link itself signs them in; this finishes the job by setting a new password).
struct ResetPasswordSheet: View {
    @EnvironmentObject private var auth: AuthController
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirm = ""
    @State private var errorMessage: String?
    @State private var isBusy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose a new password")
                .font(EF.display(28))
                .foregroundStyle(EF.ink)
                .padding(.top, 32)

            Text("You're signed in — set a new password to finish the reset.")
                .font(EF.body)
                .foregroundStyle(EF.dim)
                .padding(.top, 8)

            VStack(spacing: 12) {
                SecureField("New password", text: $password)
                    .textContentType(.newPassword)
                    .efFieldChrome()
                SecureField("Confirm password", text: $confirm)
                    .textContentType(.newPassword)
                    .efFieldChrome()
            }
            .padding(.top, 28)

            Text("At least 8 characters.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(EF.faint)
                .padding(.top, 8)

            if let errorMessage {
                EFErrorNote(message: errorMessage)
                    .padding(.top, 12)
            }

            EFPrimaryButton(title: "Save Password", isBusy: isBusy) { save() }
                .padding(.top, 20)

            EFGhostButton(title: "Not now") {
                auth.needsPasswordReset = false
                dismiss()
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EF.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func save() {
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
                try await auth.updatePassword(password)
                dismiss()
            } catch {
                withAnimation { errorMessage = error.localizedDescription }
            }
            isBusy = false
        }
    }
}

#Preview {
    ResetPasswordSheet()
        .environmentObject(AuthController())
}
