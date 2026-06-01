# Screenshot OCR

<img src="ScreenshotOCR/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Screenshot OCR icon" width="128" align="right" />

A lightweight menu-bar-only macOS app that captures a screen region (or a file)
and extracts the text from it with Apple Vision Framework. The recognised text
goes straight to the clipboard — no result window, no LLM, no network.

- **Local & private.** Everything runs on-device. No telemetry, no API calls.
- **Fast.** Cold start < 1 s; OCR of a typical screenshot < 0.5 s on Apple Silicon.
- **Multilingual.** English, Spanish, Russian, Ukrainian out of the box.
- **No dependencies.** Only stock Apple frameworks.

## Requirements

- macOS 14 Sonoma or newer (uses `ScreenCaptureKit.SCScreenshotManager`).
- Xcode 15 or newer to build.
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (optional — `.xcodeproj` is
  committed, but `project.yml` is the source of truth).

## Build & run

```bash
# Option A — open the committed project
open ScreenshotOCR.xcodeproj

# Option B — regenerate the project first
xcodegen generate
open ScreenshotOCR.xcodeproj

# Option C — pure CLI build
xcodebuild -project ScreenshotOCR.xcodeproj \
           -scheme ScreenshotOCR \
           -configuration Debug \
           -destination 'platform=macOS' build
```

The built `.app` lands in
`~/Library/Developer/Xcode/DerivedData/ScreenshotOCR-*/Build/Products/Debug/ScreenshotOCR.app`.
Run it with `open` and look for the icon in your menu bar.

## Usage

1. Click the menu-bar icon.
2. Hit **Capture** (or press the global hotkey, default `⇧+⌘+O`).
3. Drag a rectangle around the text you want.
4. The recognised text is already in your clipboard — paste it anywhere.

The popover also offers:

- **Copy Last** — re-copies the most recent OCR result.
- **Choose File…** — runs OCR on a PNG / JPEG / HEIC / TIFF / BMP / GIF / PDF
  (multi-page PDFs are processed page by page).
- **Change hotkey** — record a new global combination.
- **Quit**.

### Permissions

On first launch macOS will prompt for **Screen Recording** permission. After
granting it in *System Settings → Privacy & Security → Screen Recording*, you
have to **restart the app** — macOS does not propagate fresh TCC grants to a
running process. The popover surfaces this with a red banner and inline action
buttons until access is granted.

No Accessibility permission is needed: global hotkeys go through Carbon
`RegisterEventHotKey`, not a CGEventTap.

## Supported languages

`OCRService.languages` (`ScreenshotOCR/OCR/OCRService.swift`) is configured for:

| Language  | BCP-47   |
|-----------|----------|
| English   | `en-US`  |
| Spanish   | `es-ES`  |
| Russian   | `ru-RU`  |
| Ukrainian | `uk-UA`  |

Vision picks the language per line automatically; the list is only a tiebreaker
on ambiguous glyphs. Other Latin-script languages (French, German, Portuguese…)
usually come back legible but with degraded diacritics; non-Latin scripts
(CJK, Arabic, Hebrew, Thai…) need to be added to `recognitionLanguages` to be
recognised reliably.

## Architecture

```
ScreenshotOCRApp                // @main, MenuBarExtra(.window)
└── AppCoordinator              // @MainActor orchestrator
    ├── HotkeyManager           // Carbon RegisterEventHotKey
    ├── HotkeyRecorderWindow/View
    ├── ScreenshotAreaSelector  // multi-monitor overlay
    │   └── SelectionOverlayView
    ├── OCRService              // VNRecognizeTextRequest → String
    ├── FileOCRService          // image / PDF → OCRService
    ├── ClipboardService        // NSPasteboard wrapper
    ├── PermissionsService      // Screen Recording probe + deep link
    └── AppSettings             // UserDefaults-backed @Published store
```

Full requirements and design notes live in
[`REQUIREMENTS.md`](REQUIREMENTS.md).

## Development

### Tests

```bash
xcodebuild -project ScreenshotOCR.xcodeproj \
           -scheme ScreenshotOCR \
           -configuration Debug \
           -destination 'platform=macOS' test
```

44 unit + integration tests cover `Hotkey` / `AppSettings` / `Clipboard` /
`Permissions` / `KeyCodeNames` / `OCRService` (with rendered en/es/ru/uk
fixtures) / `FileOCRService` (PNG + multi-page PDF).

### Project regeneration

```bash
xcodegen generate
```

`project.yml` is the source of truth; the generated `.xcodeproj` is committed
so contributors without `xcodegen` can still build, but it should be considered
read-only — edit `project.yml`, then regenerate.

## License

[MIT](LICENSE) © 2026 Alex Garmatenko
