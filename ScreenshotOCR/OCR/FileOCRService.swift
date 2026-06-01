import AppKit
import PDFKit
import UniformTypeIdentifiers

enum FileOCRError: LocalizedError {
    case unsupportedType(String)
    case unreadable(URL)
    case pdfRenderFailed(pageIndex: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let ext): return "Unsupported file type: .\(ext)"
        case .unreadable(let url): return "Could not read file: \(url.lastPathComponent)"
        case .pdfRenderFailed(let page): return "Failed to render PDF page \(page + 1)"
        }
    }
}

/// OCR for files chosen via the file picker.
///
/// Images go straight to `OCRService`. PDFs are rendered page-by-page at
/// `pdfRenderScale` and OCR'd in order; per-page text is joined with a form-feed
/// separator so the result is greppable as a single string.
struct FileOCRService {
    static let supportedTypes: [UTType] = [.png, .jpeg, .heic, .tiff, .bmp, .gif, .pdf]

    /// Rendering DPI multiplier for PDF pages. Vision works best on 1500–3000 px
    /// images; for a typical Letter page that's ~2x the natural rendering size.
    static let pdfRenderScale: CGFloat = 2.0

    private let ocr: OCRService

    init(ocr: OCRService = OCRService()) {
        self.ocr = ocr
    }

    func recognize(at url: URL) async throws -> String {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if type?.conforms(to: .pdf) == true {
            return try await recognizePDF(at: url)
        }
        return try await recognizeImage(at: url)
    }

    // MARK: - Image

    private func recognizeImage(at url: URL) async throws -> String {
        guard let image = NSImage(contentsOf: url) else {
            throw FileOCRError.unreadable(url)
        }
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw FileOCRError.unreadable(url)
        }
        return try await ocr.recognize(cgImage)
    }

    // MARK: - PDF

    private func recognizePDF(at url: URL) async throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw FileOCRError.unreadable(url)
        }
        var pages: [String] = []
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index) else { continue }
            let cgImage = try renderPDFPage(page, pageIndex: index)
            do {
                let text = try await ocr.recognize(cgImage)
                pages.append(text)
            } catch OCRError.emptyResult {
                // Empty page — keep an empty slot so page numbers stay stable.
                pages.append("")
            }
        }
        let joined = pages.joined(separator: "\n\u{000C}\n") // form-feed between pages
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func renderPDFPage(_ page: PDFPage, pageIndex: Int) throws -> CGImage {
        let bounds = page.bounds(for: .mediaBox)
        let scale = Self.pdfRenderScale
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0 else {
            throw FileOCRError.pdfRenderFailed(pageIndex: pageIndex)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw FileOCRError.pdfRenderFailed(pageIndex: pageIndex)
        }
        ctx.setFillColor(CGColor.white)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)

        guard let image = ctx.makeImage() else {
            throw FileOCRError.pdfRenderFailed(pageIndex: pageIndex)
        }
        return image
    }
}
