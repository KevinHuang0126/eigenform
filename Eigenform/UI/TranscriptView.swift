import SwiftUI

/// The scrolling coaching transcript rendered over the camera feed. Newest entry
/// at the bottom; auto-scrolls as entries arrive.
struct TranscriptView: View {
    let entries: [TranscriptEntry]
    /// Panel height. Shrinks in landscape (compact height) so the transcript doesn't
    /// swallow the shorter screen; see `ContentView`.
    var height: CGFloat = 140

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Self.timeFormatter.string(from: entry.date))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                            Text(entry.count > 1 ? "\(entry.text) ×\(entry.count)" : entry.text)
                                .font(.callout.weight(entry.kind == .fault ? .bold : .regular))
                                .foregroundStyle(color(for: entry.kind))
                        }
                        .id(entry.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            // Keyed on the whole entry, not its id: a coalescing ×N bump mutates the
            // last row in place and must still scroll.
            .onChange(of: entries.last) { _, last in
                guard let last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .frame(height: height)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func color(for kind: TranscriptEntry.Kind) -> Color {
        switch kind {
        case .rep: return .green
        case .fault: return .orange
        case .guidance: return .yellow
        case .info: return .white.opacity(0.8)
        }
    }
}
