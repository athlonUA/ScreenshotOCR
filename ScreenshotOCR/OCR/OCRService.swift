import Foundation
import Vision
import CoreGraphics
import CoreText

enum OCRError: LocalizedError {
    case visionFailed(Error)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .visionFailed(let error): return "Vision failed: \(error.localizedDescription)"
        case .emptyResult: return "No text recognized."
        }
    }
}

/// Runs Apple Vision text recognition on a single image.
///
/// Configured for English / Spanish / Russian / Ukrainian with accurate
/// recognition and language correction. Vision picks per-line language
/// automatically — the order of `recognitionLanguages` is only a tiebreaker
/// when a glyph is ambiguous between two languages on the list.
///
/// Behaviour for unlisted languages: Vision's text-detection stage still
/// finds the glyphs, but recognition quality drops sharply. Latin-script
/// languages outside the list (French, German, Portuguese, Italian…) tend
/// to come back legible with some diacritics replaced by their closest
/// English/Spanish neighbours; non-Latin scripts (CJK, Arabic, Hebrew,
/// Hindi, Thai…) are mostly garbled or empty. Add them to
/// `recognitionLanguages` if you need reliable support.
struct OCRService {
    /// `nil` returned only when Vision succeeded with zero observations
    /// (e.g. blank screenshot). Caller decides whether that's an error.
    func recognize(_ image: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = Self.languages

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try await Task.detached(priority: .userInitiated) {
                try handler.perform([request])
            }.value
        } catch {
            throw OCRError.visionFailed(error)
        }

        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let joined = lines.joined(separator: "\n")
        if joined.isEmpty {
            throw OCRError.emptyResult
        }
        return joined
    }

    static let languages: [String] = ["en-US", "es-ES", "ru-RU", "uk-UA"]

    /// Runs one throwaway recognition so Vision compiles and caches its
    /// models ahead of the first real capture.
    ///
    /// Why: on a fresh macOS build Vision's E5/ANE model cache
    /// (`~/Library/Caches/<bundle id>/com.apple.e5rt.e5bundlecache/<os build>`)
    /// is empty, and the first `accurate` request blocks for ~35 s while the
    /// models compile. Quitting mid-compile leaves only a `.tmp` bundle, so the
    /// next run starts cold again. Paying that cost at launch, with UI
    /// feedback, keeps the first hotkey press fast. Failures are ignored —
    /// a real request will surface them.
    func warmUp() async {
        guard let image = Self.makeWarmUpImage() else { return }
        _ = try? await recognize(image)
    }

    /// Latin + Cyrillic sample so the warm-up touches the same script models
    /// as `languages`. ASCII source via `\u{}` escapes, like the test fixtures:
    /// "Hello world Privet Pryvit".
    static func makeWarmUpImage() -> CGImage? {
        let text = "Hello world \u{041F}\u{0440}\u{0438}\u{0432}\u{0435}\u{0442} \u{041F}\u{0440}\u{0438}\u{0432}\u{0456}\u{0442}"
        let width = 800
        let height = 120
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))

        let font = CTFontCreateUIFontForLanguage(.system, 40, nil) ?? CTFontCreateWithName("Helvetica" as CFString, 40, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
        ctx.textPosition = CGPoint(x: 20, y: 40)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
        return ctx.makeImage()
    }
}
