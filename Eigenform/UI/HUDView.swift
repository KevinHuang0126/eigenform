import SwiftUI

/// Top-of-screen controls and status: exercise picker, rep counter, phase label,
/// camera flip and session reset.
struct HUDView: View {
    @ObservedObject var viewModel: WorkoutSessionViewModel

    var body: some View {
        VStack(spacing: 12) {
            Picker("Exercise", selection: $viewModel.selectedExercise) {
                ForEach(Exercise.allCases) { exercise in
                    Text(exercise.displayName).tag(exercise)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.repCount)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(viewModel.phaseLabel)
                        .font(.headline)
                        .foregroundStyle(.yellow)
                }
                Spacer()
                VStack(spacing: 16) {
                    Button {
                        viewModel.camera.flipCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title2)
                    }
                    Button {
                        viewModel.resetSession()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title2)
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .padding(12)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
