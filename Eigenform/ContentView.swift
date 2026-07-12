import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WorkoutSessionViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.camera.permissionDenied {
                permissionDeniedView
            } else {
                CameraPreviewView(session: viewModel.camera.session)
                    .ignoresSafeArea()
                SkeletonOverlayView(frame: viewModel.skeleton)
                    .ignoresSafeArea()

                VStack {
                    HUDView(viewModel: viewModel)
                    Spacer()
                    TranscriptView(entries: viewModel.feedback.transcript)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
