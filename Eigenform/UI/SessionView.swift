import SwiftUI

/// The live set. Chrome is deliberately sparse — camera and skeleton own the
/// screen; everything else is glanceable from across a squat rack:
/// - top: leave, exercise identity, reset + camera flip
/// - bottom-left: hero rep counter that punches with a haptic on every rep
/// - bottom-right: End Set, the one full-color action on screen
/// - a floating coach chip surfaces the latest cue; tap it for the full log
struct SessionView: View {
    @ObservedObject var viewModel: WorkoutSessionViewModel
    /// Called when the user ends the set; parent decides what comes next.
    var onEnd: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var skeletonTint: Color = EF.mint
    @State private var showTranscript = false
    @State private var faultFlashTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            EF.paper.ignoresSafeArea()

            if viewModel.camera.permissionDenied {
                PermissionDeniedView()
            } else {
                CameraPreviewView(camera: viewModel.camera)
                    .ignoresSafeArea()
                SkeletonOverlayView(frame: viewModel.skeleton, tint: skeletonTint)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottomCluster
                }
                .padding(.horizontal, 16)
                .padding(.vertical, verticalSizeClass == .compact ? 6 : 10)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.repCount)
        .sensoryFeedback(.warning, trigger: viewModel.faultPulse)
        .onChange(of: viewModel.faultPulse) { _, _ in flashFault() }
        .onDisappear { faultFlashTask?.cancel() }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            EFCircleButton(systemName: "xmark", action: onEnd)

            Spacer()

            Label(viewModel.selectedExercise.displayName,
                  systemImage: viewModel.selectedExercise.symbolName)
                .font(EF.label)
                .foregroundStyle(EF.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(EF.hairline))

            Spacer()

            HStack(spacing: 10) {
                EFCircleButton(systemName: "arrow.counterclockwise") {
                    viewModel.resetSession()
                }
                EFCircleButton(systemName: "arrow.triangle.2.circlepath.camera") {
                    viewModel.camera.flipCamera()
                }
            }
        }
    }

    private var bottomCluster: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showTranscript {
                TranscriptView(entries: viewModel.feedback.transcript,
                               height: verticalSizeClass == .compact ? 90 : 150,
                               onClose: { showTranscript = false })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                CoachChip(entries: viewModel.feedback.transcript)
            }

            HStack(alignment: .bottom) {
                repHero
                Spacer()
                endButton
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showTranscript)
    }

    private var repHero: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("REPS")
                .font(EF.caption)
                .kerning(1.5)
                .foregroundStyle(EF.onVideoDim)
                .shadow(color: .black.opacity(0.4), radius: 4)

            Text("\(viewModel.repCount)")
                .font(EF.display(76))
                .monospacedDigit()
                .foregroundStyle(EF.onVideo)
                .contentTransition(.numericText(value: Double(viewModel.repCount)))
                .animation(.snappy(duration: 0.3), value: viewModel.repCount)
                .phaseAnimator([false, true], trigger: viewModel.repCount) { view, punch in
                    view.scaleEffect(punch ? 1.12 : 1.0, anchor: .bottomLeading)
                } animation: { punch in
                    punch ? .spring(response: 0.15, dampingFraction: 0.5)
                          : .spring(response: 0.4, dampingFraction: 0.7)
                }
                .shadow(color: .black.opacity(0.5), radius: 8)

            if !viewModel.phaseLabel.isEmpty {
                Text(viewModel.phaseLabel)
                    .font(EF.label)
                    .foregroundStyle(EF.emerald)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(EF.hairline))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.phaseLabel)
            }
        }
    }

    private var endButton: some View {
        Button(action: onEnd) {
            Text("End Set")
                .font(EF.label)
                .foregroundStyle(EF.ink)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(EF.mint, in: Capsule())
        }
        .buttonStyle(EFPressStyle())
    }

    /// Latest cue, floating above the rep counter. Tap toggles the full log.
    @ViewBuilder
    private func CoachChip(entries: [TranscriptEntry]) -> some View {
        // Re-evaluate every second so the chip retires quietly after its moment.
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if let entry = entries.last(where: { $0.kind != .rep }),
               timeline.date.timeIntervalSince(entry.date) < 6 {
                Button {
                    showTranscript = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: entry.kind == .fault
                              ? "exclamationmark.triangle.fill" : "waveform")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(entry.kind == .fault ? EF.coral : EF.emerald)
                        Text(entry.count > 1 ? "\(entry.text) ×\(entry.count)" : entry.text)
                            .font(EF.label)
                            .foregroundStyle(EF.ink)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(entry.kind == .fault
                                      ? EF.coral.opacity(0.4) : EF.hairline))
                }
                .buttonStyle(EFPressStyle())
                .id(entry.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Micro-interactions

    /// Coral flash on the skeleton when a fault fires, easing back to mint.
    private func flashFault() {
        faultFlashTask?.cancel()
        skeletonTint = EF.coral
        faultFlashTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { skeletonTint = EF.mint }
        }
    }
}

/// Camera permission was denied: explain and hand the user straight to Settings.
private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(EF.emerald)

            Text("EigenForm needs the camera\nto watch your form.")
                .font(EF.title)
                .foregroundStyle(EF.ink)
                .multilineTextAlignment(.center)

            Text("Video is analyzed on-device and never leaves your phone.")
                .font(EF.body)
                .foregroundStyle(EF.dim)
                .multilineTextAlignment(.center)

            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    Text("Open Settings")
                        .font(EF.label)
                        .foregroundStyle(EF.ink)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                        .background(EF.mint, in: Capsule())
                }
                .buttonStyle(EFPressStyle())
            }
        }
        .padding(32)
    }
}
