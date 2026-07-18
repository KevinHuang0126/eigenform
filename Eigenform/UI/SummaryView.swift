import SwiftUI

/// The moment of completion. The rep total counts up in the icon's gradient,
/// stats stay quiet, and form notes give the set a takeaway. A clean set gets
/// its moment of praise instead of an empty list.
struct SummaryView: View {
    let summary: SessionSummary
    var onAgain: () -> Void
    var onDone: () -> Void

    @State private var shownReps = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(summary.exercise.displayName)
                .font(EF.label)
                .foregroundStyle(EF.dim)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(EF.raised, in: Capsule())
                .overlay(Capsule().strokeBorder(EF.hairline))

            Text("\(shownReps)")
                .font(EF.display(96))
                .monospacedDigit()
                .foregroundStyle(EF.bandGradient)
                .contentTransition(.numericText(value: Double(shownReps)))
                .padding(.top, 18)

            Text(summary.reps == 1 ? "REP" : "REPS")
                .font(EF.caption)
                .kerning(2)
                .foregroundStyle(EF.dim)

            HStack(spacing: 12) {
                StatTile(label: "DURATION", value: formattedDuration)
                StatTile(label: "FORM CUES", value: "\(totalFaults)",
                         valueColor: totalFaults == 0 ? EF.emerald : EF.coral)
            }
            .padding(.top, 28)

            formNotes
                .padding(.top, 12)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onAgain) {
                    Text("Go Again")
                        .font(EF.label)
                        .foregroundStyle(EF.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(EF.mint, in: Capsule())
                }
                .buttonStyle(EFPressStyle())

                Button(action: onDone) {
                    Text("Done")
                        .font(EF.label)
                        .foregroundStyle(EF.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(EFPressStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EF.paper.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.9).delay(0.15)) {
                shownReps = summary.reps
            }
        }
        .sensoryFeedback(.success, trigger: shownReps == summary.reps && summary.reps > 0)
    }

    private var totalFaults: Int {
        summary.faults.reduce(0) { $0 + $1.count }
    }

    private var formattedDuration: String {
        let seconds = max(0, Int(summary.duration))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @ViewBuilder
    private var formNotes: some View {
        if summary.faults.isEmpty {
            Label("Clean set — no form faults.", systemImage: "checkmark.seal.fill")
                .font(EF.body)
                .foregroundStyle(EF.emerald)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(EF.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("WORK ON")
                    .font(EF.caption)
                    .kerning(1.5)
                    .foregroundStyle(EF.dim)
                ForEach(summary.faults, id: \.text) { fault in
                    HStack(alignment: .firstTextBaseline) {
                        Text(fault.text)
                            .font(EF.body)
                            .foregroundStyle(EF.ink)
                        Spacer()
                        Text("×\(fault.count)")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(EF.coral)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(EF.raised, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(EF.hairline))
        }
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    var valueColor: Color = EF.ink

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(EF.display(28))
                .monospacedDigit()
                .foregroundStyle(valueColor)
            Text(label)
                .font(EF.caption)
                .kerning(1.5)
                .foregroundStyle(EF.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(EF.raised, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(EF.hairline))
    }
}

#Preview {
    SummaryView(summary: SessionSummary(
        exercise: .squat, reps: 12, duration: 95,
        faults: [(text: "Keep your heels down", count: 3),
                 (text: "Squat deeper", count: 1)]),
        onAgain: {}, onDone: {})
}
