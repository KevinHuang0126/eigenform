import SwiftUI

/// History sheet reached from the home screen: every saved set, grouped by
/// day, newest first. Rows lean on the same visual language as the home
/// cards — glyph well, rounded card, green for reps, coral only for faults.
struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("History")
                    .font(EF.display(30))
                    .foregroundStyle(EF.ink)
                    .padding(.top, 20)

                content
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: 480, alignment: .leading)
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
        .task { await history.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch history.phase {
        case .idle, .loading:
            ProgressView()
                .tint(EF.emerald)
                .frame(maxWidth: .infinity)
                .padding(.top, 120)

        case .failed(let message):
            VStack(spacing: 16) {
                EFErrorNote(message: message)
                EFPrimaryButton(title: "Try Again") {
                    Task { await history.refresh() }
                }
            }
            .padding(.top, 40)

        case .loaded:
            if history.records.isEmpty {
                emptyState
            } else {
                ForEach(WorkoutRecord.daySections(history.records), id: \.day) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(dayLabel(section.day))
                            .font(EF.caption)
                            .kerning(1.5)
                            .foregroundStyle(EF.dim)

                        ForEach(section.records) { record in
                            WorkoutRow(record: record)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("λ")
                .font(EF.display(44))
                .foregroundStyle(EF.bandGradient)
            Text("No sets yet")
                .font(EF.title)
                .foregroundStyle(EF.ink)
            Text("Finish a set and it lands here automatically.")
                .font(EF.body)
                .foregroundStyle(EF.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "TODAY" }
        if Calendar.current.isDateInYesterday(day) { return "YESTERDAY" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            .uppercased()
    }
}

/// One saved set: glyph well, movement + time + duration, rep total. Fault
/// count rides the subtitle in coral — the theme's one emphasis color.
private struct WorkoutRow: View {
    let record: WorkoutRecord

    var body: some View {
        HStack(spacing: 16) {
            Group {
                if let exercise = Exercise(rawValue: record.exercise) {
                    ExerciseGlyph(exercise: exercise)
                        .frame(width: 30, height: 30)
                } else {
                    // Row written by a newer build with an exercise this one
                    // doesn't know; still worth showing.
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 46, height: 46)
            .background(EF.iconGradient, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(EF.label)
                    .foregroundStyle(EF.ink)
                subtitle
                    .font(.system(.footnote, design: .rounded))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(record.reps)")
                    .font(EF.display(24))
                    .monospacedDigit()
                    .foregroundStyle(EF.emerald)
                Text(record.reps == 1 ? "REP" : "REPS")
                    .font(EF.caption)
                    .kerning(1.2)
                    .foregroundStyle(EF.faint)
            }
        }
        .padding(14)
        .background(EF.raised, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(EF.hairline))
    }

    private var title: String {
        Exercise(rawValue: record.exercise)?.displayName
            ?? record.exercise.capitalized
    }

    private var subtitle: Text {
        let time = record.performedAt.formatted(date: .omitted, time: .shortened)
        let seconds = max(0, Int(record.durationSeconds))
        let duration = String(format: "%d:%02d", seconds / 60, seconds % 60)
        let base = Text("\(time) · \(duration)").foregroundStyle(EF.dim)

        let cues = record.faults.reduce(0) { $0 + $1.count }
        guard cues > 0 else { return base }
        return base + Text(" · \(cues) \(cues == 1 ? "cue" : "cues")")
            .foregroundStyle(EF.coral)
    }
}

#Preview {
    HistoryView()
        .environmentObject(HistoryStore())
}
