import XCTest

final class RemoteToolbarTests: XCTestCase {
    private var app: XCUIApplication!
    private var spotlight: XCUIElement { app.buttons["toolbar-spotlight"] }
    private var keyboard: XCUIElement { app.buttons["toolbar-keyboard"] }
    private var sentKeys: XCUIElement { app.staticTexts["sent-keys"] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--test-remote-toolbar"]
        app.launch()
        XCTAssertTrue(spotlight.waitForExistence(timeout: 5))
    }

    func testSpotlightIsVisibleWithoutScrollingAndTappableAcrossItsWholeTarget() {
        XCTAssertTrue(spotlight.isHittable)

        // The icon and title are only about 30pt tall; this lands in the padding of the 60x46 button.
        spotlight.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 24, dy: 19))
            .tap()

        expectSentKeys("command down, space down, space up, command up")
    }

    func testSpotlightSendsCommandSpaceAndOpensTheKeyboard() {
        XCTAssertFalse(keyboard.isSelected)

        spotlight.tap()

        expectSentKeys("command down, space down, space up, command up")
        expect(keyboard, toBeSelected: true)
        XCTAssertTrue(app.buttons["Esc"].waitForExistence(timeout: 2), "The key row opens with the keyboard")
    }

    func testTrackpadToggleShowsAPanelUnderTheControls() {
        let trackpad = app.buttons["toolbar-trackpad"]
        XCTAssertTrue(trackpad.waitForExistence(timeout: 2))
        XCTAssertTrue(trackpad.isHittable)

        trackpad.tap()

        let panel = app.otherElements["remote-trackpad-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(panel.frame.minY, trackpad.frame.maxY - 8)
        XCTAssertGreaterThan(panel.frame.height, 200)
        expect(trackpad, toBeSelected: true)
        expect(keyboard, toBeSelected: false)

        keyboard.tap()

        expect(keyboard, toBeSelected: true)
        expect(trackpad, toBeSelected: false)
        let gone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: panel)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 2), .completed)
    }

    func testMoreMenuTypesClipboardText() {
        app.terminate()
        app.launchEnvironment["TAILREMOTE_PASTE_TEXT"] = "ab"
        app.launch()

        let more = app.buttons["toolbar-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        XCTAssertTrue(more.isHittable)
        more.tap()

        let paste = app.buttons["toolbar-paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 2))
        paste.tap()

        expectSentKeys("a down, a up, b down, b up")
    }

    func testSpotlightDropsLatchedModifiersBeforeTyping() {
        app.buttons["toolbar-keys"].tap()
        let latchedCommand = app.buttons["⌘"]
        XCTAssertTrue(latchedCommand.waitForExistence(timeout: 2))
        latchedCommand.tap()

        spotlight.tap()
        expect(keyboard, toBeSelected: true)
        // The bridge becomes first responder on the next run loop; wait for the system keyboard before typing.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Spotlight must open the keyboard")
        app.typeText("a\n")

        expectSentKeys("command down, space down, space up, command up, a down, a up, return down, return up")
    }

    private func expectSentKeys(_ expected: String) {
        let predicate = NSPredicate { [self] _, _ in sentKeys.label == expected }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        // Typing through the system keyboard can land a moment after typeText returns on a busy simulator.
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed, "Sent: \(sentKeys.label)")
    }

    private func expect(_ element: XCUIElement, toBeSelected selected: Bool) {
        let predicate = NSPredicate(format: "isSelected == %@", NSNumber(value: selected))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }
}
