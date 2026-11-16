#if DEBUG
import RoyalVNCKit
import SwiftUI

// Show the real session controls without connecting to a Mac. Key presses are
// listed on screen instead of being sent anywhere. Never included in release builds.
struct RemoteToolbarTestView: View {
    @StateObject private var recorder = KeyRecorder()

    var body: some View {
        RemoteDesktopView()
            .environmentObject(recorder.session)
            .overlay(alignment: .topLeading) {
                Text(recorder.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.top, 52)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("sent-keys")
            }
    }

    @MainActor
    final class KeyRecorder: ObservableObject {
        @Published private(set) var log = "none"
        let session: VNCSession
        private var events: [String] = []

        init() {
            var record: (VNCKeyCode, Bool) -> Void = { _, _ in }
            session = VNCSession(startConnection: { _ in }) { _, key, isDown in record(key, isDown) }
            record = { [weak self] key, isDown in
                guard let self else { return }
                events.append("\(Self.name(key)) \(isDown ? "down" : "up")")
                log = events.joined(separator: ", ")
            }
            session.connect(hostname: "test.invalid", port: 5900, username: "", password: "")
        }

        private static func name(_ key: VNCKeyCode) -> String {
            switch key {
            case .command: return "command"
            case .space: return "space"
            case .return: return "return"
            default:
                if let scalar = Unicode.Scalar(key.rawValue), scalar.isASCII, scalar.properties.isAlphabetic {
                    return String(Character(scalar))
                }
                return String(key.rawValue, radix: 16)
            }
        }
    }
}
#endif
