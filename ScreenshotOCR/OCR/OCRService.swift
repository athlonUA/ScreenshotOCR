import Foundation
import Vision
import CoreGraphics

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
}
