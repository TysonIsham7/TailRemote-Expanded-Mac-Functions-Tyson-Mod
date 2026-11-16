import UIKit
import XCTest
@testable import RoyalVNCKit
@testable import TailRemote

final class HardwareKeyTranslatorTests: XCTestCase {
    func testModifiersMapToTheMatchingSide() {
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardLeftGUI, charactersIgnoringModifiers: ""), .command)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardRightGUI, charactersIgnoringModifiers: ""), .rightCommand)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardLeftAlt, charactersIgnoringModifiers: ""), .option)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardRightAlt, charactersIgnoringModifiers: ""), .rightOption)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardLeftControl, charactersIgnoringModifiers: ""), .control)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardRightControl, charactersIgnoringModifiers: ""), .rightControl)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardLeftShift, charactersIgnoringModifiers: ""), .shift)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardRightShift, charactersIgnoringModifiers: ""), .rightShift)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardCapsLock, charactersIgnoringModifiers: "")?.rawValue, 0xFFE5)
    }

    func testArrowsEscapeAndFunctionKeys() {
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardEscape, charactersIgnoringModifiers: ""), .escape)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardLeftArrow, charactersIgnoringModifiers: ""), .leftArrow)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardRightArrow, charactersIgnoringModifiers: ""), .rightArrow)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardUpArrow, charactersIgnoringModifiers: ""), .upArrow)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardDownArrow, charactersIgnoringModifiers: ""), .downArrow)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardF1, charactersIgnoringModifiers: ""), .f1)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardF12, charactersIgnoringModifiers: ""), .f12)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardSpacebar, charactersIgnoringModifiers: " "), .space)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardTab, charactersIgnoringModifiers: "\t"), .tab)
        XCTAssertEqual(HardwareKeyTranslator.code(usage: .keyboardDeleteOrBackspace, charactersIgnoringModifiers: ""), .delete)
    }

    func testLettersUseTheUnmodifiedCharacter() {
        let lowercase = VNCKeyCode.withCharacter("a").first
        XCTAssertEqual(
            HardwareKeyTranslator.code(usage: .keyboardA, charactersIgnoringModifiers: "a"),
            lowercase
        )
        XCTAssertEqual(
            HardwareKeyTranslator.code(usage: .keyboardA, charactersIgnoringModifiers: "A"),
            lowercase
        )
        XCTAssertEqual(
            HardwareKeyTranslator.code(usage: .keyboardSlash, charactersIgnoringModifiers: "/"),
            VNCKeyCode.withCharacter("/").first
        )
    }

    func testModifierFlagsBecomeKeysymsInAStableOrder() {
        XCTAssertEqual(
            HardwareKeyTranslator.modifiers(from: [.command, .alternate, .shift]),
            [.shift, .option, .command]
        )
        XCTAssertEqual(HardwareKeyTranslator.modifiers(from: []), [])
    }
}
