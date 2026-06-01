# Screenshot OCR — Requirements

## 1. Overview

A lightweight macOS application for recognising text on the screen and from files via Apple Vision Framework.
Primary flow: the user presses a global hotkey, drags a selection rectangle, the captured region is OCR'd, and the recognised text is copied to the clipboard. No main window, no result popup — only the menu bar plus system dialogs (file picker, permission prompts).

## 2. Application type

- **Menu-bar only** (`LSUIElement = true` in `Info.plist`).
- No main application window.
- Does not appear in the Dock or Cmd+Tab switcher.
- Icon shown only in the macOS menu bar.
- Clicking the icon opens a popover with controls.

## 3. Menu layout

### 3.1 Current hotkey
- Informational, disabled row showing the active combination.
- Format: `Capture: ⇧+⌘+O`.
- Default: `Cmd + Shift + O`.
- Updates immediately after the hotkey is replaced.

### 3.2 Replace hotkey…
- Opens a compact modal / window with `HotkeyRecorder`.
- The user presses the desired combination — it is recorded and validated (must include at least one modifier when used with an alphanumeric key, must not be a bare modifier key, must not conflict with reserved system shortcuts).
- On Save:
  - the previous hotkey is unregistered,
  - the new one is persisted in `UserDefaults`,
  - the new one is registered globally,
  - the `Capture:` label updates.
  - If registration of the new combo fails, the previous binding is restored and the user is notified.
- Esc cancels; a "Reset to default" button is provided.

### 3.3 Copy last extracted text
- Copies the last recognised text into `NSPasteboard.general`.
- If no text has been captured yet → row **disabled** (`isEnabled = false`).

### 3.4 Extract text from file…
- Opens `NSOpenPanel` (async via `panel.begin(completionHandler:)`).
- Allowed types: PNG, JPEG, HEIC, TIFF, BMP, GIF, PDF (multi-page PDFs are rendered page by page, OCR'd, and joined with a form-feed separator).
- On success:
  - OCR is performed via `FileOCRService`,
  - the result is copied to the clipboard,
  - `lastExtractedText` is updated,
  - the **Copy last extracted text** row becomes enabled.
- Errors (unreadable file, empty OCR result) surface as a single-line caption.

### 3.5 Quit
- `NSApp.terminate(nil)`.

## 4. Primary flow (hotkey)

1. The user presses the global hotkey (default `Cmd+Shift+O`).
2. `HotkeyManager` notifies `ScreenshotAreaSelector` via a closure routed through `AppCoordinator`.
3. A translucent overlay window appears on every connected screen with a crosshair cursor.
4. The user drags a selection rectangle.
5. On mouse-up:
   - the overlay is dismissed,
   - the selected region is captured via `ScreenCaptureKit.SCScreenshotManager.captureImage(contentFilter:configuration:)`, with `sourceRect` in the chosen `SCDisplay`'s coordinate space and Retina scale derived from `NSScreen.backingScaleFactor`,
   - the resulting `CGImage` is passed to `OCRService`.
6. `OCRService` runs `VNRecognizeTextRequest` with languages `en-US`, `es-ES`, `ru-RU`, `uk-UA`, `recognitionLevel = .accurate`, `usesLanguageCorrection = true`.
7. The recognised text:
   - is copied to `NSPasteboard.general`,
   - is persisted as `lastExtractedText` (UserDefaults).
8. No result window is shown.
9. Esc / right-click during selection cancels the operation without touching the clipboard.

## 5. Technical requirements

| Requirement | Value |
|---|---|
| Platform | macOS 14 Sonoma (minimum — `SCScreenshotManager` is required) |
| Language | Swift |
| UI framework | SwiftUI + AppKit (for `NSStatusItem` / `MenuBarExtra`, overlay windows, `NSOpenPanel`) |
| OCR | Apple Vision Framework (`VNRecognizeTextRequest`) |
| LLM | **Not used** |
| Supported OCR languages | English, Spanish, Russian, Ukrainian |
| Clipboard | `NSPasteboard.general` |
| Global hotkeys | Carbon `RegisterEventHotKey` (no Accessibility permission required) |
| Permissions | Screen Recording (mandatory for off-window screen capture) |
| File picker | `NSOpenPanel` (async API) |
| Persistence | `UserDefaults` |
| Sandbox | Disabled for this menu-bar utility — same convention as Rectangle / Magnet / Transcribr |

### 5.1 Permissions
- On first run the app checks Screen Recording permission (`CGPreflightScreenCaptureAccess()`).
- If the permission is missing, the menu shows a red banner with `Request Screen Recording Access` and `Open System Settings` actions.
- Without Screen Recording the hotkey + area capture flow is disabled (the primary CTA is `.disabled`); `Extract text from file` keeps working independently.

## 6. Architecture

Small, single-responsibility components. No singletons (except the documented one-slot invariant in `HotkeyManager`).

```
ScreenshotOCRApp            // @main, MenuBarExtra(.window) only
└── AppCoordinator          // @MainActor orchestrator
    ├── HotkeyManager       // global hotkey via Carbon RegisterEventHotKey
    ├── HotkeyRecorderWindow / HotkeyRecorderView
    ├── ScreenshotAreaSelector + SelectionOverlayView
    ├── OCRService          // VNRecognizeTextRequest → String
    ├── FileOCRService      // PNG/JPEG/HEIC/TIFF/BMP/GIF/PDF → CGImage(s) → OCRService
    ├── ClipboardService    // NSPasteboard wrapper
    ├── PermissionsService  // Screen Recording probe + System Settings deep link
    └── AppSettings         // UserDefaults-backed @Published store
        ├── currentHotkey   // Codable { keyCode: Int64, flags: UInt64 }
        └── lastExtractedText // String?
```

### 6.1 Coordination
- `AppCoordinator` connects `HotkeyManager` → `ScreenshotAreaSelector` → `OCRService` → `ClipboardService` → `AppSettings.lastExtractedText` → menu refresh.
- Long-running work (file OCR, PDF) runs on a background priority `Task.detached`; UI updates land on `@MainActor`.

### 6.2 Menu state
- `MenuBarContent` observes `AppCoordinator`, `AppSettings`, and `PermissionsService` directly via `@ObservedObject` — no Combine glue needed.
- The popover refreshes permission state on `.onAppear` (macOS does not push TCC changes into a running process; popover-open is the natural retry).

## 7. Persistence

Stored in `UserDefaults`:
- `screenshotocr.hotkey` — JSON-encoded `{ keyCode: Int64, flags: UInt64 }` where `flags` uses `CGEventFlags.rawValue` (bit-compatible with `NSEvent.ModifierFlags.rawValue`). Decoding routes through the masking initialiser so stray bits (Fn / CapsLock / NumPad) are stripped.
- `screenshotocr.lastExtractedText` — `String`. Soft-capped at 1 MB UTF-8 to keep the `plist` from ballooning on huge OCR results (the clipboard still receives the full text immediately).
- `screenshotocr.didRequestScreenRecording` — `Bool` flag distinguishing "user never asked" from "user denied".

First-launch defaults:
- `hotkey = Cmd + Shift + O`
- `lastExtractedText = nil`

## 8. Non-functional constraints

- **No main window.** No SwiftUI `WindowGroup` / `Settings` scenes that surface as windows.
- **Lightweight.** Cold start under 1 second, minimal idle RAM, no background thread pools beyond Vision's own.
- **No result window.** The OCR result is delivered only via the clipboard and (for repeat copy) the menu item.
- **No telemetry, no network calls.** Everything runs locally.
- **Multi-monitor support.** The overlay covers every connected display; capture picks the display with the largest intersection area and clamps the selection to its bounds. Retina scaling is honoured via `NSScreen.backingScaleFactor`.
- **Cancellation.** Esc / right-click during selection cancels; a repeated hotkey press while an overlay is open is silently dropped (the first selection wins).

## 9. Out of scope

- History of recognitions (only the most recent result is kept).
- In-app editing / post-processing of recognised text.
- Cloud OCR, LLM post-processing.
- A full preferences window (one hotkey is enough at this stage).
- Export to file, drag-and-drop into the menu icon.

## 10. Definition of Done

- [ ] App launches as menu-bar-only — no Dock icon, no window.
- [ ] Default hotkey `Cmd+Shift+O` works globally, including when other apps are frontmost.
- [ ] `Replace hotkey` re-registers and persists the new combination across launches.
- [ ] Region capture works on a single display and across multiple displays, Retina and non-Retina.
- [ ] OCR recognises en/es/ru/uk text with usable accuracy on typical screenshots.
- [ ] After a hotkey flow the clipboard contains the recognised text; `lastExtractedText` is updated.
- [ ] `Copy last extracted text` is disabled until the first successful OCR.
- [ ] `Extract text from file` works for PNG / JPEG / HEIC / TIFF / BMP / GIF / PDF (including multi-page PDFs).
- [ ] `Quit` terminates the process.
- [ ] Unit-test coverage for: `OCRService` (with rendered fixtures), `FileOCRService`, `ClipboardService`, `Hotkey` / `AppSettings` (serialization round-trip), `PermissionsService` (notDetermined / denied state), `KeyCodeNames` (display string).
