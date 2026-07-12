import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WorkoutSessionViewModel()
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Landscape on iPhone reports compact height: the top/bottom chrome has to share
    /// a much shorter screen, so the transcript panel shrinks and padding tightens.
    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.camera.permissionDenied {
                permissionDeniedView
            } else {
                CameraPreviewView(camera: viewModel.camera)
                    .ignoresSafeArea()
                SkeletonOverlayView(frame: viewModel.skeleton)
                    .ignoresSafeArea()

                VStack {
                    HUDView(viewModel: viewModel)
                    Spacer()
                    TranscriptView(entries: viewModel.feedback.transcript,
                                   height: isCompactHeight ? 90 : 140)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, isCompactHeight ? 4 : 8)
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.system(size: 44))
            Text("Eigenform needs the camera to watch your form.")
                .multilineTextAlignment(.center)
            Text("Enable camera access in Settings → Eigenform.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(32)
    }
}

#Preview {
    ContentView()
}
