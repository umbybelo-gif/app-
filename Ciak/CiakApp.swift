import SwiftUI

@main
struct CiakApp: App {
    @State private var store = LibraryStore()
    @State private var auth = AuthManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(auth)
                .onChange(of: scenePhase) { _, phase in
                    auth.handleScenePhase(phase)
                }
        }
    }
}

struct RootView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        ZStack {
            switch auth.phase {
            case .needsSetup:
                PasswordSetupView()
                    .transition(.opacity)
            case .locked:
                LockView()
                    .transition(.opacity)
            case .unlocked:
                ProjectsView()
                    .transition(.opacity)
            }

            if auth.isObscured { PrivacyShield() }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.phase)
        .animation(.easeInOut(duration: 0.15), value: auth.isObscured)
    }
}
