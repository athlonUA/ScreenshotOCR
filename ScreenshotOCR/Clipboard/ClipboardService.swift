import AppKit

/// Thin wrapper around `NSPasteboard.general` so callers don't have to deal
/// with `clearContents()` / `setString(_:forType:)` directly, and so we have
/// a single seam to mock in tests.
struct ClipboardService {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    @discardableResult
    func copy(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    func currentString() -> String? {
        pasteboard.string(forType: .string)
    }
}
