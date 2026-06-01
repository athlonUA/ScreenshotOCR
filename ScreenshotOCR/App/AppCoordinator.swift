import AppKit
import Combine
import UniformTypeIdentifiers

/// Central orchestrator that wires the hotkey, screenshot selector, OCR
/// services, clipboard and storage together.
///
/// Lifecycle:
/// 1. On init: register the global hotkey from `AppSettings.hotkey`.
/// 2. Hotkey press → screenshot overlay → OCR → clipboard + `lastExtractedText`.
/// 3. File picker → file OCR → clipboard + `lastExtractedText`.
/// 4. Hotkey recorder window → save new hotkey → re-register globally.
@MainActor
final class AppCoordinator: ObservableObject {
    /// True while a screenshot, OCR run, or file OCR is in progress. Menu
    /// items and the status-bar icon read this to dim/animate themselves and
    /// to debounce repeated hotkey presses.
    @Published private(set) var isWorking: Bool = false
    /// Last user-facing error message. Cleared when the next run starts.
    @Published private(set) var lastError: String?

    let storage: AppSettings
    let permissions: PermissionsService

    private let hotkeyManager = HotkeyManager()
    private let selector = ScreenshotAreaSelector()
    private let ocr = OCRService()
    private let fileOCR: FileOCRService
    private let clipboard = ClipboardService()
    private let recorderWindow = HotkeyRecorderWindow()

    init(storage: AppSettings, permissions: PermissionsService) {
        self.storage = storage
        self.permissions = permissions
        self.fileOCR = FileOCRService(ocr: self.ocr)

        hotkeyManager.onTrigger = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.runScreenshotFlow()
            }
        }
        if !hotkeyManager.register(storage.hotkey) {
            lastError = "Could not register \(storage.hotkey.description). The combination may already be taken by another app — set a new one from the menu."
        }
    }

    // MARK: - Hotkey flow

    func runScreenshotFlow() async {
        guard !isWorking else { return }
        lastError = nil

        // Refresh permission lazily — the user may have toggled it in System
        // Settings since launch. If still missing, bail silently: the
        // disabled CTA and red permission banner already tell that story;
        // an error toast would be redundant.
        permissions.refresh()
        guard permissions.screenRecording == .granted else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            guard let image = try await selector.capture() else { return }
            let text = try await ocr.recognize(image)
            saveResult(text)
        } catch {
            lastError = errorMessage(error)
        }
    }

    // MARK: - Replace hotkey

    func startHotkeyReplacement() {
        recorderWindow.present(initial: storage.hotkey) { [weak self] newHotkey in
            self?.applyHotkey(newHotkey)
        }
    }

    private func applyHotkey(_ hotkey: Hotkey) {
        let previous = storage.hotkey
        if hotkeyManager.register(hotkey) {
            storage.hotkey = hotkey
            return
        }
        // Roll back to the previous hotkey so the user isn't left with no
        // working shortcut. If even the rollback fails, surface that too.
        if !hotkeyManager.register(previous) {
            lastError = "Failed to register \(hotkey.description), and could not restore \(previous.description) either."
        } else {
            lastError = "Failed to register \(hotkey.description). It may be taken by another app — keeping \(previous.description)."
        }
    }

    // MARK: - Copy last text

    func copyLastText() {
        guard let text = storage.lastExtractedText, !text.isEmpty else { return }
        clipboard.copy(text)
    }

    // MARK: - File OCR

    func extractFromFile() async {
        guard !isWorking else { return }
        lastError = nil

        let panel = NSOpenPanel()
        panel.allowedContentTypes = FileOCRService.supportedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose an image or PDF to extract text from"
        panel.prompt = "Extract"

        NSApp.activate(ignoringOtherApps: true)

        // Use the async `begin(completionHandler:)` flavour so we don't
        // block the main thread inside an `async` function and so the
        // `MenuBarExtra` popover dismisses cleanly while the panel is up.
        let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let url = panel.url else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            let text = try await fileOCR.recognize(at: url)
            saveResult(text)
        } catch {
            lastError = errorMessage(error)
        }
    }

    // MARK: - Quit

    func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func saveResult(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "No text recognized."
            return
        }
        clipboard.copy(trimmed)
        storage.lastExtractedText = trimmed
    }

    private func errorMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
