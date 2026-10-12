import RoyalVNCKit
import SwiftUI
import UIKit

struct RemoteKeyboardBridge: UIViewRepresentable {
    @ObservedObject var session: VNCSession
    @Binding var isActive: Bool
    var modifiers: [VNCKeyCode] = []
    var onModifiersConsumed: () -> Void = {}

    func makeUIView(context: Context) -> RemoteKeyboardTextField {
        let field = RemoteKeyboardTextField()
        bind(field)
        return field
    }

    func updateUIView(_ field: RemoteKeyboardTextField, context: Context) {
        bind(field)

        if isActive, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !isActive, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    private func bind(_ field: RemoteKeyboardTextField) {
        field.onText = { text in
            session.sendText(text, modifiers: modifiers)
            if !modifiers.isEmpty { onModifiersConsumed() }
        }
        field.onBackspace = {
            session.pressKey(.delete, modifiers: modifiers)
            if !modifiers.isEmpty { onModifiersConsumed() }
        }
        field.onReturn = {
            session.pressKey(.return, modifiers: modifiers)
            if !modifiers.isEmpty { onModifiersConsumed() }
        }
        field.onDismiss = { isActive = false }
    }
}

@MainActor
final class RemoteKeyboardTextField: UITextField, UITextFieldDelegate {
    /// Kept in the field so iOS never sees an empty box and turns Shift back on.
    private let anchor = "\u{200b}"

    var onText: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onReturn: (() -> Void)?
    var onDismiss: (() -> Void)?
    private var sentBackspaceAt: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        autocapitalizationType = .none
        autocorrectionType = .no
        spellCheckingType = .no
        smartDashesType = .no
        smartQuotesType = .no
        smartInsertDeleteType = .no
        textContentType = nil
        inlinePredictionType = .no
        returnKeyType = .default
        keyboardAppearance = .dark
        text = anchor
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        accessibilityLabel = "Remote keyboard input"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func deleteBackward() {
        sendBackspace()
        restoreAnchor()
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        if string == "\n" {
            onReturn?()
        } else if string.isEmpty {
            // The field keeps a hidden character, so the phone keyboard deletes
            // that instead of calling deleteBackward. Send one Backspace to the Mac.
            sendBackspace()
        } else {
            onText?(string)
        }
        restoreAnchor()
        return false
    }

    private func sendBackspace() {
        let now = CACurrentMediaTime()
        if now - sentBackspaceAt < 0.04 { return }
        sentBackspaceAt = now
        onBackspace?()
    }

    private func restoreAnchor() {
        if text != anchor {
            text = anchor
        }
        let end = endOfDocument
        selectedTextRange = textRange(from: end, to: end)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        onDismiss?()
    }
}

