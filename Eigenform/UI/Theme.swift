import SwiftUI

/// EigenForm's design language, derived entirely from the app icon: a white
/// skeleton-lambda over three diagonal bands of green. Every color here is either
/// sampled from that icon or derived from its greens.
///
/// Rules of the system:
/// - Green is the voice: reps, progress, anything "good" or interactive.
///   Mint/seafoam fill shapes; emerald is the same voice when it has to be text.
/// - Ink is content: numerals, primary labels. (Over live video, content stays
///   white — the camera feed is its own dark surface.)
/// - Coral is the single emphasis color, reserved for form faults.
/// - Everything else is negative space on paper-white surfaces.
enum EF {
    // MARK: Icon palette (sampled from AppIcon.png)

    /// Lightest band of the icon.
    static let mint = Color(red: 0x80 / 255, green: 0xE2 / 255, blue: 0xA6 / 255)
    /// Middle band.
    static let seafoam = Color(red: 0x61 / 255, green: 0xCB / 255, blue: 0xA1 / 255)
    /// Darkest band.
    static let teal = Color(red: 0x2F / 255, green: 0xB6 / 255, blue: 0xA1 / 255)
    /// The icon's greens driven dark enough to read as text on paper.
    static let emerald = Color(red: 0x12 / 255, green: 0x87 / 255, blue: 0x63 / 255)

    // MARK: Surfaces (paper-white, tinted faintly toward the icon's mint)

    /// App background.
    static let paper = Color(red: 0xF4 / 255, green: 0xFA / 255, blue: 0xF6 / 255)
    /// Raised cards and chips.
    static let raised = Color.white
    /// Primary text: near-black tinted toward the icon's teal.
    static let ink = Color(red: 0x0A / 255, green: 0x14 / 255, blue: 0x11 / 255)
    /// Hairline strokes on raised surfaces.
    static let hairline = ink.opacity(0.08)

    // MARK: Emphasis

    /// The one non-icon color: form faults only.
    static let coral = Color(red: 0xE2 / 255, green: 0x4C / 255, blue: 0x3B / 255)
    /// Secondary text.
    static let dim = ink.opacity(0.55)
    /// Tertiary text (timestamps, footnotes).
    static let faint = ink.opacity(0.34)

    // MARK: Over live video
    // The camera feed stays a dark, busy surface no matter the UI scheme, so
    // content drawn directly on it keeps the light treatment.
    static let onVideo = Color.white
    static let onVideoDim = Color.white.opacity(0.8)

    /// The icon's diagonal band gradient, deepened one stop so it holds up as
    /// display type on paper.
    static let bandGradient = LinearGradient(
        colors: [seafoam, teal, emerald],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// The icon's bands at their true values — surfaces that should read as a
    /// miniature of the icon itself (the exercise chips), where white artwork
    /// sits on top the way the lambda does.
    static let iconGradient = LinearGradient(
        colors: [mint, seafoam, teal],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: Typography
    // SF Rounded throughout — the icon's lambda is built from round-capped
    // strokes and circular joints, and the type should feel like the same pen.

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static let title = Font.system(.title2, design: .rounded).weight(.bold)
    static let body = Font.system(.body, design: .rounded)
    static let label = Font.system(.subheadline, design: .rounded).weight(.semibold)
    /// Uppercase micro-labels ("REPS", "DURATION").
    static let caption = Font.system(.caption, design: .rounded).weight(.semibold)
}

/// Shared press micro-interaction: cards and buttons sink slightly and dim,
/// with a spring release. Used everywhere so touch feels like one material.
struct EFPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

/// The lambda mark from the app icon (shape only, no background), carrying the
/// same band gradient the wordmark headers have always used.
struct EFLogoMark: View {
    var size: CGFloat = 40

    var body: some View {
        Image("LogoMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(EF.bandGradient)
            .frame(width: size, height: size)
    }
}

/// Circular glassy icon button used in the session chrome. `isActive` marks a
/// latched toggle (angle mode) by filling the circle mint, the same treatment as
/// the primary action capsules.
struct EFCircleButton: View {
    let systemName: String
    var isActive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(EF.ink)
                .frame(width: 42, height: 42)
                .background {
                    if isActive {
                        Circle().fill(EF.mint)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
                .overlay(Circle().strokeBorder(EF.hairline))
        }
        .buttonStyle(EFPressStyle())
    }
}
