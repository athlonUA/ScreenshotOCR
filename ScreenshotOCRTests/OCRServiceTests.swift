import XCTest
import AppKit
import CoreGraphics
import Vision
@testable import ScreenshotOCR

/// Integration tests against Apple Vision. They render text into a bitmap and
/// expect Vision to roundtrip it back. Vision's accuracy is high enough on
/// rendered Helvetica text that we can assert content equality up to
/// punctuation noise.
///
/// Cyrillic fixtures are written via `\u{}` escapes so the source file stays
/// ASCII while still exercising the Russian / Ukrainian recognition paths
/// promised by `OCRService.languages`. Each constant is annotated with its
/// transliteration for readability.
final class OCRServiceTests: XCTestCase {

    // MARK: - Cyrillic fixtures (ASCII-source via \u{} escapes)

    // "Privet mir" — Russian "Hello world"
    private static let russianGreeting = "\u{041F}\u{0440}\u{0438}\u{0432}\u{0435}\u{0442} \u{043C}\u{0438}\u{0440}"
    // "privet" — Russian "hello" (lowercased for case-insensitive assertion)
    private static let russianHello = "\u{043F}\u{0440}\u{0438}\u{0432}\u{0435}\u{0442}"
    // "mir" — Russian "world"
    private static let russianWorld = "\u{043C}\u{0438}\u{0440}"

    // "Pryvit svit" — Ukrainian "Hello world"
    private static let ukrainianGreeting = "\u{041F}\u{0440}\u{0438}\u{0432}\u{0456}\u{0442} \u{0441}\u{0432}\u{0456}\u{0442}"
    // "pryvit" — Ukrainian "hello"
    private static let ukrainianHello = "\u{043F}\u{0440}\u{0438}\u{0432}\u{0456}\u{0442}"
    // "svit" — Ukrainian "world"
    private static let ukrainianWorld = "\u{0441}\u{0432}\u{0456}\u{0442}"

    func test_recognize_englishLine() async throws {
        let image = try Self.render("Hello World", size: CGSize(width: 480, height: 96))
        let text = try await OCRService().recognize(image)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("hello"),
                      "Expected 'hello' in recognized text, got: \(text)")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("world"),
                      "Expected 'world' in recognized text, got: \(text)")
    }

    func test_recognize_russianLine() async throws {
        let image = try Self.render(Self.russianGreeting, size: CGSize(width: 480, height: 96))
        let text = try await OCRService().recognize(image)
        XCTAssertTrue(text.localizedCaseInsensitiveContains(Self.russianHello),
                      "Expected Russian 'hello' in recognized text, got: \(text)")
        XCTAssertTrue(text.localizedCaseInsensitiveContains(Self.russianWorld),
                      "Expected Russian 'world' in recognized text, got: \(text)")
    }

    func test_recognize_ukrainianLine() async throws {
        let image = try Self.render(Self.ukrainianGreeting, size: CGSize(width: 480, height: 96))
        let text = try await OCRService().recognize(image)
        XCTAssertTrue(text.localizedCaseInsensitiveContains(Self.ukrainianHello),
                      "Expected Ukrainian 'hello' in recognized text, got: \(text)")
        XCTAssertTrue(text.localizedCaseInsensitiveContains(Self.ukrainianWorld),
                      "Expected Ukrainian 'world' in recognized text, got: \(text)")
    }

    func test_recognize_spanishLine() async throws {
        let image = try Self.render("Hola mundo", size: CGSize(width: 480, height: 96))
        let text = try await OCRService().recognize(image)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("hola"),
                      "Expected 'hola' in recognized text, got: \(text)")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("mundo"),
                      "Expected 'mundo' in recognized text, got: \(text)")
    }

    func test_recognize_blankImage_throwsEmptyResult() async {
        let image = try! Self.renderBlank(size: CGSize(width: 200, height: 80))
        do {
            _ = try await OCRService().recognize(image)
            XCTFail("Expected emptyResult error")
        } catch OCRError.emptyResult {
            // expected
        } catch {
            XCTFail("Expected OCRError.emptyResult, got \(error)")
        }
    }

    func test_languages_configuration() {
        XCTAssertEqual(OCRService.languages, ["en-US", "es-ES", "ru-RU", "uk-UA"])
    }

    // MARK: - Helpers

    private static func render(_ text: String, size: CGSize) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let width = Int(size.width)
        let height = Int(size.height)
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw NSError(domain: "OCRServiceTests", code: 1)
        }
        ctx.setFillColor(CGColor.white)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 36, weight: .regular),
            .foregroundColor: NSColor.black,
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)

        NSGraphicsContext.saveGraphicsState()
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = nsCtx
        let textSize = attr.size()
        let origin = CGPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2
        )
        attr.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()

        guard let image = ctx.makeImage() else {
            throw NSError(domain: "OCRServiceTests", code: 2)
        }
        return image
    }

    private static func renderBlank(size: CGSize) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let width = Int(size.width)
        let height = Int(size.height)
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw NSError(domain: "OCRServiceTests", code: 1)
        }
        ctx.setFillColor(CGColor.white)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = ctx.makeImage() else {
            throw NSError(domain: "OCRServiceTests", code: 2)
        }
        return image
    }
}
