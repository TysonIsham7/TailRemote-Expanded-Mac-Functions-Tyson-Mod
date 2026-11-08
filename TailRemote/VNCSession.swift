import Combine
import CoreGraphics
import Foundation
import OSLog
import QuartzCore
import RoyalVNCKit
import UIKit

enum RemoteConnectionState: Equatable {
    case idle
    case connecting
    case authenticating
    case loadingDesktop
    case connected
    case disconnecting
    case disconnected

    var statusText: String {
        switch self {
        case .idle: return "Ready"
        case .connecting: return "Connecting"
        case .authenticating: return "Signing in"
        case .loadingDesktop: return "Loading desktop"
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting"
        case .disconnected: return "Disconnected"
        }
    }
}

@MainActor
final class VNCSession: NSObject, ObservableObject, VNCConnectionDelegate, RemoteCanvasInput {
    @Published private(set) var state: RemoteConnectionState = .idle
    @Published private(set) var framebufferImage: CGImage?
    @Published private(set) var framebufferSize: CGSize = .zero
    @Published private(set) var cursorPoint: CGPoint = .zero
    @Published private(set) var lastError: String?
    @Published private(set) var credentialStorageError: String?
    let clickFeedback = PassthroughSubject<RemoteClickFeedback, Never>()

    private var connection: VNCConnection?
    private var framebuffer: VNCFramebuffer?
    /// Size the VNC server advertised. The published `framebufferSize` can be a
    /// larger pixel bitmap; mouse events are scaled back into this size.
    private var protocolSize: CGSize = .zero
    private var username = ""
    private var password = ""
    private let passwordStore: any RemotePasswordStoring
    private var passwordKeyToSave: RemoteCredentialKey?
    private var cursorIsInitialized = false
    private var hasPendingFrame = false
    private var displayLink: CADisplayLink?
    private let startConnection: (VNCConnection) -> Void
    private let sendWheelEvent: (VNCConnection, VNCMouseWheel, UInt16, UInt16, UInt32) -> Void
    private let sendKeyEvent: (VNCConnection, VNCKeyCode, Bool) -> Void
    private var connectionStartedAt: CFTimeInterval?
    private var closeWasRequested = false
    private var gracefulClosePending = false
    private var resumeTarget: RemoteResumeTarget?
    private var isBackgrounded = false
    private var reconnectWhenForeground = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let connectionLogger = Logger(subsystem: "TailRemote", category: "Connection")
    private var pendingWheels: [(VNCMouseWheel, UInt32)] = []
    private var wheelFlushScheduled = false
    private var pendingDirtyRects: [CGRect] = []
    private var copyFullFrame = true
    let frameComposer = IncrementalFramebuffer()

    /// Fraction of the Mac's pixel grid requested from Screen Sharing.
    ///
    /// 1, the default, keeps the full picture (2880×1800 on this Retina display).
    /// That grid is the coordinate space the Mac cursor uses, so a finger at the
    /// bottom or right edge of the picture lands on that edge.
    ///
    /// Below 1 asks screensharingd for a smaller picture. 0.5 is half the width
    /// and height (1440×900). The phone still maps the pointer across the whole
    /// view, but the events are in that smaller grid, so the Mac cursor stops
    /// about halfway down and across the desktop. Leave this at 1.
    ///
    /// Pinch zoom still enlarges whatever arrives. This does not change the Mac's
    /// own screen.
    static let appleServerScale: Double = 1
    /// Keys this session has sent key-down for and not yet key-up. Hardware
    /// modifiers stay here until the keyboard releases them.
    private var heldKeyCodes: Set<UInt32> = []

    init(
        passwordStore: any RemotePasswordStoring = KeychainPasswordStore(),
        startConnection: @escaping (VNCConnection) -> Void = { $0.connect() },
        sendWheelEvent: ((VNCConnection, VNCMouseWheel, UInt16, UInt16, UInt32) -> Void)? = nil,
        sendKeyEvent: @escaping (VNCConnection, VNCKeyCode, _ isDown: Bool) -> Void = { connection, key, isDown in
            if isDown {
                connection.keyDown(key)
            } else {
                connection.keyUp(key)
            }
        }
    ) {
        self.passwordStore = passwordStore
        self.startConnection = startConnection
        self.sendWheelEvent = sendWheelEvent ?? Self.transmitWheelClicks
        self.sendKeyEvent = sendKeyEvent
        super.init()
    }

    /// RoyalVNCKit enqueues the wheel button-down and then clears it locally
    /// without enqueueing the release. macOS Screen Sharing scrolls on the
    /// press transition, so a later sample with the button still down does
    /// nothing. A move at the same point transmits the release.
    private static func transmitWheelClicks(
        _ connection: VNCConnection,
        _ wheel: VNCMouseWheel,
        _ x: UInt16,
        _ y: UInt16,
        _ steps: UInt32
    ) {
        let count = max(Int(steps), 1)
        for _ in 0..<count {
            connection.mouseWheel(wheel, x: x, y: y, steps: 1)
            connection.mouseMove(x: x, y: y)
        }
    }

    var showsRemoteScreen: Bool {
        switch state {
        case .connecting, .authenticating, .loadingDesktop, .connected, .disconnecting:
            return true
        case .idle, .disconnected:
            return false
        }
    }

    func connect(hostname: String, port: UInt16, username: String, password: String, rememberPassword: Bool = false) {
        // An old connection may still have delegate tasks queued on MainActor.
        // Detach it before disconnecting, and check identity in every callback.
        connection?.delegate = nil
        connection?.disconnect()
        stopDisplayLink()
        connectionStartedAt = CACurrentMediaTime()
        closeWasRequested = false
        gracefulClosePending = false
        resumeTarget = RemoteResumeTarget(
            hostname: hostname.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            rememberPassword: rememberPassword
        )

        self.username = username
        self.password = password
        passwordKeyToSave = rememberPassword
            ? RemoteCredentialKey(hostname: hostname, port: port, username: username)
            : nil
        credentialStorageError = nil
        lastError = nil
        framebuffer = nil
        framebufferImage = nil
        framebufferSize = .zero
        protocolSize = .zero
        cursorPoint = .zero
        cursorIsInitialized = false
        hasPendingFrame = false
        pendingWheels.removeAll()
        pendingDirtyRects.removeAll()
        copyFullFrame = true
        frameComposer.reset()

        let settings = VNCConnection.Settings(
            isDebugLoggingEnabled: false,
            hostname: hostname,
            port: port,
            isShared: true,
            isScalingEnabled: false,
            useDisplayLink: false,
            inputMode: .forwardKeyboardShortcutsIfNotInUseLocally,
            isClipboardRedirectionEnabled: true,
            colorDepth: .depth24Bit,
            frameEncodings: .default,
            appleServerScale: Self.appleServerScale
        )

        let connection = VNCConnection(settings: settings)
        connection.delegate = self
        self.connection = connection
        updateState(.connecting)
        startConnection(connection)
    }

    func disconnect() {
        NotificationCenter.default.post(name: .tailRemoteSessionWillDisconnect, object: nil)
        resumeTarget = nil
        reconnectWhenForeground = false
        isBackgrounded = false
        endBackgroundTask()
        closeWasRequested = true
        gracefulClosePending = true
        lastError = nil
        heldKeyCodes.removeAll()
        guard let connection else {
            closeWasRequested = false
            updateState(.disconnected)
            return
        }
        updateState(.disconnecting)
        stopDisplayLink()
        hasPendingFrame = false
        pendingWheels.removeAll()
        pendingDirtyRects.removeAll()
        connection.disconnect()
    }

    func movePointer(
        viewDelta: CGPoint,
        viewSize: CGSize,
        zoomScale: CGFloat = RemoteGeometry.minimumZoomScale,
        displayScale: CGFloat = 1
    ) {
        flushWheels()
        initializeCursorIfNeeded()
        let framebufferDelta = RemoteGeometry.framebufferDelta(
            fromViewDelta: viewDelta,
            framebufferSize: framebufferSize,
            viewSize: viewSize,
            zoomScale: zoomScale,
            displayScale: displayScale
        )
        movePointer(
            toFramebufferPoint: CGPoint(x: cursorPoint.x + framebufferDelta.x, y: cursorPoint.y + framebufferDelta.y)
        )
    }

    func movePointer(toFramebufferPoint point: CGPoint) {
        guard framebufferSize.width > 0, framebufferSize.height > 0 else { return }
        cursorPoint = RemoteGeometry.clamp(point, to: framebufferSize)
        cursorIsInitialized = true
        let wire = wireCursor()
        connection?.mouseMove(x: wire.x, y: wire.y)
    }

    func mouseDown(_ button: VNCMouseButton) {
        flushWheels()
        initializeCursorIfNeeded()
        let wire = wireCursor()
        connection?.mouseButtonDown(button, x: wire.x, y: wire.y)
    }

    func mouseUp(_ button: VNCMouseButton) {
        flushWheels()
        initializeCursorIfNeeded()
        let wire = wireCursor()
        connection?.mouseButtonUp(button, x: wire.x, y: wire.y)
    }

    func click(_ button: VNCMouseButton, count: Int = 1) {
        for _ in 0..<max(count, 1) {
            mouseDown(button)
            mouseUp(button)
        }
        if state == .connected, connection != nil {
            clickFeedback.send(RemoteClickFeedback(point: cursorPoint, button: button, count: count))
        }
    }

    func scroll(_ wheel: VNCMouseWheel, steps: UInt32) {
        let count = max(steps, 1)
        if let index = pendingWheels.indices.last, pendingWheels[index].0 == wheel {
            pendingWheels[index].1 += count
        } else {
            pendingWheels.append((wheel, count))
        }
        scheduleWheelFlush()
    }

    func endScrollGesture() {
        flushWheels()
    }

    func sendText(_ text: String, modifiers: [VNCKeyCode] = []) {
        for character in text {
            if character.isNewline {
                pressKey(.return, modifiers: modifiers)
            } else {
                VNCKeyCode.withCharacter(character).forEach { pressKey($0, modifiers: modifiers) }
            }
        }
    }

    func pressKey(_ key: VNCKeyCode, modifiers: [VNCKeyCode] = []) {
        guard connection != nil else { return }
        let chord = RemoteKeyChord(modifiers: modifiers, alreadyHeld: heldKeyCodes)
        for event in chord.events(for: key) {
            switch event {
            case .down(let rawValue):
                keyDown(VNCKeyCode(rawValue))
            case .up(let rawValue):
                keyUp(VNCKeyCode(rawValue))
            }
        }
    }

    func keyDown(_ key: VNCKeyCode) {
        flushWheels()
        guard let connection else { return }
        sendKeyEvent(connection, key, true)
        heldKeyCodes.insert(key.rawValue)
    }

    func keyUp(_ key: VNCKeyCode) {
        heldKeyCodes.remove(key.rawValue)
        guard let connection else { return }
        sendKeyEvent(connection, key, false)
    }

    /// Types clipboard text into the focused remote field. See `RemoteClipboardPaste`.
    func pasteRemoteClipboard(_ text: String) {
        let actions = RemoteClipboardPaste.actions(for: text)
        guard !actions.isEmpty else { return }
        flushWheels()
        for action in actions {
            if case .key(let key, let modifiers) = action {
                pressKey(key, modifiers: modifiers)
            }
        }
    }

    /// Keeps the socket alive for the system's short background window. No background
    /// mode is declared: a continuous suspended VNC session would need a mode such as
    /// VoIP, and that capability is not free. When the window ends, or the peer drops
    /// the connection, the next foreground uses the saved password to reconnect.
    func appDidEnterBackground() {
        guard resumeTarget != nil, showsRemoteScreen else { return }
        isBackgrounded = true
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "TailRemote.session") { [weak self] in
            Task { @MainActor in
                self?.backgroundTimeExpired()
            }
        }
    }

    func appWillEnterForeground() {
        isBackgrounded = false
        endBackgroundTask()
        guard reconnectWhenForeground, resumeTarget?.rememberPassword == true else {
            reconnectWhenForeground = false
            return
        }
        // A close that started in the background may still be in flight. The
        // disconnected callback finishes the reconnect once the socket is gone.
        guard state == .disconnected || state == .idle else { return }
        reconnectWhenForeground = false
        reconnectWithSavedPassword()
    }

    /// True once after the user ends a session, or the peer closes it without a real failure.
    /// The connect form uses this to drop a password-load banner left over from before the session.
    func takeGracefulClose() -> Bool {
        let pending = gracefulClosePending
        gracefulClosePending = false
        return pending
    }

    /// Command-Space is the macOS default Spotlight shortcut. A Mac that remapped it won't open Spotlight.
    func openSpotlight() {
        pressKey(.space, modifiers: [.command])
    }

    private func backgroundTimeExpired() {
        if resumeTarget?.rememberPassword == true {
            reconnectWhenForeground = true
            closeWasRequested = true
            connection?.disconnect()
        }
        endBackgroundTask()
    }

    private func reconnectWithSavedPassword() {
        guard let target = resumeTarget, target.rememberPassword else { return }
        let key = RemoteCredentialKey(hostname: target.hostname, port: target.port, username: target.username)
        guard let saved = try? passwordStore.password(for: key), !saved.isEmpty else { return }
        connect(
            hostname: target.hostname,
            port: target.port,
            username: target.username,
            password: saved,
            rememberPassword: true
        )
    }

    private func endBackgroundTask() {
        let task = backgroundTask
        guard task != .invalid else { return }
        backgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }

    private func initializeCursorIfNeeded() {
        guard !cursorIsInitialized, framebufferSize.width > 0, framebufferSize.height > 0 else { return }
        cursorPoint = CGPoint(x: framebufferSize.width / 2, y: framebufferSize.height / 2)
        cursorIsInitialized = true
        let wire = wireCursor()
        connection?.mouseMove(x: wire.x, y: wire.y)
    }

    /// Local cursor space can be a Retina bitmap. RoyalVNC clamps pointer events to
    /// the advertised framebuffer, so scale that bitmap back onto the protocol edge.
    private func wireCursor() -> (x: UInt16, y: UInt16) {
        let source: CGPoint
        if protocolSize.width > 0,
           protocolSize.height > 0,
           framebufferSize != protocolSize {
            source = RemoteGeometry.protocolPoint(
                fromPixelPoint: cursorPoint,
                pixelSize: framebufferSize,
                protocolSize: protocolSize
            )
        } else {
            source = cursorPoint
        }
        return (UInt16(min(max(source.x, 0), 65535)), UInt16(min(max(source.y, 0), 65535)))
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 60, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkFired() {
        flushWheels()
        renderPendingFrame()
    }

    /// Coalesce wheel samples from one frame into one transmission per direction.
    private func scheduleWheelFlush() {
        if displayLink != nil {
            return
        }
        guard !wheelFlushScheduled else { return }
        wheelFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.wheelFlushScheduled = false
            self.flushWheels()
        }
    }

    private func flushWheels() {
        let batch = pendingWheels
        pendingWheels.removeAll()
        guard !batch.isEmpty, let connection else { return }
        initializeCursorIfNeeded()
        let wire = wireCursor()
        for (wheel, steps) in batch {
            sendWheelEvent(connection, wheel, wire.x, wire.y, steps)
        }
    }

    func renderPendingFrame() {
        guard hasPendingFrame, let framebuffer else { return }
        hasPendingFrame = false
        let width = Int(framebuffer.size.width)
        let height = Int(framebuffer.size.height)
        guard width > 0, height > 0 else { return }

        let rects: [CGRect]
        if copyFullFrame {
            rects = [CGRect(x: 0, y: 0, width: width, height: height)]
            copyFullFrame = false
            pendingDirtyRects.removeAll()
        } else {
            rects = pendingDirtyRects
            pendingDirtyRects.removeAll()
        }

        let composed = frameComposer.apply(
            source: framebuffer.surfaceAddress,
            width: width,
            height: height,
            dirtyRects: rects
        ) ?? framebuffer.cgImage
        if let image = composed {
            framebufferImage = image
            updatePointerSpace(bitmap: CGSize(width: CGFloat(image.width), height: CGFloat(image.height)))
            updateState(.connected)
        }
    }

    private func updateState(_ newState: RemoteConnectionState) {
        guard state != newState else { return }
        state = newState
        if let connectionStartedAt {
            let elapsed = CACurrentMediaTime() - connectionStartedAt
            // Only fixed stage names and elapsed time, never hosts or credentials.
            connectionLogger.info("\(newState.statusText, privacy: .public) after \(elapsed, privacy: .public) seconds")
        }
    }

    private func acceptsCallbacks(from connection: VNCConnection) -> Bool {
        self.connection === connection && state != .disconnecting && state != .disconnected
    }

    private func saveAuthenticatedPassword() {
        guard let key = passwordKeyToSave else { return }
        passwordKeyToSave = nil
        do {
            try passwordStore.save(password, for: key)
        } catch {
            credentialStorageError = "Connected, but the password couldn’t be saved on this iPhone."
        }
    }

    private func adoptFramebuffer(_ framebuffer: VNCFramebuffer) {
        guard self.framebuffer !== framebuffer else { return }
        self.framebuffer = framebuffer
        protocolSize = framebuffer.cgSize
        connectionLogger.info("Desktop \(Int(framebuffer.cgSize.width), privacy: .public) by \(Int(framebuffer.cgSize.height), privacy: .public)")
        framebufferImage = nil
        hasPendingFrame = false
        pendingDirtyRects.removeAll()
        copyFullFrame = true
        frameComposer.reset()
        updatePointerSpace(bitmap: nil)
        if cursorIsInitialized {
            cursorPoint = RemoteGeometry.clamp(cursorPoint, to: framebufferSize)
        } else {
            initializeCursorIfNeeded()
        }
        updateState(.loadingDesktop)
    }

    private func updatePointerSpace(bitmap: CGSize?) {
        let pixels = RemoteGeometry.pointerPixelSize(
            reportedSize: protocolSize,
            bitmapPixelSize: bitmap
        )
        guard pixels.width > 0, pixels.height > 0, pixels != framebufferSize else { return }
        if cursorIsInitialized, framebufferSize.width > 0, framebufferSize.height > 0 {
            cursorPoint = CGPoint(
                x: cursorPoint.x * pixels.width / framebufferSize.width,
                y: cursorPoint.y * pixels.height / framebufferSize.height
            )
        }
        framebufferSize = pixels
        if cursorIsInitialized {
            cursorPoint = RemoteGeometry.clamp(cursorPoint, to: framebufferSize)
        }
    }

    nonisolated func connection(
        _ connection: VNCConnection,
        stateDidChange connectionState: VNCConnection.ConnectionState
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.connection === connection else { return }
            switch connectionState.status {
            case .connecting:
                break
            case .connected:
                guard self.acceptsCallbacks(from: connection) else { return }
                self.saveAuthenticatedPassword()
                self.updateState(self.framebufferImage == nil ? .loadingDesktop : .connected)
            case .disconnecting:
                if self.isBackgrounded, self.resumeTarget?.rememberPassword == true, !self.closeWasRequested {
                    self.reconnectWhenForeground = true
                }
                self.updateState(.disconnecting)
                self.stopDisplayLink()
                self.hasPendingFrame = false
                self.pendingWheels.removeAll()
                self.pendingDirtyRects.removeAll()
            case .disconnected:
                let error = connectionState.error
                if self.isBackgrounded, self.resumeTarget?.rememberPassword == true, !self.closeWasRequested {
                    self.reconnectWhenForeground = true
                }
                let resumeNow = self.reconnectWhenForeground && !self.isBackgrounded && self.resumeTarget?.rememberPassword == true
                let expected = self.closeWasRequested || self.reconnectWhenForeground || error.map(RemoteSessionClose.isExpected) ?? true
                if expected {
                    self.lastError = nil
                    self.gracefulClosePending = true
                } else if let error {
                    self.lastError = error.localizedDescription
                    self.gracefulClosePending = false
                }
                self.closeWasRequested = false
                self.updateState(.disconnected)
                self.stopDisplayLink()
                self.connection?.delegate = nil
                self.connection = nil
                self.framebuffer = nil
                self.framebufferImage = nil
                self.hasPendingFrame = false
                self.pendingDirtyRects.removeAll()
                self.copyFullFrame = true
                self.frameComposer.reset()
                self.password = ""
                self.passwordKeyToSave = nil
                self.connectionStartedAt = nil
                if resumeNow {
                    self.reconnectWhenForeground = false
                    self.reconnectWithSavedPassword()
                }
            }
        }
    }

    nonisolated func connection(
        _ connection: VNCConnection,
        credentialFor authenticationType: VNCAuthenticationType,
        completion: @escaping (VNCCredential?) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.acceptsCallbacks(from: connection) else {
                completion(nil)
                return
            }

            guard !self.password.isEmpty else {
                completion(nil)
                return
            }

            if self.state == .connecting {
                self.updateState(.authenticating)
            }

            if authenticationType.requiresUsername, !self.username.isEmpty {
                completion(VNCUsernamePasswordCredential(username: self.username, password: self.password))
            } else if authenticationType.requiresPassword {
                completion(VNCPasswordCredential(password: self.password))
            } else {
                completion(nil)
            }
        }
    }

    nonisolated func connection(
        _ connection: VNCConnection,
        didCreateFramebuffer framebuffer: VNCFramebuffer
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.acceptsCallbacks(from: connection),
                  connection.framebuffer === framebuffer else { return }
            self.adoptFramebuffer(framebuffer)
        }
    }

    nonisolated func connection(
        _ connection: VNCConnection,
        didResizeFramebuffer framebuffer: VNCFramebuffer
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.acceptsCallbacks(from: connection),
                  connection.framebuffer === framebuffer else { return }
            self.adoptFramebuffer(framebuffer)
        }
    }

    nonisolated func connection(
        _ connection: VNCConnection,
        didUpdateFramebuffer framebuffer: VNCFramebuffer,
        x: UInt16,
        y: UInt16,
        width: UInt16,
        height: UInt16
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.acceptsCallbacks(from: connection),
                  connection.framebuffer === framebuffer else { return }
            self.adoptFramebuffer(framebuffer)
            let rect = CGRect(
                x: CGFloat(x),
                y: CGFloat(y),
                width: CGFloat(width),
                height: CGFloat(height)
            )
            self.noteDirtyRect(rect)
            self.hasPendingFrame = true
            if self.framebufferImage == nil {
                // Present the first available image immediately. Later updates
                // stay coalesced to the display cadence and copy only the
                // rectangles that changed.
                self.renderPendingFrame()
                self.startDisplayLink()
            }
        }
    }

    private func noteDirtyRect(_ rect: CGRect) {
        guard !copyFullFrame else { return }
        pendingDirtyRects.append(rect)
        if pendingDirtyRects.count > 24 {
            let union = pendingDirtyRects.reduce(CGRect.null) { $0.union($1) }
            pendingDirtyRects = [union]
        }
    }

    nonisolated func connection(_ connection: VNCConnection, didUpdateCursor cursor: VNCCursor) {
        // macOS Screen Sharing generally expects the client to draw its own pointer.
    }
}

struct RemoteResumeTarget: Equatable {
    var hostname: String
    var port: UInt16
    var username: String
    var rememberPassword: Bool
}

/// Whether a disconnect should be shown on the connect screen.
/// A user-requested end, a cancelled or closed VNC session, and POSIX 53
/// ("Software caused connection abort" / "Network error 53") are normal session ends.
enum RemoteSessionClose {
    static func isExpected(_ error: Error) -> Bool {
        if let vnc = error as? VNCError {
            switch vnc {
            case .connection(.cancelled), .connection(.closed):
                return true
            case .connection(.failed(let underlying)):
                return underlying.map(isConnectionAbort) ?? false
            case .connection(.closedDuringHandshake(_, let underlying)):
                return underlying.map(isConnectionAbort) ?? false
            default:
                return false
            }
        }
        return isConnectionAbort(error)
    }

    static func isConnectionAbort(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.code == 53 && (nsError.domain == NSPOSIXErrorDomain || nsError.domain == "NWErrorDomainPOSIX") {
            return true
        }
        let description = nsError.localizedDescription
        if description.localizedCaseInsensitiveContains("software caused connection abort")
            || description.localizedCaseInsensitiveContains("network error 53") {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error, !(underlying is NSError && (underlying as NSError) === nsError) {
            return isConnectionAbort(underlying)
        }
        return false
    }
}

/// Copies dirty rectangles out of the VNC surface into one bitmap.
/// A full-desktop Core Image render on every update stalled gestures, which
/// made UIKit collapse a swipe into a single capped scroll sample.
final class IncrementalFramebuffer {
    private var context: CGContext?
    private var width = 0
    private var height = 0
    private(set) var bytesCopied = 0

    func reset() {
        context = nil
        width = 0
        height = 0
        bytesCopied = 0
    }

    func apply(source: UnsafeRawPointer, width: Int, height: Int, dirtyRects: [CGRect]) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        if context == nil || self.width != width || self.height != height {
            let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            guard let created = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            ) else { return nil }
            context = created
            self.width = width
            self.height = height
        }

        guard let context, let destination = context.data else { return nil }
        for dirty in dirtyRects {
            let minX = max(0, Int(dirty.minX.rounded(.down)))
            let minY = max(0, Int(dirty.minY.rounded(.down)))
            let maxX = min(width, Int(dirty.maxX.rounded(.up)))
            let maxY = min(height, Int(dirty.maxY.rounded(.up)))
            guard maxX > minX, maxY > minY else { continue }
            let rowBytes = (maxX - minX) * 4
            for row in minY..<maxY {
                let offset = row * bytesPerRow + minX * 4
                destination.advanced(by: offset).copyMemory(
                    from: source.advanced(by: offset),
                    byteCount: rowBytes
                )
                bytesCopied += rowBytes
            }
        }
        return context.makeImage()
    }

    func pixel(x: Int, y: Int) -> [UInt8]? {
        guard let data = context?.data, x >= 0, y >= 0, x < width, y < height else { return nil }
        let start = (y * width + x) * 4
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        return [bytes[start], bytes[start + 1], bytes[start + 2], bytes[start + 3]]
    }
}

enum RemoteKeyEvent: Equatable {
    case down(UInt32)
    case up(UInt32)
}

/// Modifiers a `pressKey` chord presses itself. Keys already down stay down.
struct RemoteKeyChord: Equatable {
    let ownedModifiers: [VNCKeyCode]

    init(modifiers: [VNCKeyCode], alreadyHeld: Set<UInt32>) {
        var owned: [VNCKeyCode] = []
        for modifier in modifiers {
            if alreadyHeld.contains(modifier.rawValue) { continue }
            if owned.contains(modifier) { continue }
            owned.append(modifier)
        }
        ownedModifiers = owned
    }

    func events(for key: VNCKeyCode) -> [RemoteKeyEvent] {
        var events = ownedModifiers.map { RemoteKeyEvent.down($0.rawValue) }
        events.append(.down(key.rawValue))
        events.append(.up(key.rawValue))
        events.append(contentsOf: ownedModifiers.reversed().map { RemoteKeyEvent.up($0.rawValue) })
        return events
    }
}
