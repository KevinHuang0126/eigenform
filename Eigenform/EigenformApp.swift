import SwiftUI

@main
struct EigenformApp: App {
    @StateObject private var auth = AuthController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(auth.history)
                .preferredColorScheme(.light)
                .statusBarHidden()
                // OAuth callbacks and email links (verification, recovery,
                // email change) all arrive as eigenform:// URLs.
                .onOpenURL { auth.handleDeepLink($0) }
        }
    }
}

/// The auth gate: the workout flow only exists behind a session.
private struct RootView: View {
    @EnvironmentObject private var auth: AuthController

    var body: some View {
        ZStack {
            EF.paper.ignoresSafeArea()

            switch auth.phase {
            case .loading:
                EFLogoMark(size: 56)
                    .transition(.opacity)

            case .signedOut:
                AuthFlowView()
                    .transition(.opacity)

            case .signedIn:
                ContentView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: auth.phase)
        .sheet(isPresented: $auth.needsPasswordReset) {
            ResetPasswordSheet()
        }
    }
}
