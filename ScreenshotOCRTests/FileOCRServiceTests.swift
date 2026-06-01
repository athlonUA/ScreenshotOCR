import XCTest
import AppKit
import CoreGraphics
import PDFKit
@testable import ScreenshotOCR

final class FileOCRServiceTests: XCTestCase {

    func test_recognize_pngImage() async throws {
        let url = try Self.writePNG("Hello PNG", to: nil)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await FileOCRService().recognize(at: url)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("hello"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("png"))
    }

    func test_recognize_pdf_singlePage() async throws {
        let url = try Self.writePDF(pageTexts: ["Page Alpha"])
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await FileOCRService().recognize(at: url)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("alpha"))
    }

    func test_recognize_pdf_multiPageConcatenates() async throws {
        let url = try Self.writePDF(pageTexts: ["Page One", "Page Two", "Page Three"])
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await FileOCRService().recognize(at: url)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("one"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("two"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("three"))
    }

    func test_recognize_unreadableFile_throws() async {
        let url = URL(fileURLWithPath: "/tmp/screenshotocr-nonexistent-\(UUID().uuidString).png")
        do {
            _ = try await FileOCRService().recognize(at: url)
            XCTFail("Expected unreadable error")
        } catch FileOCRError.unreadable {
            // expected
        } catch {
            XCTFail("Expected unreadable, got \(error)")
        }
    }

    // MARK: - Helpers

    private static func writePNG(_ text: String, to dir: URL?) throws -> URL {
        let size = CGSize(width: 480, height: 120)
        let cgImage = try renderText(text, size: size)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "FileOCRServiceTests", code: 1)
        }
        let url = (dir ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("ocr-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    private static func writePDF(pageTexts: [String]) throws -> URL {
        let document = PDFDocument()
        for (index, line) in pageTexts.enumerated() {
            let pageSize = CGSize(width: 612, height: 200)
            let image = try renderText(line, size: pageSize)
            let nsImage = NSImage(cgImage: image, size: pageSize)
            guard let page = PDFPage(image: nsImage) else {
                throw NSError(domain: "FileOCRServiceTests", code: 2)
            }
            document.insert(page, at: index)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocr-\(UUID().uuidString).pdf")
        guard document.write(to: url) else {
            throw NSError(domain: "FileOCRServiceTests", code: 3)
        }
        return url
    }

    private static func renderText(_ text: String, size: CGSize) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let width = Int(size.width)
        let height = Int(size.height)
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw NSError(domain: "FileOCRServiceTests", code: 4)
        }
        ctx.setFillColor(CGColor.white)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 42, weight: .regular),
            .foregroundColor: NSColor.black,
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let textSize = attr.size()
        let origin = CGPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2
        )
        attr.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()

        guard let image = ctx.makeImage() else {
            throw NSError(domain: "FileOCRServiceTests", code: 5)
        }
        return image
    }
}
