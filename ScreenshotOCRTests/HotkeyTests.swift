import XCTest
import Carbon.HIToolbox
import CoreGraphics
@testable import ScreenshotOCR

final class HotkeyTests: XCTestCase {

    func test_default_isCmdShiftO() {
        let hotkey = Hotkey.default
        XCTAssertEqual(hotkey.keyCode, Int64(kVK_ANSI_O))
        XCTAssertEqual(hotkey.description, "⇧+⌘+O")
    }

    func test_init_stripsExtraneousFlags() {
        let capsLock: UInt64 = CGEventFlags.maskAlphaShift.rawValue
        let numericPad: UInt64 = CGEventFlags.maskNumericPad.rawValue
        let hotkey = Hotkey(
            keyCode: 0,
            flags: CGEventFlags.maskCommand.rawValue | capsLock | numericPad
        )
        XCTAssertEqual(hotkey.flags, CGEventFlags.maskCommand.rawValue)
    }

    func test_description_followsAppleHIGOrder() {
        // Apple HIG: Control, Option, Shift, Command, then key.
        let allMods = CGEventFlags.maskControl.rawValue
            | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskShift.rawValue
            | CGEventFlags.maskCommand.rawValue
        let hotkey = Hotkey(keyCode: Int64(kVK_ANSI_A), flags: allMods)
        XCTAssertEqual(hotkey.description, "⌃+⌥+⇧+⌘+A")
    }

    func test_description_unknownKey_fallback() {
        let hotkey = Hotkey(keyCode: 999, flags: CGEventFlags.maskCommand.rawValue)
        XCTAssertEqual(hotkey.description, "⌘+Key 999")
    }

    func test_jsonRoundTrip_preservesValue() throws {
        let original = Hotkey(
            keyCode: Int64(kVK_ANSI_K),
            flags: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Hotkey.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func test_isValidForGlobal_rejectsBareLetter() {
        XCTAssertFalse(Hotkey.isValidForGlobal(keyCode: Int64(kVK_ANSI_A), flags: 0))
    }

    func test_isValidForGlobal_rejectsBareDigit() {
        XCTAssertFalse(Hotkey.isValidForGlobal(keyCode: Int64(kVK_ANSI_5), flags: 0))
    }

    func test_isValidForGlobal_acceptsLetterWithModifier() {
        XCTAssertTrue(Hotkey.isValidForGlobal(
            keyCode: Int64(kVK_ANSI_A),
            flags: CGEventFlags.maskCommand.rawValue
        ))
    }

    func test_isValidForGlobal_acceptsBareFunctionKey() {
        XCTAssertTrue(Hotkey.isValidForGlobal(keyCode: Int64(kVK_F5), flags: 0))
    }

    func test_isValidForGlobal_acceptsBareEscape() {
        XCTAssertTrue(Hotkey.isValidForGlobal(keyCode: Int64(kVK_Escape), flags: 0))
    }

    func test_carbonModifiers_mapsAllFour() {
        let hotkey = Hotkey(
            keyCode: 0,
            flags: CGEventFlags.maskCommand.rawValue
                | CGEventFlags.maskShift.rawValue
                | CGEventFlags.maskAlternate.rawValue
                | CGEventFlags.maskControl.rawValue
        )
        let expected = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        XCTAssertEqual(hotkey.carbonModifiers, expected)
    }

    func test_carbonModifiers_partial() {
        let hotkey = Hotkey(
            keyCode: 0,
            flags: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
        )
        XCTAssertEqual(hotkey.carbonModifiers, UInt32(cmdKey | shiftKey))
    }

    func test_isValidForGlobal_rejectsBareModifierKeycode() {
        // Even with another modifier held, a key code that IS a modifier
        // (Shift, Command, Option, Control, Fn, CapsLock) must be rejected.
        let modKeyCodes: [Int64] = [
            Int64(kVK_Command), Int64(kVK_RightCommand),
            Int64(kVK_Shift), Int64(kVK_RightShift),
            Int64(kVK_Option), Int64(kVK_RightOption),
            Int64(kVK_Control), Int64(kVK_RightControl),
            Int64(kVK_CapsLock), Int64(kVK_Function),
        ]
        for code in modKeyCodes {
            XCTAssertFalse(
                Hotkey.isValidForGlobal(
                    keyCode: code,
                    flags: CGEventFlags.maskCommand.rawValue
                ),
                "keyCode \(code) should be rejected as a pure-modifier key"
            )
        }
    }

    func test_codable_decodingStripsForbiddenFlags() throws {
        // Simulate a persisted hotkey written before masking was added
        // (e.g. a Transcribr UserDefaults migration). The Fn bit should be
        // stripped on decode, not carried into runtime.
        let rawFlags = CGEventFlags.maskCommand.rawValue
            | CGEventFlags.maskShift.rawValue
            | CGEventFlags.maskSecondaryFn.rawValue
            | CGEventFlags.maskAlphaShift.rawValue
        let payload = #"{"keyCode":31,"flags":\#(rawFlags)}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Hotkey.self, from: payload)

        XCTAssertEqual(decoded.flags & CGEventFlags.maskSecondaryFn.rawValue, 0)
        XCTAssertEqual(decoded.flags & CGEventFlags.maskAlphaShift.rawValue, 0)
        XCTAssertEqual(
            decoded.flags,
            CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
        )
    }
}
