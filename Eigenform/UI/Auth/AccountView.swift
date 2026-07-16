import SwiftUI

/// Account sheet reached from the home screen: profile editing, email and
/// password changes, sign-out, and the App Store-required account deletion.
struct AccountView: View {
    @EnvironmentObject private var auth: AuthController
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var newEmail = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""

    /// One inline status line per card, keyed by section, so feedback shows
    /// up next to the action that produced it.
    @State private var notes: [Section: Note] = [:]
    @State private var busySection: Section?
    @State private var confirmingDelete = false

    private enum Section: Hashable { case profile, email, password, danger }
    private struct Note {
        let text: String
        let isError: Bool
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                identity
                profileCard
                emailCard
                passwordCard
                dangerZone
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(EF.paper.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(EF.dim)
                    .frame(width: 34, height: 34)
                    .background(EF.raised, in: Circle())
                    .overlay(Circle().strokeBorder(EF.hairline))
            }
            .buttonStyle(EFPressStyle())
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
        .onAppear { name = auth.displayName }
    }

    // MARK: Cards

    private var identity: some View {
        VStack(spacing: 10) {
            Text(initial)
                .font(EF.display(30))
                .foregroundStyle(EF.emerald)
                .frame(width: 72, height: 72)
                .background(EF.mint.opacity(0.18), in: Circle())

            if !auth.displayName.isEmpty {
                Text(auth.displayName)
                    .font(EF.title)
                    .foregroundStyle(EF.ink)
            }

            Text(auth.email)
                .font(EF.body)
                .foregroundStyle(EF.dim)
        }
        .padding(.top, 16)
    }

    private var initial: String {
        let source = auth.displayName.isEmpty ? auth.email : auth.displayName
        return source.first.map { String($0).uppercased() } ?? "?"
    }

    private var profileCard: some View {
        card("PROFILE", section: .profile) {
            TextField("Display name", text: $name)
                .textContentType(.name)
                .efFieldChrome()

            EFPrimaryButton(title: "Save Name", isBusy: busySection == .profile) {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else {
                    note(.profile, "Enter a name first.", isError: true)
                    return
                }
                run(.profile, success: "Name updated.") {
                    try await auth.updateDisplayName(trimmed)
                }
            }
        }
    }

    private var emailCard: some View {
        card("EMAIL", section: .email) {
            EFEmailField(placeholder: "New email address", text: $newEmail)

            Text("Confirmation links go to both your current and new address; the change lands once both are confirmed.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(EF.faint)

            EFPrimaryButton(title: "Send Confirmation", isBusy: busySection == .email) {
                let address = newEmail.trimmingCharacters(in: .whitespaces)
                guard address.contains("@"), address.contains(".") else {
                    note(.email, "Enter a valid email address.", isError: true)
                    return
                }
                run(.email, success: "Check both inboxes to confirm the change.") {
                    try await auth.changeEmail(to: address)
                    newEmail = ""
                }
            }
        }
    }

    private var passwordCard: some View {
        card("PASSWORD", section: .password) {
            SecureField("New password", text: $newPassword)
                .textContentType(.newPassword)
                .efFieldChrome()
            SecureField("Confirm new password", text: $confirmPassword)
                .textContentType(.newPassword)
                .efFieldChrome()

            EFPrimaryButton(title: "Change Password", isBusy: busySection == .password) {
                guard newPassword.count >= 8 else {
                    note(.password, "Password must be at least 8 characters.", isError: true)
                    return
                }
                guard newPassword == confirmPassword else {
                    note(.password, "Passwords don't match.", isError: true)
                    return
                }
                run(.password, success: "Password changed.") {
                    try await auth.updatePassword(newPassword)
                    newPassword = ""
                    confirmPassword = ""
                }
            }
        }
    }

    private var dangerZone: some View {
        VStack(spacing: 4) {
            EFGhostButton(title: "Sign Out", tint: EF.ink) {
                Task {
                    await auth.signOut()
                    dismiss()
                }
            }

            EFGhostButton(title: "Delete Account", tint: EF.coral) {
                confirmingDelete = true
            }
            .confirmationDialog(
                "Delete your account? This permanently removes your account and can't be undone.",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    run(.danger, success: "") {
                        try await auth.deleteAccount()
                        dismiss()
                    }
                }
            }

            if let note = notes[.danger], note.isError {
                EFErrorNote(message: note.text)
            }
        }
        .padding(.top, 8)
    }

    // MARK: Chrome

    private func card<Content: View>(
        _ title: String, section: Section,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(EF.caption)
                .kerning(1.5)
                .foregroundStyle(EF.dim)

            content()

            if let note = notes[section] {
                if note.isError {
                    EFErrorNote(message: note.text)
                } else {
                    Label(note.text, systemImage: "checkmark.circle.fill")
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .foregroundStyle(EF.emerald)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(EF.raised, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(EF.hairline))
    }

    private func note(_ section: Section, _ text: String, isError: Bool) {
        withAnimation { notes[section] = Note(text: text, isError: isError) }
    }

    private func run(
        _ section: Section, success: String,
        _ intent: @escaping () async throws -> Void
    ) {
        notes[section] = nil
        busySection = section
        Task {
            do {
                try await intent()
                if !success.isEmpty { note(section, success, isError: false) }
            } catch {
                note(section, error.localizedDescription, isError: true)
            }
            busySection = nil
        }
    }
}

#Preview {
    AccountView()
        .environmentObject(AuthController())
}
