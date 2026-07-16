import SwiftUI

/// The moment of arrival: wordmark, one sentence, four movement cards, and the
/// privacy line. Cards stagger in on first appearance; everything else is
/// negative space.
struct HomeView: View {
    var onSelect: (Exercise) -> Void

    @State private var revealed = false
    @State private var showAccount = false
    @State private var showHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 28)

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                ForEach(Array(Exercise.allCases.enumerated()), id: \.element) { index, exercise in
                    ExerciseCard(exercise: exercise) { onSelect(exercise) }
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 24)
                        .animation(.spring(response: 0.55, dampingFraction: 0.8)
                            .delay(0.08 + Double(index) * 0.06), value: revealed)
                }
            }

            Spacer(minLength: 24)

            Label("On-device only. Video never leaves your phone.",
                  systemImage: "lock.fill")
                .font(EF.caption)
                .foregroundStyle(EF.faint)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EF.paper.ignoresSafeArea())
        .onAppear { revealed = true }
        .sheet(isPresented: $showAccount) { AccountView() }
        .sheet(isPresented: $showHistory) { HistoryView() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                EFLogoMark(size: 40)
                    .opacity(revealed ? 1 : 0)
                    .animation(.easeOut(duration: 0.6), value: revealed)

                Text("EigenForm")
                    .font(EF.display(38))
                    .foregroundStyle(EF.ink)

                Text("Pick a movement. I'll watch your form.")
                    .font(EF.body)
                    .foregroundStyle(EF.dim)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                headerButton("clock.arrow.circlepath") { showHistory = true }
                headerButton("person.fill") { showAccount = true }
            }
            .opacity(revealed ? 1 : 0)
            .animation(.easeOut(duration: 0.6), value: revealed)
        }
    }

    private func headerButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(EF.emerald)
                .frame(width: 42, height: 42)
                .background(EF.raised, in: Circle())
                .overlay(Circle().strokeBorder(EF.hairline))
        }
        .buttonStyle(EFPressStyle())
    }
}

/// One movement row: symbol well, name, camera-setup hint. The whole card is the
/// button; it sinks on press (see `EFPressStyle`).
private struct ExerciseCard: View {
    let exercise: Exercise
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ExerciseGlyph(exercise: exercise)
                    .frame(width: 32, height: 32)
                    .frame(width: 46, height: 46)
                    .background(EF.iconGradient, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.displayName)
                        .font(EF.title)
                        .foregroundStyle(EF.ink)
                    Text(exercise.setupHint)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(EF.dim)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(EF.faint)
            }
            .padding(16)
            .background(EF.raised, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(EF.hairline))
        }
        .buttonStyle(EFPressStyle())
    }
}

#Preview {
    HomeView { _ in }
        .environmentObject(AuthController())
}
