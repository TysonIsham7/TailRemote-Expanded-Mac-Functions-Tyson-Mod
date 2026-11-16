import Combine
import XCTest
@testable import RoyalVNCKit
@testable import TailRemote

@MainActor
final class VNCSessionTests: XCTestCase {
    private var connections: [VNCConnection] = []
    private var session: VNCSession!
    private var passwordStore: TestPasswordStore!
    private var keyEvents: [KeyEvent] = []
    private var wheelEvents: [WheelEvent] = []

    private struct KeyEvent: Equatable {
        let key: VNCKeyCode
        let isDown: Bool
    }

    private struct WheelEvent: Equatable {
        let wheel: VNCMouseWheel
        let steps: UInt32
    }

    override func setUp() async throws {
        connections = []
        keyEvents = []
        wheelEvents = []
        passwordStore = TestPasswordStore()
        // Use real connection/framebuffer objects, with no network connection.
        session = VNCSession(
            passwordStore: passwordStore,
            startConnection: { [weak self] in self?.connections.append($0) },
            sendWheelEvent: { [weak self] _, wheel, _, _, steps in
                self?.wheelEvents.append(WheelEvent(wheel: wheel, steps: steps))
            },
            sendKeyEvent: { [weak self] _, key, isDown in self?.keyEvents.append(KeyEvent(key: key, isDown: isDown)) }
        )
    }

    override func tearDown() async throws {
        session.disconnect()
        await drainCallbacks()
        session = nil
        connections = []
        keyEvents = []
        wheelEvents = []
    }

    func testFullResolutionPointerReachesTheMacDesktopEdge() async throws {
        XCTAssertEqual(
            VNCSession.appleServerScale,
            1,
            "A scale of 0.5 requests a 1440×900 picture on a 2880×1800 Mac. Pointer events stay in that smaller grid, so the Mac cursor stops halfway."
        )

        let connection = connect()
        XCTAssertEqual(connection.settings.appleServerScale, 1)

        let desktop = CGSize(width: 2880, height: 1800)
        let picture = CGSize(
            width: desktop.width * CGFloat(VNCSession.appleServerScale),
            height: desktop.height * CGFloat(VNCSession.appleServerScale)
        )
        let image = CGRect(x: 8, y: 20, width: 390, height: 390 * picture.height / picture.width)
        let far = RemoteGeometry.framebufferPoint(
            fromViewPoint: CGPoint(x: image.maxX, y: image.maxY),
            imageRect: image,
            framebufferSize: picture,
            displayScale: 3
        )
        let wire = RemoteGeometry.protocolPoint(
            fromPixelPoint: far,
            pixelSize: picture,
            protocolSize: picture
        )
        let halfImage = CGRect(x: image.minX, y: image.minY, width: image.width, height: image.width * 900 / 1440)
        let halfway = RemoteGeometry.framebufferPoint(
            fromViewPoint: CGPoint(x: halfImage.maxX, y: halfImage.maxY),
            imageRect: halfImage,
            framebufferSize: CGSize(width: 1440, height: 900),
            displayScale: 3
        )
        XCTAssertEqual(halfway.y, desktop.height / 2 - 1, accuracy: 0.001)
        XCTAssertEqual(wire.x, desktop.width - 1, accuracy: 0.001)
        XCTAssertEqual(wire.y, desktop.height - 1, accuracy: 0.001)
        XCTAssertGreaterThan(wire.y, halfway.y)
        XCTAssertGreaterThan(wire.x, halfway.x)

        let framebuffer = try makeFramebuffer(
            for: connection,
            width: UInt16(desktop.width),
            height: UInt16(desktop.height)
        )
        session.connection(connection, didCreateFramebuffer: framebuffer)
        await drainCallbacks()
        XCTAssertEqual(session.framebufferSize, desktop)

        session.movePointer(toFramebufferPoint: CGPoint(x: desktop.width, y: desktop.height))
        var sent: (UInt16, UInt16)?
        while let message = connection.clientToServerMessageQueue.dequeue() {
            guard let pointer = message as? VNCProtocol.PointerEvent else { continue }
            sent = (pointer.xPosition, pointer.yPosition)
        }
        XCTAssertEqual(sent?.0, UInt16(desktop.width) - 1)
        XCTAssertEqual(sent?.1, UInt16(desktop.height) - 1)
        XCTAssertGreaterThan(sent?.1 ?? 0, UInt16(desktop.height) / 2)

        for displayScale: CGFloat in [1, 2, 3] {
            session.movePointer(toFramebufferPoint: .zero)
            session.movePointer(
                viewDelta: CGPoint(x: image.width, y: image.height),
                viewSize: image.size,
                displayScale: displayScale
            )
            XCTAssertEqual(session.cursorPoint.x, desktop.width - 1, accuracy: 0.001)
            XCTAssertEqual(session.cursorPoint.y, desktop.height - 1, accuracy: 0.001)
            XCTAssertGreaterThan(session.cursorPoint.y, desktop.height / 2)
        }
    }

    func testScrollSamplesInOneFrameBatchUntilTheGestureEnds() {
        _ = connect()
        session.scroll(.down, steps: 4)
        session.scroll(.down, steps: 6)
        session.scroll(.up, steps: 2)

        XCTAssertTrue(wheelEvents.isEmpty)
        session.endScrollGesture()

        XCTAssertEqual(wheelEvents, [
            WheelEvent(wheel: .down, steps: 10),
            WheelEvent(wheel: .up, steps: 2),
        ])
    }

    func testEachWheelDetentIsAPressAndARelease() {
        // The shared session replaces the wheel sender. This one uses the
        // production press-and-release path.
        let producing = VNCSession(
            passwordStore: passwordStore,
            startConnection: { [weak self] in self?.connections.append($0) }
        )
        producing.connect(
            hostname: "test.invalid",
            port: 5900,
            username: "test-user",
            password: "synthetic-test-password"
        )
        let connection = connections.last!
        producing.scroll(.down, steps: 2)
        producing.endScrollGesture()

        var masks: [UInt8] = []
        while let message = connection.clientToServerMessageQueue.dequeue() {
            guard let pointer = message as? VNCProtocol.PointerEvent else { continue }
            masks.append(pointer.buttonMask)
        }
        producing.disconnect()

        let wheelDown = VNCProtocol.MousePointerButton.wheelDown.rawValue
        XCTAssertEqual(masks, [wheelDown, 0, wheelDown, 0])
    }

    func testFirstFrameCopiesTheDesktopAndALaterUpdateCopiesOnlyTheDirtyRect() async throws {
        let connection = connect()
        let framebuffer = try makeFramebuffer(for: connection)
        fill(framebuffer)
        sendFrameUpdate(framebuffer, from: connection)
        await drainCallbacks()

        let fullBytes = 32 * 24 * 4
        XCTAssertEqual(session.frameComposer.bytesCopied, fullBytes)
        XCTAssertEqual(session.framebufferImage?.width, 32)

        var pixel = Data([0x10, 0x20, 0x30, 0xFF])
        framebuffer.fill(region: VNCRegion(x: 0, y: 0, width: 2, height: 2), withPixel: &pixel)
        session.connection(
            connection,
            didUpdateFramebuffer: framebuffer,
            x: 0,
            y: 0,
            width: 2,
            height: 2
        )
        await drainCallbacks()
        session.renderPendingFrame()

        XCTAssertEqual(session.frameComposer.bytesCopied, fullBytes + 2 * 2 * 4)
    }

    func testDirtyRectangleDoesNotChangePixelsOutsideIt() {
        var source = [UInt8](repeating: 7, count: 4 * 2 * 4)
        source.replaceSubrange(0..<4, with: [9, 8, 7, 255])
        let composer = IncrementalFramebuffer()
        _ = source.withUnsafeBytes { raw in
            composer.apply(source: raw.baseAddress!, width: 4, height: 2, dirtyRects: [
                CGRect(x: 0, y: 0, width: 4, height: 2),
            ])
        }
        XCTAssertEqual(composer.pixel(x: 0, y: 0), [9, 8, 7, 255])
        XCTAssertEqual(composer.pixel(x: 1, y: 0), [7, 7, 7, 7])

        source.replaceSubrange(0..<4, with: [1, 2, 3, 255])
        _ = source.withUnsafeBytes { raw in
            composer.apply(source: raw.baseAddress!, width: 4, height: 2, dirtyRects: [
                CGRect(x: 0, y: 0, width: 1, height: 1),
            ])
        }

        XCTAssertEqual(composer.pixel(x: 0, y: 0), [1, 2, 3, 255])
        XCTAssertEqual(composer.pixel(x: 1, y: 0), [7, 7, 7, 7])
        XCTAssertEqual(composer.bytesCopied, 4 * 2 * 4 + 4)
    }

    func testOpenSpotlightPressesCommandSpaceAndReleasesCommandLast() {
        _ = connect()
        session.openSpotlight()

        XCTAssertEqual(keyEvents, [
            KeyEvent(key: .command, isDown: true),
            KeyEvent(key: .space, isDown: true),
            KeyEvent(key: .space, isDown: false),
            KeyEvent(key: .command, isDown: false),
        ])
    }

    func testKeyDownStaysDownUntilKeyUp() {
        _ = connect()
        session.keyDown(.command)
        session.click(.left)
        session.keyUp(.command)

        XCTAssertEqual(keyEvents, [
            KeyEvent(key: .command, isDown: true),
            KeyEvent(key: .command, isDown: false),
        ])
    }

    func testOpenSpotlightWithoutAConnectionSendsNothing() {
        session.openSpotlight()
        XCTAssertTrue(keyEvents.isEmpty)
    }

    func testTypingAfterSpotlightSendsPlainKeysAndReturn() {
        _ = connect()
        session.openSpotlight()
        keyEvents.removeAll()

        session.sendText("ab\n")

        let a = VNCKeyCode.withCharacter("a")[0]
        let b = VNCKeyCode.withCharacter("b")[0]
        XCTAssertEqual(keyEvents, [
            KeyEvent(key: a, isDown: true), KeyEvent(key: a, isDown: false),
            KeyEvent(key: b, isDown: true), KeyEvent(key: b, isDown: false),
            KeyEvent(key: .return, isDown: true), KeyEvent(key: .return, isDown: false),
        ])
    }

    func testRepeatedModifierIsPressedAndReleasedOnce() {
        _ = connect()
        session.pressKey(.space, modifiers: [.command, .command])

        XCTAssertEqual(keyEvents.filter { $0.key == .command }, [
            KeyEvent(key: .command, isDown: true),
            KeyEvent(key: .command, isDown: false),
        ])
    }

    func testStartupStaysLoadingUntilFirstImageArrives() async throws {
        let connection = connect()
        XCTAssertEqual(session.state, .connecting)
        XCTAssertTrue(session.showsRemoteScreen)

        let credential = await credential(from: connection)
        XCTAssertNotNil(credential)
        XCTAssertEqual(session.state, .authenticating)

        session.connection(connection, stateDidChange: .connected)
        await drainCallbacks()
        XCTAssertEqual(session.state, .loadingDesktop)
        XCTAssertNil(session.framebufferImage)

        let framebuffer = try makeFramebuffer(for: connection)
        session.connection(connection, didCreateFramebuffer: framebuffer)
        await drainCallbacks()
        XCTAssertNil(session.framebufferImage, "An allocated buffer is not a received desktop")

        fill(framebuffer)
        sendFrameUpdate(framebuffer, from: connection)
        await drainCallbacks()
        XCTAssertEqual(session.state, .connected)
        XCTAssertNotNil(session.framebufferImage)
        XCTAssertEqual(session.framebufferImage?.width, 32)
    }

    func testQueuedOldDisconnectCannotEndNewConnectionOrClearItsPassword() async {
        let old = connect()
        session.connection(old, stateDidChange: .disconnected)
        let current = connect()
        session.connection(current, stateDidChange: .connected)
        await drainCallbacks()

        XCTAssertEqual(session.state, .loadingDesktop)
        let currentCredential = await credential(from: current) as? VNCUsernamePasswordCredential
        XCTAssertEqual(currentCredential?.password, "synthetic-test-password")
        let staleCredential = await credential(from: old)
        XCTAssertNil(staleCredential, "An old handshake must not receive the new connection's credentials")
    }

    func testOldFramebufferCallbacksCannotReplaceNewDesktop() async throws {
        let old = connect()
        let staleFrame = try makeFramebuffer(for: old, width: 64)
        fill(staleFrame)
        session.connection(old, didCreateFramebuffer: staleFrame)
        session.connection(old, didResizeFramebuffer: staleFrame)
        sendFrameUpdate(staleFrame, from: old)
        _ = connect()
        await drainCallbacks()

        XCTAssertEqual(session.state, .connecting)
        XCTAssertEqual(session.framebufferSize, .zero)
        XCTAssertNil(session.framebufferImage)
    }

    func testCancelledConnectionIgnoresLateConnectedAndFrameCallbacks() async throws {
        let connection = connect()
        let framebuffer = try makeFramebuffer(for: connection)
        fill(framebuffer)
        session.disconnect()
        session.connection(connection, stateDidChange: .connected)
        sendFrameUpdate(framebuffer, from: connection)
        await drainCallbacks()

        XCTAssertEqual(session.state, .disconnected)
        XCTAssertFalse(session.showsRemoteScreen)
        XCTAssertNil(session.framebufferImage)
        let cancelledCredential = await credential(from: connection)
        XCTAssertNil(cancelledCredential)
    }

    func testLateCreationCallbackDoesNotClearAnAlreadyPresentedFrame() async throws {
        let connection = connect()
        let framebuffer = try makeFramebuffer(for: connection)
        fill(framebuffer)
        sendFrameUpdate(framebuffer, from: connection)
        await drainCallbacks()
        XCTAssertNotNil(session.framebufferImage)

        session.connection(connection, didCreateFramebuffer: framebuffer)
        session.connection(connection, stateDidChange: .connected)
        await drainCallbacks()
        XCTAssertNotNil(session.framebufferImage)
        XCTAssertEqual(session.state, .connected)
    }

    func testPasswordIsSavedOnlyAfterAuthenticationAndOnlyOnce() async {
        let connection = connect(rememberPassword: true)
        _ = await credential(from: connection)
        XCTAssertEqual(passwordStore.saveCount, 0)
        session.connection(connection, stateDidChange: .connected)
        await drainCallbacks()
        XCTAssertEqual(passwordStore.saveCount, 1)
        XCTAssertEqual(passwordStore.passwords[savedKey], "synthetic-test-password")
        session.connection(connection, stateDidChange: .connected)
        await drainCallbacks()
        XCTAssertEqual(passwordStore.saveCount, 1)
    }

    func testFailedSignInKeepsPreviouslySavedPassword() async {
        passwordStore.passwords[savedKey] = "previously-working-password"
        let connection = connect(rememberPassword: true)
        session.connection(connection, stateDidChange: .disconnected)
        await drainCallbacks()
        XCTAssertEqual(passwordStore.saveCount, 0)
        XCTAssertEqual(passwordStore.passwords[savedKey], "previously-working-password")
    }

    func testRememberDisabledNeverSavesPassword() async {
        let connection = connect(rememberPassword: false)
        session.connection(connection, stateDidChange: .connected)
        await drainCallbacks()
        XCTAssertEqual(passwordStore.saveCount, 0)
        XCTAssertTrue(passwordStore.passwords.isEmpty)
    }

    func testStaleSuccessfulConnectionCannotSaveCredentials() async {
        let old = connect(rememberPassword: true)
        session.connection(old, stateDidChange: .connected)
        _ = connect(rememberPassword: false)
        await drainCallbacks()
        XCTAssertEqual(passwordStore.saveCount, 0)
    }

    func testUserLogoutHidesConnectionAbortAndClearsTheCloseForTheForm() async {
        let connection = connect()
        session.connection(connection, stateDidChange: .connected)
        await drainCallbacks()

        let abort = VNCError.connection(.failed(posixAbort))
        session.connection(connection, stateDidChange: .disconnected(error: abort))
        session.disconnect()
        await drainCallbacks()

        XCTAssertNil(session.lastError)
        XCTAssertEqual(session.state, .disconnected)
        XCTAssertFalse(session.lastError?.contains("53") ?? false)
        XCTAssertTrue(session.takeGracefulClose())
        XCTAssertFalse(session.takeGracefulClose())
    }

    func testRemoteAbortAndCancelledCloseAreNotShownAsFailures() async {
        XCTAssertTrue(RemoteSessionClose.isExpected(VNCError.connection(.cancelled)))
        XCTAssertTrue(RemoteSessionClose.isExpected(VNCError.connection(.closed)))
        XCTAssertTrue(RemoteSessionClose.isExpected(posixAbort))
        XCTAssertTrue(RemoteSessionClose.isExpected(VNCError.connection(.failed(posixAbort))))
        XCTAssertFalse(RemoteSessionClose.isExpected(VNCError.authentication(.ardAuthenticationFailed)))

        let connection = connect()
        session.connection(connection, stateDidChange: .disconnected(error: posixAbort))
        await drainCallbacks()

        XCTAssertNil(session.lastError)
        XCTAssertTrue(session.takeGracefulClose())
    }

    func testAuthenticationFailureIsStillShownAfterAPreviousLogout() async {
        let first = connect()
        session.disconnect()
        session.connection(first, stateDidChange: .disconnected)
        await drainCallbacks()
        XCTAssertTrue(session.takeGracefulClose())

        let second = connect()
        let auth = VNCError.authentication(.ardAuthenticationFailed)
        session.connection(second, stateDidChange: .disconnected(error: auth))
        await drainCallbacks()

        XCTAssertEqual(session.lastError, auth.localizedDescription)
        XCTAssertFalse(session.takeGracefulClose())
    }

    func testBackgroundDropReconnectsWithTheSavedPassword() async {
        passwordStore.passwords[savedKey] = "synthetic-test-password"
        let connection = connect(rememberPassword: true)
        session.connection(connection, stateDidChange: .connected)
        await drainCallbacks()

        session.appDidEnterBackground()
        session.connection(connection, stateDidChange: .disconnected(error: posixAbort))
        await drainCallbacks()

        XCTAssertNil(session.lastError)
        XCTAssertEqual(session.state, .disconnected)
        session.appWillEnterForeground()

        XCTAssertEqual(connections.count, 2)
        XCTAssertEqual(session.state, .connecting)
    }

    func testStayingConnectedThroughABriefBackgroundDoesNotReconnect() async {
        let connection = connect(rememberPassword: true)
        session.connection(connection, stateDidChange: .connected)
        await drainCallbacks()
        let before = connections.count

        session.appDidEnterBackground()
        session.appWillEnterForeground()

        XCTAssertEqual(connections.count, before)
        // No framebuffer has arrived, so the live session stays on the desktop loader.
        XCTAssertEqual(session.state, .loadingDesktop)
        XCTAssertTrue(session.showsRemoteScreen)
    }

    func testUserDisconnectAndForgottenPasswordDoNotReconnect() async {
        let remembered = connect(rememberPassword: true)
        session.connection(remembered, stateDidChange: .connected)
        await drainCallbacks()
        session.disconnect()
        await drainCallbacks()
        session.appDidEnterBackground()
        session.appWillEnterForeground()
        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(session.state, .disconnected)

        let transient = connect(rememberPassword: false)
        session.connection(transient, stateDidChange: .connected)
        await drainCallbacks()
        session.appDidEnterBackground()
        session.connection(transient, stateDidChange: .disconnected(error: posixAbort))
        await drainCallbacks()
        session.appWillEnterForeground()
        XCTAssertEqual(connections.count, 2)
        XCTAssertEqual(session.state, .disconnected)
    }

    func testForegroundDuringAnInFlightBackgroundDropReconnectsWhenTheCloseFinishes() async {
        passwordStore.passwords[savedKey] = "synthetic-test-password"
        let connection = connect(rememberPassword: true)
        session.connection(connection, stateDidChange: .connected)
        await drainCallbacks()

        session.appDidEnterBackground()
        session.connection(connection, stateDidChange: .disconnecting)
        await drainCallbacks()
        session.appWillEnterForeground()
        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(session.state, .disconnecting)

        session.connection(connection, stateDidChange: .disconnected(error: posixAbort))
        await drainCallbacks()

        XCTAssertNil(session.lastError)
        XCTAssertEqual(connections.count, 2)
        XCTAssertEqual(session.state, .connecting)
    }

    func testPasteTypesClipboardTextAndANewlineAsReturn() {
        _ = connect()
        session.pasteRemoteClipboard("A\nb")

        let a = VNCKeyCode.withCharacter("A").first!
        let b = VNCKeyCode.withCharacter("b").first!
        XCTAssertEqual(keyEvents, [
            KeyEvent(key: a, isDown: true),
            KeyEvent(key: a, isDown: false),
            KeyEvent(key: .return, isDown: true),
            KeyEvent(key: .return, isDown: false),
            KeyEvent(key: b, isDown: true),
            KeyEvent(key: b, isDown: false),
        ])
    }

    func testEmptyClipboardSendsNothingAndPasteFlushesAPendingScroll() {
        _ = connect()
        session.pasteRemoteClipboard("")
        XCTAssertTrue(keyEvents.isEmpty)
        XCTAssertTrue(wheelEvents.isEmpty)

        session.scroll(.down, steps: 3)
        session.pasteRemoteClipboard("a")
        XCTAssertEqual(wheelEvents, [WheelEvent(wheel: .down, steps: 3)])
        let a = VNCKeyCode.withCharacter("a").first!
        XCTAssertEqual(keyEvents, [
            KeyEvent(key: a, isDown: true),
            KeyEvent(key: a, isDown: false),
        ])
    }

    func testSaveFailureKeepsConnectionUsableAndReportsIt() async {
        passwordStore.shouldFail = true
        let connection = connect(rememberPassword: true)
        session.connection(connection, stateDidChange: .connected)
        await drainCallbacks()
        XCTAssertEqual(session.state, .loadingDesktop)
        XCTAssertNotNil(session.credentialStorageError)
        XCTAssertFalse(session.credentialStorageError?.contains("synthetic-test-password") ?? true)
    }

    private var posixAbort: NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: 53,
            userInfo: [NSLocalizedDescriptionKey: "Network error 53 (Software caused connection abort)"]
        )
    }

    private var savedKey: RemoteCredentialKey {
        RemoteCredentialKey(hostname: "test.invalid", port: 5900, username: "test-user")
    }

    private func connect(rememberPassword: Bool = false) -> VNCConnection {
        session.connect(hostname: "test.invalid", port: 5900, username: "test-user", password: "synthetic-test-password", rememberPassword: rememberPassword)
        return connections.last!
    }

    private func credential(from connection: VNCConnection) async -> VNCCredential? {
        await withCheckedContinuation { continuation in
            session.connection(connection, credentialFor: .appleRemoteDesktop) {
                continuation.resume(returning: $0)
            }
        }
    }

    private func makeFramebuffer(
        for connection: VNCConnection,
        width: UInt16 = 32,
        height: UInt16 = 24
    ) throws -> VNCFramebuffer {
        let framebuffer = try VNCFramebuffer(
            logger: connection.logger,
            size: VNCSize(width: width, height: height),
            screens: [],
            pixelFormat: VNCProtocol.PixelFormat(depth: 24),
            allocator: VNCFramebufferMallocAllocator()
        )
        connection.framebuffer = framebuffer
        return framebuffer
    }

    private func fill(_ framebuffer: VNCFramebuffer) {
        var pixel = Data([0x33, 0x66, 0x99, 0])
        framebuffer.fill(region: framebuffer.fullRegion, withPixel: &pixel)
    }

    private func sendFrameUpdate(_ framebuffer: VNCFramebuffer, from connection: VNCConnection) {
        session.connection(connection, didUpdateFramebuffer: framebuffer, x: 0, y: 0, width: framebuffer.size.width, height: framebuffer.size.height)
    }

    private func drainCallbacks() async {
        // Let MainActor process the queued delegate callbacks and display work.
        let drained = expectation(description: "Queued callbacks processed")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
    }
}

final class RemoteKeyChordTests: XCTestCase {
    func testPressesAndReleasesEveryModifierWhenNoneAreHeld() {
        let chord = RemoteKeyChord(modifiers: [.shift, .command], alreadyHeld: [])
        XCTAssertEqual(
            chord.events(for: .space),
            [
                .down(VNCKeyCode.shift.rawValue),
                .down(VNCKeyCode.command.rawValue),
                .down(VNCKeyCode.space.rawValue),
                .up(VNCKeyCode.space.rawValue),
                .up(VNCKeyCode.command.rawValue),
                .up(VNCKeyCode.shift.rawValue),
            ]
        )
    }

    func testHeldCommandIsNeitherPressedNorReleased() {
        let chord = RemoteKeyChord(
            modifiers: [.command],
            alreadyHeld: [VNCKeyCode.command.rawValue]
        )
        XCTAssertEqual(
            chord.events(for: .space),
            [
                .down(VNCKeyCode.space.rawValue),
                .up(VNCKeyCode.space.rawValue),
            ]
        )
    }

    func testOnlyTheMissingModifierIsOwned() {
        let chord = RemoteKeyChord(
            modifiers: [.command, .shift, .command],
            alreadyHeld: [VNCKeyCode.command.rawValue]
        )
        XCTAssertEqual(chord.ownedModifiers, [.shift])
        XCTAssertEqual(
            chord.events(for: .tab),
            [
                .down(VNCKeyCode.shift.rawValue),
                .down(VNCKeyCode.tab.rawValue),
                .up(VNCKeyCode.tab.rawValue),
                .up(VNCKeyCode.shift.rawValue),
            ]
        )
    }
}
