import Foundation

// New for the iOS client, with no Android source to port. For comparison, Starwire for Android's
// StreamView (GPL-3.0) also turns the system keyboard's delete into Backspace key taps.

/// What to send to the PC when the iOS system keyboard changes the text.
///
/// Rules:
/// - Inserted text goes as one `.text` packet (UTF-8 on the wire), not as key presses.
/// - Deleting n characters sends n Backspace taps (key down, key up; virtual key 0x08).
/// - A newline sends an Enter tap (0x0D) and is never sent as text. "\n", "\r" and "\r\n" each
///   count as one newline. Text with newlines in the middle is split around them: "ab\ncd" is
///   text "ab", Enter, text "cd".
/// - Characters are Swift characters (what a person counts as one letter), so an emoji with a
///   skin tone or a letter with an accent is deleted by one Backspace.
/// - Deletions go first, then the insertion, so a replacement reads as it would be typed.
public enum SystemKeyboardText {
    public static let backspaceKey = 0x08
    public static let enterKey = 0x0D

    /// Packets for `deleted` characters removed, then `inserted` typed.
    public static func events(inserted: String, deleted: Int = 0) -> [InputEvent] {
        var events: [InputEvent] = []
        for _ in 0..<max(0, deleted) {
            events += tap(backspaceKey)
        }

        var run = ""
        func flushRun() {
            if !run.isEmpty {
                events.append(.text(run))
                run = ""
            }
        }
        for character in inserted {
            if character == "\n" || character == "\r" || character == "\r\n" {
                flushRun()
                events += tap(enterKey)
            } else {
                run.append(character)
            }
        }
        flushRun()
        return events
    }

    /// Packets for the text field changing from `old` to `new`. The part they share at the start
    /// stays; the rest of `old` is deleted and the rest of `new` is typed. So "hello" to "help!"
    /// is two Backspaces, then the text "p!".
    public static func events(old: String, new: String) -> [InputEvent] {
        let oldCharacters = Array(old)
        let newCharacters = Array(new)
        var common = 0
        while common < oldCharacters.count, common < newCharacters.count,
              oldCharacters[common] == newCharacters[common] {
            common += 1
        }
        return events(inserted: String(newCharacters[common...]), deleted: oldCharacters.count - common)
    }

    private static func tap(_ virtualKey: Int) -> [InputEvent] {
        [.key(code: virtualKey, down: true, modifiers: 0), .key(code: virtualKey, down: false, modifiers: 0)]
    }
}
