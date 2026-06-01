import XCTest
import Carbon.HIToolbox
import CoreGraphics
@testable import ScreenshotOCR

@MainActor
final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "test.screenshotocr.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func test_init_withoutStoredValues_usesDefaults() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.hotkey, .default)
        XCTAssertNil(settings.lastExtractedText)
    }

    func test_init_loadsStoredHotkey() throws {
        let custom = Hotkey(
            keyCode: Int64(kVK_ANSI_K),
            flags: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue
        )
        let data = try JSONEncoder().encode(custom)
        defaults.set(data, forKey: AppSettings.hotkeyKey)

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.hotkey, custom)
    }

    func test_updatingHotkey_persistsToDefaults() throws {
        let settings = AppSettings(defaults: defaults)
        let updated = Hotkey(
            keyCode: Int64(kVK_F5),
            flags: CGEventFlags.maskCommand.rawValue
        )
        settings.hotkey = updated

        let raw = try XCTUnwrap(defaults.data(forKey: AppSettings.hotkeyKey))
        let decoded = try JSONDecoder().decode(Hotkey.self, from: raw)
        XCTAssertEqual(decoded, updated)
    }

    func test_updatingLastText_persists() {
        let settings = AppSettings(defaults: defaults)
        settings.lastExtractedText = "Hello, world!"
        XCTAssertEqual(defaults.string(forKey: AppSettings.lastTextKey), "Hello, world!")
    }

    func test_clearingLastText_removesValue() {
        defaults.set("stale", forKey: AppSettings.lastTextKey)
        let settings = AppSettings(defaults: defaults)
        settings.lastExtractedText = nil
        XCTAssertNil(defaults.string(forKey: AppSettings.lastTextKey))
    }

    func test_emptyLastText_removesValue() {
        let settings = AppSettings(defaults: defaults)
        settings.lastExtractedText = "non-empty"
        settings.lastExtractedText = ""
        XCTAssertNil(defaults.string(forKey: AppSettings.lastTextKey))
    }

    func test_oversizedLastText_isTruncatedByteBudget() {
        let settings = AppSettings(defaults: defaults)
        let huge = String(repeating: "a", count: AppSettings.lastTextMaxBytes + 2048)
        settings.lastExtractedText = huge

        let stored = defaults.string(forKey: AppSettings.lastTextKey)
        XCTAssertNotNil(stored)
        XCTAssertLessThanOrEqual(stored!.utf8.count, AppSettings.lastTextMaxBytes)
    }
}
