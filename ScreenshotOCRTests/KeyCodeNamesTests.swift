import XCTest
import Carbon.HIToolbox
@testable import ScreenshotOCR

final class KeyCodeNamesTests: XCTestCase {

    func test_name_letters() {
        XCTAssertEqual(KeyCodeNames.name(for: Int64(kVK_ANSI_A)), "A")
        XCTAssertEqual(KeyCodeNames.name(for: Int64(kVK_ANSI_Z)), "Z")
    }

    func test_name_digits() {
        XCTAssertEqual(KeyCodeNames.name(for: Int64(kVK_ANSI_0)), "0")
        XCTAssertEqual(KeyCodeNames.name(for: Int64(kVK_ANSI_9)), "9")
    }

    func test_name_functionKeys() {
        XCTAssertEqual(KeyCodeNames.name(for: Int64(kVK_F1)), "F1")
        XCTAssertEqual(KeyCodeNames.name(for: Int64(kVK_F12)), "F12")
    }

    func test_name_specialKeys() {
        XCTAssertEqual(KeyCodeNames.name(for: Int64(kVK_Space)), "Space")
        XCTAssertEqual(KeyCodeNames.name(for: Int64(kVK_Escape)), "Escape")
        XCTAssertEqual(KeyCodeNames.name(for: Int64(kVK_Return)), "Return")
    }

    func test_name_arrows() {
        XCTAssertEqual(KeyCodeNames.name(for: Int64(kVK_LeftArrow)), "←")
        XCTAssertEqual(KeyCodeNames.name(for: Int64(kVK_UpArrow)), "↑")
    }

    func test_name_unknownReturnsFallback() {
        XCTAssertEqual(KeyCodeNames.name(for: 12345), "Key 12345")
    }

    func test_isAlphanumeric_lettersDigits() {
        XCTAssertTrue(KeyCodeNames.isAlphanumeric(Int64(kVK_ANSI_A)))
        XCTAssertTrue(KeyCodeNames.isAlphanumeric(Int64(kVK_ANSI_0)))
    }

    func test_isAlphanumeric_specialKeysAreNot() {
        XCTAssertFalse(KeyCodeNames.isAlphanumeric(Int64(kVK_F1)))
        XCTAssertFalse(KeyCodeNames.isAlphanumeric(Int64(kVK_Escape)))
        XCTAssertFalse(KeyCodeNames.isAlphanumeric(Int64(kVK_Space)))
    }
}
