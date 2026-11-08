import GameController
import RoyalVNCKit
import SwiftUI
import UIKit

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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject private var session: VNCSession
    @AppStorage("remoteControlsVisible") private var controlsVisible = true
    @AppStorage("remoteScrollMode") private var scrollMode = false
    @AppStorage("remoteKeyboardHeight") private var rememberedKeyboardHeight = 336.0
    @State private var keyboardIsVisible = false
    @State private var trackpadMode = false
    @State private var openKeyboardAfterTrackpadCloses = false
    @State private var showKeys = false
    @State private var keyboardOverlap: CGFloat = 0
    @State private var controlHeight: CGFloat = 0
    @State private var latched: Set<Latch> = []
    @State private var hardwareKeyboardConnected = GCKeyboard.coalesced != nil

    /// Regular width and height is an iPad window large enough for the pad chrome.
    /// iPhone, Slide Over, and a narrow Split View stay on the phone layout.
    private var usesPadLayout: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }

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
                isActive: Binding(
                    get: { keyboardIsVisible && !hardwareKeyboardConnected },
                    set: { keyboardIsVisible = $0 }
                ),
                modifiers: heldModifiers,
                onModifiersConsumed: { latched.removeAll() }
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)

            RemoteHardwareKeyboard(session: session, captureEnabled: hardwareKeyboardConnected)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                topBar
                    .padding(.top, usesPadLayout ? 16 : 8)
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
                VStack(spacing: 0) {
                    bottomChrome
                    if trackpadMode {
                        RemoteTrackpadPanel(session: session, commandHeld: latched.contains(.command)) {
                            if latched.contains(.command) {
                                latched.remove(.command)
                            } else {
                                latched.insert(.command)
                            }
                        }
                        .frame(height: trackpadHeight)
                    }
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            keyboardOverlap = Self.keyboardOverlap(from: note)
            if keyboardOverlap > 50 {
                rememberedKeyboardHeight = keyboardOverlap
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardOverlap = 0
        }
        .onChange(of: trackpadMode) { _, isOn in
            guard !isOn, openKeyboardAfterTrackpadCloses else { return }
            openKeyboardAfterTrackpadCloses = false
            keyboardIsVisible = true
            showKeys = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidConnect)) { _ in
            hardwareKeyboardConnected = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidDisconnect)) { _ in
            hardwareKeyboardConnected = GCKeyboard.coalesced != nil
        }
        .onAppear(perform: dismissLeftoverKeyboard)
    }

    /// The password field can still be first responder when this screen appears.
    /// Resign it so the session controls are not covered by that keyboard.
    private func dismissLeftoverKeyboard() {
        guard !keyboardIsVisible else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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

    private var topBar: some View {
        HStack(spacing: 8) {
            statusPill
            Spacer(minLength: 8)
            // Disconnect stays at the top. On iPhone the bottom toolbar is wider
            // than the screen, so End is clipped to a sliver in the home-indicator
            // strip and cannot be tapped. The password keyboard also covers that bar.
            endSessionButton
        }
        .padding(.horizontal, usesPadLayout ? 28 : 12)
    }

    private var endSessionButton: some View {
        Button(role: .destructive) {
            keyboardIsVisible = false
            trackpadMode = false
            showKeys = false
            dismissLeftoverKeyboard()
            session.disconnect()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                Text("End")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(AppTheme.danger)
            .frame(width: 56, height: 44)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarButtonStyle())
        .accessibilityLabel("End")
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
                VStack(spacing: usesPadLayout ? 10 : 8) {
                    if showKeys || keyboardIsVisible {
                        if usesPadLayout {
                            padKeys
                        } else {
                            keysRow
                        }
                    }
                    if usesPadLayout {
                        padToolbar
                    } else {
                        toolbar
                    }
                }
            } else {
                revealHandle
            }
        }
        .padding(.horizontal, usesPadLayout ? 28 : 12)
        .padding(.bottom, usesPadLayout ? 18 : 8)
        .frame(maxWidth: usesPadLayout ? 880 : nil)
        .frame(maxWidth: usesPadLayout ? .infinity : nil)
        .background {
            WindowCoverageReader(isActive: controlsVisible) { controlHeight = $0 }
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


    private var padToolbar: some View {
        ViewThatFits(in: .horizontal) {
            padToolbarButtons
                .fixedSize(horizontal: true, vertical: false)
            ScrollView(.horizontal, showsIndicators: false) {
                padToolbarButtons
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var padToolbarButtons: some View {
        HStack(spacing: 6) {
            toolButton("Keyboard", systemImage: "keyboard", isActive: keyboardIsVisible, width: 88, height: 52) {
                if keyboardIsVisible {
                    trackpadMode = false
                    keyboardIsVisible = false
                } else if trackpadMode {
                    openKeyboardAfterTrackpadCloses = true
                    trackpadMode = false
                } else {
                    keyboardIsVisible = true
                    showKeys = true
                }
            }
            toolButton("Trackpad", systemImage: "hand.draw", isActive: trackpadMode, width: 88, height: 52) {
                if trackpadMode {
                    trackpadMode = false
                } else {
                    keyboardIsVisible = false
                    trackpadMode = true
                }
            }
            toolButton("Spotlight", systemImage: "magnifyingglass", width: 88, height: 52) {
                openSpotlight()
            }
            moreMenu
            toolButton("Scroll", systemImage: "arrow.up.and.down", isActive: scrollMode, width: 72, height: 52) {
                scrollMode.toggle()
            }
            toolButton("Keys", systemImage: "command", isActive: showKeys || keyboardIsVisible, width: 68, height: 52) {
                showKeys.toggle()
            }
            toolButton("Hide", systemImage: "chevron.down", width: 64, height: 52) {
                controlsVisible = false
                showKeys = false
                controlHeight = 0
            }
        }
    }

    private var padKeys: some View {
        VStack(alignment: .leading, spacing: 8) {
            fittingRow {
                latchChips(prominent: true)
                chipDivider
                shortcutChips(prominent: true)
            }
            fittingRow {
                navigationChips(prominent: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private func fittingRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8, content: content)
                .fixedSize(horizontal: true, vertical: false)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8, content: content)
            }
        }
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                toolButton("Keyboard", systemImage: "keyboard", isActive: keyboardIsVisible, width: 68) {
                    if keyboardIsVisible {
                        trackpadMode = false
                        keyboardIsVisible = false
                    } else if trackpadMode {
                        // The keyboard field resigns while the trackpad panel leaves
                        // the tree, and that dismiss clears the button. Open it
                        // after the panel is gone.
                        openKeyboardAfterTrackpadCloses = true
                        trackpadMode = false
                    } else {
                        keyboardIsVisible = true
                        showKeys = true
                    }
                }
                toolButton("Trackpad", systemImage: "hand.draw", isActive: trackpadMode, width: 68) {
                    if trackpadMode {
                        trackpadMode = false
                    } else {
                        keyboardIsVisible = false
                        trackpadMode = true
                    }
                }
                toolButton("Spotlight", systemImage: "magnifyingglass", width: 60) {
                    openSpotlight()
                }
                moreMenu
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
                keyChip("End", accessibilityLabel: "End key") { send(.end) }
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
        height: CGFloat = 46,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: height > 46 ? 17 : 15, weight: .semibold))
                Text(title)
                    .font(.system(size: height > 46 ? 11 : 9, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(role == .destructive ? AppTheme.danger : (isActive ? AppTheme.tailBlue : AppTheme.text))
            .frame(width: width, height: height)
            .background(isActive ? AppTheme.tailBlue.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier("toolbar-\(title.lowercased())")
    }

    /// Prev and Next moved here so Paste fits without another wide control on a ~420pt screen.
    private var moreMenu: some View {
        Menu {
            Button {
                pasteClipboard()
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            .accessibilityIdentifier("toolbar-paste")

            Button {
                session.pressKey(.leftArrow, modifiers: [.control])
            } label: {
                Label("Prev", systemImage: "chevron.left")
            }
            .accessibilityIdentifier("toolbar-prev")

            Button {
                session.pressKey(.rightArrow, modifiers: [.control])
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .accessibilityIdentifier("toolbar-next")
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                Text("More")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(AppTheme.text)
            .frame(width: 48, height: 46)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
        .accessibilityIdentifier("toolbar-more")
    }

    private func pasteClipboard() {
        session.pasteRemoteClipboard(clipboardText())
    }

    private func clipboardText() -> String {
        #if DEBUG
        if let injected = ProcessInfo.processInfo.environment["TAILREMOTE_PASTE_TEXT"] {
            return injected
        }
        #endif
        return UIPasteboard.general.string ?? ""
    }

    private func latchChips(prominent: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(Latch.allCases) { latch in
                keyChip(latch.title, isActive: latched.contains(latch), prominent: prominent) {
                    if latched.contains(latch) {
                        latched.remove(latch)
                    } else {
                        latched.insert(latch)
                    }
                }
            }
        }
    }

    private func shortcutChips(prominent: Bool) -> some View {
        HStack(spacing: 8) {
            shortcutChip("⌘C", character: "c", extra: [.command], prominent: prominent)
            shortcutChip("⌘V", character: "v", extra: [.command], prominent: prominent)
            shortcutChip("⌘Z", character: "z", extra: [.command], prominent: prominent)
            shortcutChip("⌘A", character: "a", extra: [.command], prominent: prominent)
            shortcutChip("⌘X", character: "x", extra: [.command], prominent: prominent)
            shortcutChip("⌃C", character: "c", extra: [.control], prominent: prominent)
        }
    }

    private func navigationChips(prominent: Bool) -> some View {
        HStack(spacing: 8) {
            keyChip("Esc", prominent: prominent) { send(.escape) }
            keyChip("Tab", prominent: prominent) { send(.tab) }
            keyChip("Right", prominent: prominent) { session.click(.right) }
            keyChip("Desks", prominent: prominent) { session.pressKey(.upArrow, modifiers: [.control]) }
            chipDivider
            keyChip("←", prominent: prominent) { send(.leftArrow) }
            keyChip("→", prominent: prominent) { send(.rightArrow) }
            keyChip("↑", prominent: prominent) { send(.upArrow) }
            keyChip("↓", prominent: prominent) { send(.downArrow) }
            keyChip("Home", prominent: prominent) { send(.home) }
            keyChip("End", prominent: prominent, accessibilityLabel: "End key") { send(.end) }
            keyChip("PgUp", prominent: prominent) { send(.pageUp) }
            keyChip("PgDn", prominent: prominent) { send(.pageDown) }
            keyChip("⌫", prominent: prominent) { send(.delete) }
        }
    }

    private func keyChip(
        _ title: String,
        isActive: Bool = false,
        prominent: Bool = false,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: prominent ? 15 : 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isActive ? AppTheme.tailBlue : AppTheme.text)
                .padding(.horizontal, prominent ? 12 : 10)
                .frame(height: prominent ? 36 : 32)
                .background(isActive ? AppTheme.tailBlue.opacity(0.16) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
    }

    /// Borderless buttons report a frame but no hit point, so a tap never lands.
    private struct ToolbarButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.6 : 1)
        }
    }

    private func shortcutChip(_ title: String, character: Character, extra: [VNCKeyCode], prominent: Bool = false) -> some View {
        keyChip(title, prominent: prominent) {
            guard let key = VNCKeyCode.withCharacter(character).first else { return }
            send(key, extra: extra)
        }
    }

    /// Latched modifiers are dropped so the first typed letter reaches Spotlight as plain text.
    private var trackpadHeight: CGFloat {
        let measured = keyboardOverlap > 50 ? keyboardOverlap : rememberedKeyboardHeight
        return min(max(measured, 240), 420)
    }

    private func openSpotlight() {
        latched.removeAll()
        trackpadMode = false
        session.openSpotlight()
        keyboardIsVisible = true
        showKeys = true
    }

    private func send(_ key: VNCKeyCode, extra: [VNCKeyCode] = []) {
        var modifiers = heldModifiers
        for modifier in extra where !modifiers.contains(modifier) {
            modifiers.append(modifier)
        }
        session.pressKey(key, modifiers: modifiers)
        latched.removeAll()
    }

    /// Keyboard frames are in screen coordinates. Compare them with this window, not
    /// the full display, so Split View and Stage Manager only inset the covered part.
    private static func keyboardOverlap(from note: Notification) -> CGFloat {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              frame.height > 1,
              let window = RemoteWindow.keyWindow else {
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return 0 }
            return max(0, UIScreen.main.bounds.maxY - frame.minY)
        }
        let windowFrame = window.convert(window.bounds, to: nil)
        return max(0, windowFrame.maxY - frame.minY)
    }
}

private enum RemoteWindow {
    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

/// Distance from this chrome to the bottom of its window. The corner Controls
/// button reports nothing, matching the previous full-screen measurement.
private struct WindowCoverageReader: UIViewRepresentable {
    var isActive: Bool
    var onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> CoverageProbe {
        let view = CoverageProbe()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onChange = onChange
        view.isActive = isActive
        return view
    }

    func updateUIView(_ view: CoverageProbe, context: Context) {
        view.onChange = onChange
        view.isActive = isActive
        view.report()
    }

    final class CoverageProbe: UIView {
        var isActive = false
        var onChange: ((CGFloat) -> Void)?
        private var lastReported: CGFloat = -1

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        func report() {
            guard let window, bounds.height > 0 else { return }
            let frame = convert(bounds, to: window)
            let coverage = isActive ? max(0, window.bounds.maxY - frame.minY) : 0
            guard abs(coverage - lastReported) > 0.5 else { return }
            lastReported = coverage
            DispatchQueue.main.async { [weak self] in
                guard let self, abs(self.lastReported - coverage) <= 0.5 else { return }
                self.onChange?(coverage)
            }
        }
    }
}
