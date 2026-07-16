import SwiftUI

/// Flow coordinator: home (pick a movement) → live session → set summary.
/// The camera runs only while the session screen is on stage — `SessionView`'s
/// appear/disappear drive `start()`/`stop()`, so navigation is the lifecycle.
struct ContentView: View {
    private enum Phase {
        case home
        case session
        case summary
    }

    @StateObject private var viewModel = WorkoutSessionViewModel()
    @EnvironmentObject private var history: HistoryStore
    @State private var phase: Phase = .home
    @State private var summary: SessionSummary?

    var body: some View {
        ZStack {
            EF.paper.ignoresSafeArea()

            switch phase {
            case .home:
                HomeView { exercise in
                    viewModel.selectedExercise = exercise
                    go(to: .session)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

            case .session:
                SessionView(viewModel: viewModel, onEnd: endSet)
                    .onAppear { viewModel.start() }
                    .onDisappear { viewModel.stop() }
                    .transition(.opacity)

            case .summary:
                if let summary {
                    SummaryView(summary: summary,
                                onAgain: { go(to: .session) },
                                onDone: { go(to: .home) })
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity))
                }
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: phase)
    }

    /// An empty set (no reps, no faults) has nothing to summarize — go home.
    private func endSet() {
        let result = viewModel.makeSummary()
        if result.reps == 0 && result.faults.isEmpty {
            go(to: .home)
        } else {
            history.save(result)
            summary = result
            go(to: .summary)
        }
        viewModel.resetSession()
    }

    private func go(to newPhase: Phase) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            phase = newPhase
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthController())
        .environmentObject(HistoryStore())
}
