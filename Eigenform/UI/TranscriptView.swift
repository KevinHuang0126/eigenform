import SwiftUI

/// The full coaching log, opened from the coach chip during a set. Newest entry
/// at the bottom; auto-scrolls as entries arrive.
struct TranscriptView: View {
    let entries: [TranscriptEntry]
    /// Panel height. Shrinks in landscape (compact height) so the transcript doesn't
    /// swallow the shorter screen; see `SessionView`.
    var height: CGFloat = 150
    var onClose: (() -> Void)?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("COACHING LOG")
                    .font(EF.caption)
                    .kerning(1.5)
                    .foregroundStyle(EF.dim)
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(EF.dim)
                            .frame(width: 26, height: 26)
                            .background(EF.ink.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(EFPressStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(entries) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Self.timeFormatter.string(from: entry.date))
                                    .font(.system(.caption2, design: .rounded).monospacedDigit())
                                    .foregroundStyle(EF.faint)
                                Text(entry.count > 1 ? "\(entry.text) ×\(entry.count)" : entry.text)
                                    .font(.system(.callout, design: .rounded)
                                        .weight(entry.kind == .fault ? .semibold : .regular))
                                    .foregroundStyle(color(for: entry.kind))
                            }
                            .id(entry.id)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: entries)
                }
                // Keyed on the whole entry, not its id: a coalescing ×N bump mutates the
                // last row in place and must still scroll.
                .onChange(of: entries.last) { _, last in
                    guard let last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .frame(height: height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(EF.hairline))
    }

    private func color(for kind: TranscriptEntry.Kind) -> Color {
        switch kind {
        case .rep: return EF.emerald
        case .fault: return EF.coral
        case .guidance: return EF.teal
        case .info: return EF.dim
        }
    }
}
