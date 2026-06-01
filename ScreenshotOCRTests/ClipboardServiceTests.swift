import XCTest
import AppKit
@testable import ScreenshotOCR

final class ClipboardServiceTests: XCTestCase {

    func test_copyAndRead_roundTripThroughIsolatedPasteboard() {
        let name = NSPasteboard.Name("test.screenshotocr.\(UUID().uuidString)")
        let pasteboard = NSPasteboard(name: name)
        defer { pasteboard.releaseGlobally() }

        let service = ClipboardService(pasteboard: pasteboard)
        XCTAssertTrue(service.copy("hello — clipboard — round-trip"))
        XCTAssertEqual(service.currentString(), "hello — clipboard — round-trip")
    }

    func test_copy_replacesPreviousValue() {
        let name = NSPasteboard.Name("test.screenshotocr.\(UUID().uuidString)")
        let pasteboard = NSPasteboard(name: name)
        defer { pasteboard.releaseGlobally() }

        let service = ClipboardService(pasteboard: pasteboard)
        _ = service.copy("first")
        _ = service.copy("second")
        XCTAssertEqual(service.currentString(), "second")
    }
}
