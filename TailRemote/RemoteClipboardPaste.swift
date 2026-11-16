import RoyalVNCKit

/// Keystrokes that type clipboard text into the focused field on a Mac screen share.
///
/// RoyalVNCKit keeps ClientCutText internal, so the app cannot send that message
/// ahead of Command-V. Typing the characters inserts them directly. Screen Sharing
/// treats these keysyms as text in the focused field. A newline becomes Return.
enum RemoteClipboardPaste {
    enum Action: Equatable {
        case key(VNCKeyCode, modifiers: [VNCKeyCode])
    }

    static func actions(for text: String) -> [Action] {
        guard !text.isEmpty else { return [] }
        var actions: [Action] = []
        for character in text {
            if character.isNewline {
                actions.append(.key(.return, modifiers: []))
                continue
            }
            VNCKeyCode.withCharacter(character).forEach { key in
                actions.append(.key(key, modifiers: []))
            }
        }
        return actions
    }
}
