import RoyalVNCKit
import SwiftUI

private struct ControlHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum Latch: String, CaseIterable, Identifiable {
    case command, option, control, shift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        }
    }

    var key: VNCKeyCode {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        case .shift: .shift
        }
    }
}

struct RemoteDesktopView: View {
    @EnvironmentObject private var session: VNCSession
    @AppStorage("remoteControlsVisible") private var controlsVisible = true
    @AppStorage("remoteScrollMode") private var scrollMode = false
    @State private var keyboardIsVisible = false
    @State private var showKeys = false
    @State private var keyboardOverlap: CGFloat = 0
    @State private var controlHeight: CGFloat = 0
    @State private var latched: Set<Latch> = []

    /// Full-screen center unless the keyboard or the open control bar actually covers the bottom.
    /// The corner Controls button does not count.
    private var coveredHeight: CGFloat {
        controlsVisible ? controlHeight : keyboardOverlap
    }
    private var heldModifiers: [VNCKeyCode] { Latch.allCases.filter { latched.contains($0) }.map(\.key) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if session.framebufferImage != nil {
                RemoteCanvasView(
                    session: session,
                    bottomInset: coveredHeight,
                    pinsContentToBottom: false,
                    scrollMode: scrollMode
                )
                .ignoresSafeArea()
            } else {
                connectingState
            }

            RemoteKeyboardBridge(
                session: session,
                isActive: $keyboardIsVisible,
                modifiers: heldModifiers,
                onModifiersConsumed: { latched.removeAll() }
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)

            VStack(spacing: 8) {
                statusPill
                    .padding(.top, 8)
                if scrollMode {
                    Text("ONE FINGER SCROLLS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(AppTheme.text)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                if let error = session.credentialStorageError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                }
                Spacer()
                bottomChrome
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            keyboardOverlap = Self.keyboardOverlap(from: note)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardOverlap = 0
        }
        .onPreferenceChange(ControlHeightKey.self) { controlHeight = $0 }
    }

    private var connectingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.tailBlue)
            Text(session.state.statusText)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(AppTheme.text)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.state == .connected ? AppTheme.connected : AppTheme.tailBlue)
                .frame(width: 7, height: 7)
            Text(session.state.statusText.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.2)
        }
        .foregroundStyle(AppTheme.text)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.14), lineWidth: 1) }
    }

    private var bottomChrome: some View {
        Group {
            if controlsVisible {
                VStack(spacing: 8) {
                    if showKeys || keyboardIsVisible {
                        keysRow
                    }
                    toolbar
                }
            } else {
                revealHandle
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background {
            GeometryReader { proxy in
                let top = proxy.frame(in: .global).minY
                let obstruction = controlsVisible ? max(0, UIScreen.main.bounds.maxY - top) : 0
                Color.clear.preference(key: ControlHeightKey.self, value: obstruction)
            }
        }
    }

    private var revealHandle: some View {
        Button {
            controlsVisible = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                Text("Controls")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(AppTheme.text)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.14), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                toolButton("Keyboard", systemImage: "keyboard", isActive: keyboardIsVisible, width: 68) {
                    keyboardIsVisible.toggle()
                    if keyboardIsVisible { showKeys = true }
                }
                toolButton("Prev", systemImage: "chevron.left", width: 52) {
                    session.pressKey(.leftArrow, modifiers: [.control])
                }
                toolButton("Next", systemImage: "chevron.right", width: 52) {
                    session.pressKey(.rightArrow, modifiers: [.control])
                }
                toolButton("Scroll", systemImage: "arrow.up.and.down", isActive: scrollMode, width: 56) {
                    scrollMode.toggle()
                }
                toolButton("Keys", systemImage: "command", isActive: showKeys || keyboardIsVisible, width: 52) {
                    showKeys.toggle()
                }
                toolButton("Hide", systemImage: "chevron.down", width: 48) {
                    controlsVisible = false
                    showKeys = false
                    controlHeight = 0
                }
                toolButton("End", systemImage: "xmark", role: .destructive, width: 48) {
                    keyboardIsVisible = false
                    session.disconnect()
                }
            }
            .padding(6)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var keysRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Latch.allCases) { latch in
                    keyChip(latch.title, isActive: latched.contains(latch)) {
                        if latched.contains(latch) {
                            latched.remove(latch)
                        } else {
                            latched.insert(latch)
                        }
                    }
                }
                chipDivider
                shortcutChip("⌘C", character: "c", extra: [.command])
                shortcutChip("⌘V", character: "v", extra: [.command])
                shortcutChip("⌘Z", character: "z", extra: [.command])
                shortcutChip("⌘A", character: "a", extra: [.command])
                shortcutChip("⌘X", character: "x", extra: [.command])
                shortcutChip("⌃C", character: "c", extra: [.control])
                chipDivider
                keyChip("Esc") { send(.escape) }
                keyChip("Tab") { send(.tab) }
                keyChip("Right") { session.click(.right) }
                keyChip("Desks") { session.pressKey(.upArrow, modifiers: [.control]) }
                chipDivider
                keyChip("←") { send(.leftArrow) }
                keyChip("→") { send(.rightArrow) }
                keyChip("↑") { send(.upArrow) }
                keyChip("↓") { send(.downArrow) }
                keyChip("Home") { send(.home) }
                keyChip("End") { send(.end) }
                keyChip("PgUp") { send(.pageUp) }
                keyChip("PgDn") { send(.pageDown) }
                keyChip("⌫") { send(.delete) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var chipDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.16))
            .frame(width: 1, height: 18)
    }

    private func toolButton(
        _ title: String,
        systemImage: String,
        isActive: Bool = false,
        role: ButtonRole? = nil,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(role == .destructive ? AppTheme.danger : (isActive ? AppTheme.tailBlue : AppTheme.text))
            .frame(width: width, height: 46)
            .background(isActive ? AppTheme.tailBlue.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func keyChip(_ title: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isActive ? AppTheme.tailBlue : AppTheme.text)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(isActive ? AppTheme.tailBlue.opacity(0.16) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func shortcutChip(_ title: String, character: Character, extra: [VNCKeyCode]) -> some View {
        keyChip(title) {
            guard let key = VNCKeyCode.withCharacter(character).first else { return }
            send(key, extra: extra)
        }
    }

    private func send(_ key: VNCKeyCode, extra: [VNCKeyCode] = []) {
        var modifiers = heldModifiers
        for modifier in extra where !modifiers.contains(modifier) {
            modifiers.append(modifier)
        }
        session.pressKey(key, modifiers: modifiers)
        latched.removeAll()
    }

    private static func keyboardOverlap(from note: Notification) -> CGFloat {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return 0 }
        return max(0, UIScreen.main.bounds.maxY - frame.minY)
    }
}
