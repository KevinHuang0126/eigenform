import SwiftUI

/// Shared chrome for the auth screens: fields, buttons, and the wordmark
/// header, all in the app's card language (raised white, hairline, mint CTA).

extension View {
    /// Field chrome shared by every text input on the auth screens.
    func efFieldChrome() -> some View {
        self
            .font(EF.body)
            .foregroundStyle(EF.ink)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(EF.raised, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(EF.hairline))
    }
}

/// Email field with the keyboard traits every screen needs.
struct EFEmailField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .efFieldChrome()
    }
}

/// Mint capsule CTA with a busy state, mirroring the summary screen's
/// "Go Again" button.
struct EFPrimaryButton: View {
    let title: String
    var isBusy = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(EF.label)
                    .foregroundStyle(EF.ink)
                    .opacity(isBusy ? 0 : 1)
                if isBusy {
                    ProgressView().tint(EF.ink)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(EF.mint, in: Capsule())
        }
        .buttonStyle(EFPressStyle())
        .disabled(isBusy)
    }
}

/// Quiet text button for secondary actions.
struct EFGhostButton: View {
    let title: String
    var tint: Color = EF.dim
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(EF.label)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(EFPressStyle())
    }
}

/// Inline error line, coral like the fault language elsewhere in the app.
struct EFErrorNote: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.system(.footnote, design: .rounded).weight(.medium))
            .foregroundStyle(EF.coral)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
    }
}

/// Wordmark header shared by the auth screens.
struct AuthHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EFLogoMark(size: 40)

            Text(title)
                .font(EF.display(34))
                .foregroundStyle(EF.ink)

            Text(subtitle)
                .font(EF.body)
                .foregroundStyle(EF.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "OR" divider between password and social sign-in.
struct AuthDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(EF.hairline).frame(height: 1)
            Text("OR")
                .font(EF.caption)
                .kerning(1.5)
                .foregroundStyle(EF.faint)
            Rectangle().fill(EF.hairline).frame(height: 1)
        }
    }
}
