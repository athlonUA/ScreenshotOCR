import Foundation
import Combine

/// Persistent app state stored in `UserDefaults`.
///
/// Holds the active hotkey and the most recent OCR result. Both fields are
/// `@Published` so SwiftUI menu items reflect changes immediately, and writes
/// are funnelled through `didSet` so the persisted copy never drifts from
/// the in-memory one.
@MainActor
final class AppSettings: ObservableObject {
    static let hotkeyKey = "screenshotocr.hotkey"
    static let lastTextKey = "screenshotocr.lastExtractedText"

    /// Hard cap on persisted text size. Keeps the `plist` from ballooning if a
    /// user happens to OCR a long PDF — they still get the full text in the
    /// clipboard immediately; only the "Copy last extracted text" cache is bounded.
    static let lastTextMaxBytes = 1 * 1024 * 1024

    @Published var hotkey: Hotkey {
        didSet { persistHotkey(hotkey) }
    }

    @Published var lastExtractedText: String? {
        didSet { persistLastText(lastExtractedText) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.hotkeyKey),
           let stored = try? JSONDecoder().decode(Hotkey.self, from: data) {
            self.hotkey = stored
        } else {
            self.hotkey = .default
        }

        if let stored = defaults.string(forKey: Self.lastTextKey), !stored.isEmpty {
            self.lastExtractedText = stored
        } else {
            self.lastExtractedText = nil
        }
    }

    private func persistHotkey(_ hotkey: Hotkey) {
        if let data = try? JSONEncoder().encode(hotkey) {
            defaults.set(data, forKey: Self.hotkeyKey)
        }
    }

    private func persistLastText(_ text: String?) {
        guard let text, !text.isEmpty else {
            defaults.removeObject(forKey: Self.lastTextKey)
            return
        }
        // Truncate by UTF-8 byte budget without splitting a grapheme cluster.
        if text.utf8.count <= Self.lastTextMaxBytes {
            defaults.set(text, forKey: Self.lastTextKey)
            return
        }
        var truncated = text
        while truncated.utf8.count > Self.lastTextMaxBytes, !truncated.isEmpty {
            truncated.removeLast()
        }
        defaults.set(truncated, forKey: Self.lastTextKey)
    }
}
