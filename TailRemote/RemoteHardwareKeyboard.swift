import GameController
import RoyalVNCKit
import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted synchronously before the VNC connection is asked to disconnect,
    /// so held hardware keys can be released while the session still exists.
    static let tailRemoteSessionWillDisconnect = Notification.Name("TailRemote.sessionWillDisconnect")
}

/// Maps a hardware key to the keysym Screen Sharing should see.
/// Modifier keys are their own events. Character keys use the unmodified character
/// so Shift, held separately, still produces the shifted glyph on the Mac.
enum HardwareKeyTranslator {
    static func code(usage: UIKeyboardHIDUsage, charactersIgnoringModifiers: String) -> VNCKeyCode? {
        if let special = specialKey(usage) {
            return special
        }
        guard charactersIgnoringModifiers.count == 1, let character = charactersIgnoringModifiers.first else {
            return hidFallback(usage)
        }
        return characterKey(character) ?? hidFallback(usage)
    }

    static func modifiers(from flags: UIKeyModifierFlags) -> [VNCKeyCode] {
        var modifiers: [VNCKeyCode] = []
        if flags.contains(.shift) { modifiers.append(.shift) }
        if flags.contains(.control) { modifiers.append(.control) }
        if flags.contains(.alternate) { modifiers.append(.option) }
        if flags.contains(.command) { modifiers.append(.command) }
        return modifiers
    }

    private static func characterKey(_ character: Character) -> VNCKeyCode? {
        let normalized: Character
        if let ascii = character.asciiValue, ascii >= 65, ascii <= 90 {
            normalized = Character(UnicodeScalar(ascii + 32))
        } else {
            normalized = character
        }
        return VNCKeyCode.withCharacter(normalized).first
    }

    private static func hidFallback(_ usage: UIKeyboardHIDUsage) -> VNCKeyCode? {
        let letters: [UIKeyboardHIDUsage: Character] = [
            .keyboardA: "a", .keyboardB: "b", .keyboardC: "c", .keyboardD: "d", .keyboardE: "e",
            .keyboardF: "f", .keyboardG: "g", .keyboardH: "h", .keyboardI: "i", .keyboardJ: "j",
            .keyboardK: "k", .keyboardL: "l", .keyboardM: "m", .keyboardN: "n", .keyboardO: "o",
            .keyboardP: "p", .keyboardQ: "q", .keyboardR: "r", .keyboardS: "s", .keyboardT: "t",
            .keyboardU: "u", .keyboardV: "v", .keyboardW: "w", .keyboardX: "x", .keyboardY: "y",
            .keyboardZ: "z",
        ]
        if let letter = letters[usage] {
            return characterKey(letter)
        }
        switch usage {
        case .keyboard1: return characterKey("1")
        case .keyboard2: return characterKey("2")
        case .keyboard3: return characterKey("3")
        case .keyboard4: return characterKey("4")
        case .keyboard5: return characterKey("5")
        case .keyboard6: return characterKey("6")
        case .keyboard7: return characterKey("7")
        case .keyboard8: return characterKey("8")
        case .keyboard9: return characterKey("9")
        case .keyboard0: return characterKey("0")
        case .keyboardSpacebar: return .space
        case .keyboardHyphen: return characterKey("-")
        case .keyboardEqualSign: return characterKey("=")
        case .keyboardOpenBracket: return characterKey("[")
        case .keyboardCloseBracket: return characterKey("]")
        case .keyboardBackslash: return characterKey("\\")
        case .keyboardSemicolon: return characterKey(";")
        case .keyboardQuote: return characterKey("'")
        case .keyboardGraveAccentAndTilde: return characterKey("`")
        case .keyboardComma: return characterKey(",")
        case .keyboardPeriod: return characterKey(".")
        case .keyboardSlash: return characterKey("/")
        default: return nil
        }
    }

    private static func specialKey(_ usage: UIKeyboardHIDUsage) -> VNCKeyCode? {
        switch usage {
        case .keyboardLeftShift: .shift
        case .keyboardRightShift: .rightShift
        case .keyboardLeftControl: .control
        case .keyboardRightControl: .rightControl
        case .keyboardLeftAlt: .option
        case .keyboardRightAlt: .rightOption
        case .keyboardLeftGUI: .command
        case .keyboardRightGUI: .rightCommand
        case .keyboardCapsLock: .capsLock
        case .keyboardReturnOrEnter: .return
        case .keyboardEscape: .escape
        case .keyboardDeleteOrBackspace: .delete
        case .keyboardDeleteForward: .forwardDelete
        case .keyboardTab: .tab
        case .keyboardSpacebar: .space
        case .keyboardLeftArrow: .leftArrow
        case .keyboardRightArrow: .rightArrow
        case .keyboardUpArrow: .upArrow
        case .keyboardDownArrow: .downArrow
        case .keyboardHome: .home
        case .keyboardEnd: .end
        case .keyboardPageUp: .pageUp
        case .keyboardPageDown: .pageDown
        case .keyboardInsert: .insert
        case .keyboardF1: .f1
        case .keyboardF2: .f2
        case .keyboardF3: .f3
        case .keyboardF4: .f4
        case .keyboardF5: .f5
        case .keyboardF6: .f6
        case .keyboardF7: .f7
        case .keyboardF8: .f8
        case .keyboardF9: .f9
        case .keyboardF10: .f10
        case .keyboardF11: .f11
        case .keyboardF12: .f12
        case .keyboardF13: .f13
        case .keyboardF14: .f14
        case .keyboardF15: .f15
        case .keyboardF16: .f16
        case .keyboardF17: .f17
        case .keyboardF18: .f18
        case .keyboardF19: .f19
        case .keypadEnter: .ansiKeypadEnter
        case .keypadSlash: .ansiKeypadDivide
        case .keypadAsterisk: .ansiKeypadMultiply
        case .keypadHyphen: .ansiKeypadMinus
        case .keypadPlus: .ansiKeypadPlus
        case .keypadPeriod: .ansiKeypadDecimal
        case .keypadEqualSign: .ansiKeypadEquals
        case .keypad0: characterKey("0")
        case .keypad1: characterKey("1")
        case .keypad2: characterKey("2")
        case .keypad3: characterKey("3")
        case .keypad4: characterKey("4")
        case .keypad5: characterKey("5")
        case .keypad6: characterKey("6")
        case .keypad7: characterKey("7")
        case .keypad8: characterKey("8")
        case .keypad9: characterKey("9")
        default: nil
        }
    }
}

private extension VNCKeyCode {
    /// X11 Caps_Lock. RoyalVNCKit does not publish this keysym; Screen Sharing accepts it.
    static let capsLock = VNCKeyCode(0xFFE5)
}

struct RemoteHardwareKeyboard: UIViewRepresentable {
    var session: VNCSession
    var captureEnabled: Bool

    func makeUIView(context: Context) -> RemoteHardwareKeyboardView {
        let view = RemoteHardwareKeyboardView()
        view.session = session
        view.captureEnabled = captureEnabled
        return view
    }

    func updateUIView(_ view: RemoteHardwareKeyboardView, context: Context) {
        view.session = session
        view.captureEnabled = captureEnabled
    }

    static func dismantleUIView(_ view: RemoteHardwareKeyboardView, coordinator: ()) {
        view.releaseHeldKeys()
    }
}

/// First responder while a Magic Keyboard or other hardware keyboard is attached.
/// Key-down and key-up are forwarded individually, so modifiers stay down on the Mac
/// until the physical key comes up.
@MainActor
final class RemoteHardwareKeyboardView: UIView {
    var session: VNCSession?
    var captureEnabled = false {
        didSet {
            guard oldValue != captureEnabled else { return }
            refreshResponder()
        }
    }

    private var held: [UIKeyboardHIDUsage: VNCKeyCode] = [:]
    private var claimedByCommand: Set<UIKeyboardHIDUsage> = []
    private var suppressedUsages: Set<UIKeyboardHIDUsage> = []
    private let emptyInput = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))

    private struct PriorityShortcut {
        var input: String
        var flags: UIKeyModifierFlags
        var usage: UIKeyboardHIDUsage
        var key: VNCKeyCode
    }

    private static let relevantFlags: UIKeyModifierFlags = [.command, .shift, .control, .alternate]
    private static let priorityShortcuts: [PriorityShortcut] = [
        PriorityShortcut(input: " ", flags: .command, usage: .keyboardSpacebar, key: .space),
        PriorityShortcut(input: "\t", flags: .command, usage: .keyboardTab, key: .tab),
        PriorityShortcut(input: "\t", flags: [.command, .shift], usage: .keyboardTab, key: .tab),
        PriorityShortcut(input: UIKeyCommand.inputEscape, flags: [], usage: .keyboardEscape, key: .escape),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        emptyInput.backgroundColor = .clear
        let names: [Notification.Name] = [
            .GCKeyboardDidConnect,
            .GCKeyboardDidDisconnect,
            UIApplication.willResignActiveNotification,
            .tailRemoteSessionWillDisconnect,
        ]
        names.forEach {
            NotificationCenter.default.addObserver(self, selector: #selector(hardwareEnvironmentChanged(_:)), name: $0, object: nil)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var canBecomeFirstResponder: Bool {
        captureEnabled && Self.hardwareKeyboardIsConnected
    }

    override var inputView: UIView? {
        canBecomeFirstResponder ? emptyInput : nil
    }

    override var keyCommands: [UIKeyCommand]? {
        guard canBecomeFirstResponder else { return nil }
        return Self.priorityShortcuts.map { shortcut in
            let command = UIKeyCommand(
                input: shortcut.input,
                modifierFlags: shortcut.flags,
                action: #selector(handlePriorityShortcut(_:))
            )
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshResponder()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled: Set<UIPress> = []
        for press in presses {
            guard let key = press.key else {
                unhandled.insert(press)
                continue
            }
            let usage = key.keyCode
            if claimedByCommand.contains(usage) {
                suppressedUsages.insert(usage)
                claimedByCommand.remove(usage)
                continue
            }
            if suppressedUsages.contains(usage) || held[usage] != nil {
                continue
            }
            guard let code = HardwareKeyTranslator.code(
                usage: usage,
                charactersIgnoringModifiers: key.charactersIgnoringModifiers
            ) else {
                unhandled.insert(press)
                continue
            }
            held[usage] = code
            session?.keyDown(code)
        }
        if !unhandled.isEmpty {
            super.pressesBegan(unhandled, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled: Set<UIPress> = []
        for press in presses {
            guard let key = press.key else {
                unhandled.insert(press)
                continue
            }
            let usage = key.keyCode
            if suppressedUsages.remove(usage) != nil {
                continue
            }
            guard let code = held.removeValue(forKey: usage) else {
                unhandled.insert(press)
                continue
            }
            session?.keyUp(code)
        }
        if !unhandled.isEmpty {
            super.pressesEnded(unhandled, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled: Set<UIPress> = []
        for press in presses {
            guard let key = press.key else {
                unhandled.insert(press)
                continue
            }
            let usage = key.keyCode
            suppressedUsages.remove(usage)
            if let code = held.removeValue(forKey: usage) {
                session?.keyUp(code)
            } else {
                unhandled.insert(press)
            }
        }
        if !unhandled.isEmpty {
            super.pressesCancelled(unhandled, with: event)
        }
    }

    func releaseHeldKeys() {
        let codes = Array(held.values)
        held.removeAll()
        claimedByCommand.removeAll()
        suppressedUsages.removeAll()
        codes.forEach { session?.keyUp($0) }
    }

    private static var hardwareKeyboardIsConnected: Bool {
        GCKeyboard.coalesced != nil
    }

    private func refreshResponder() {
        if canBecomeFirstResponder {
            guard !isFirstResponder else { return }
            becomeFirstResponder()
        } else if isFirstResponder {
            releaseHeldKeys()
            resignFirstResponder()
        }
    }

    @objc private func hardwareEnvironmentChanged(_ note: Notification) {
        if note.name == .tailRemoteSessionWillDisconnect || note.name == UIApplication.willResignActiveNotification {
            releaseHeldKeys()
        }
        refreshResponder()
    }

    @objc private func handlePriorityShortcut(_ command: UIKeyCommand) {
        let flags = command.modifierFlags.intersection(Self.relevantFlags)
        guard let shortcut = Self.priorityShortcuts.first(where: {
            $0.input == command.input && $0.flags == flags
        }) else { return }
        guard held[shortcut.usage] == nil else { return }

        claimedByCommand.insert(shortcut.usage)
        let modifiers = HardwareKeyTranslator.modifiers(from: shortcut.flags)
        let modifiersAlreadyDown = !modifiers.isEmpty && modifiers.allSatisfy { held.values.contains($0) }
        if modifiersAlreadyDown {
            session?.keyDown(shortcut.key)
            session?.keyUp(shortcut.key)
        } else {
            session?.pressKey(shortcut.key, modifiers: modifiers)
        }
        DispatchQueue.main.async { [weak self] in
            self?.claimedByCommand.remove(shortcut.usage)
        }
    }
}
