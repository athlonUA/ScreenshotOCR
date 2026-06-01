import Foundation

/// US-layout keycode → human-readable name. Used for hotkey display strings.
///
/// Mirrors `kVK_*` constants from `Carbon.HIToolbox.Events` so the same numeric
/// keyCode can be persisted, displayed, and registered without a separate enum.
enum KeyCodeNames {
    static func name(for keyCode: Int64) -> String {
        if let known = table[keyCode] { return known }
        return "Key \(keyCode)"
    }

    /// Letters and digits — rejected as plain hotkeys (would shadow typing).
    static func isAlphanumeric(_ keyCode: Int64) -> Bool {
        alphanumerics.contains(keyCode)
    }

    private static let alphanumerics: Set<Int64> = {
        var set: Set<Int64> = []
        // Letters A..Z
        set.formUnion([0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6])
        // Digits 0..9 (top row)
        set.formUnion([29, 18, 19, 20, 21, 23, 22, 26, 28, 25])
        return set
    }()

    private static let table: [Int64: String] = [
        // Letters
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
        12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
        16: "Y", 6: "Z",
        // Top-row digits
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        // Function keys
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        // Whitespace & control
        49: "Space", 36: "Return", 76: "Enter", 48: "Tab", 51: "Delete", 117: "Forward Delete", 53: "Escape",
        // Arrows
        123: "←", 124: "→", 125: "↓", 126: "↑",
        // Punctuation (US layout)
        50: "`", 27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\",
        // Navigation
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
    ]
}
