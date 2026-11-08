import SwiftUI

@main
struct TailRemoteApp: App {
    @StateObject private var session = VNCSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var session: VNCSession
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--test-remote-gestures") {
                RemoteGestureTestView()
            } else if ProcessInfo.processInfo.arguments.contains("--test-remote-toolbar") {
                RemoteToolbarTestView()
            } else if ProcessInfo.processInfo.arguments.contains("--test-credentials") {
                CredentialTestView()
            } else {
                connectionView
            }
            #else
            connectionView
            #endif
        }
        .animation(.easeInOut(duration: 0.22), value: session.showsRemoteScreen)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                session.appDidEnterBackground()
            case .active:
                session.appWillEnterForeground()
            default:
                break
            }
        }
    }

    private var connectionView: some View {
        Group {
            if session.showsRemoteScreen {
                RemoteDesktopView()
            } else {
                ConnectView()
            }
        }
    }
}
