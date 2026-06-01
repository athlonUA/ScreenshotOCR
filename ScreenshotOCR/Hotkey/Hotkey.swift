import Foundation
import Carbon.HIToolbox
import CoreGraphics

/// Persisted hotkey combination.
///
/// `flags` uses `CGEventFlags` raw values, which are bit-compatible with
/// `NSEvent.ModifierFlags.rawValue` on macOS. Stored as JSON in `UserDefaults`
/// so the same value survives across launches.
struct Hotkey: Codable, Equatable, CustomStringConvertible {
    var keyCode: Int64
    var flags: UInt64

    /// Modifier-only bits we care about. Excludes CapsLock, NumPad and other
    /// transient flags that `NSEvent.modifierFlags` may leak when recording.
    static let modifierMask: UInt64 =
        CGEventFlags.maskShift.rawValue
        | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskCommand.rawValue

    /// Virtual keycodes for pure-modifier keys. Recording any of these alone
    /// would result in a hotkey that fires whenever the user holds Shift/Cmd/etc.
    private static let modifierOnlyKeyCodes: Set<Int64> = [
        Int64(kVK_Command),       // 55
        Int64(kVK_RightCommand),  // 54
        Int64(kVK_Shift),         // 56
        Int64(kVK_CapsLock),      // 57
        Int64(kVK_Option),        // 58
        Int64(kVK_Control),       // 59
        Int64(kVK_RightShift),    // 60
        Int64(kVK_RightOption),   // 61
        Int64(kVK_RightControl),  // 62
        Int64(kVK_Function),      // 63
    ]

    static let `default` = Hotkey(
        keyCode: Int64(kVK_ANSI_O),
        flags: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
    )

    init(keyCode: Int64, flags: UInt64) {
        self.keyCode = keyCode
        self.flags = flags & Self.modifierMask
    }

    /// Decoding routes through the masking initialiser so any stray bits in
    /// persisted JSON (e.g. CapsLock, NumPad, or a Fn flag from a Transcribr
    /// migration) get stripped before being trusted by the rest of the app.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let keyCode = try container.decode(Int64.self, forKey: .keyCode)
        let rawFlags = try container.decode(UInt64.self, forKey: .flags)
        self.init(keyCode: keyCode, flags: rawFlags)
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, flags
    }

    /// Apple HIG order (⌃ ⌥ ⇧ ⌘) joined with `+`, matching the Transcribr
    /// hotkey display so both apps read consistently in the menu bar.
    var description: String {
        var parts: [String] = []
        if flags & CGEventFlags.maskControl.rawValue != 0 { parts.append("⌃") }
        if flags & CGEventFlags.maskAlternate.rawValue != 0 { parts.append("⌥") }
        if flags & CGEventFlags.maskShift.rawValue != 0 { parts.append("⇧") }
        if flags & CGEventFlags.maskCommand.rawValue != 0 { parts.append("⌘") }
        parts.append(KeyCodeNames.name(for: keyCode))
        return parts.joined(separator: "+")
    }

    /// Reject combos that are never useful as a global hotkey:
    /// - a bare modifier key alone (Shift/Cmd/Option/Control on either side, Fn, CapsLock)
    ///   — `RegisterEventHotKey` would either reject these or fire whenever the
    ///   user holds the modifier;
    /// - a bare alphanumeric without any modifier — would steal regular typing.
    static func isValidForGlobal(keyCode: Int64, flags: UInt64) -> Bool {
        if modifierOnlyKeyCodes.contains(keyCode) {
            return false
        }
        let masked = flags & modifierMask
        if masked == 0, KeyCodeNames.isAlphanumeric(keyCode) {
            return false
        }
        return true
    }

    /// Convert CG flags into Carbon modifier bits expected by `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        var mods: UInt32 = 0
        if flags & CGEventFlags.maskCommand.rawValue != 0 { mods |= UInt32(cmdKey) }
        if flags & CGEventFlags.maskShift.rawValue != 0 { mods |= UInt32(shiftKey) }
        if flags & CGEventFlags.maskAlternate.rawValue != 0 { mods |= UInt32(optionKey) }
        if flags & CGEventFlags.maskControl.rawValue != 0 { mods |= UInt32(controlKey) }
        return mods
    }
}
