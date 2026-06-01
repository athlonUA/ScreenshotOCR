import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenshotError: LocalizedError {
    case noPermission
    case noDisplay
    case captureFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noPermission: return "Screen Recording permission is required."
        case .noDisplay: return "No display found for the selected region."
        case .captureFailed(let error): return "Screen capture failed: \(error.localizedDescription)"
        }
    }
}

/// Drives the area-selection overlay across all screens and captures the
/// resulting region as a `CGImage` via `ScreenCaptureKit`.
///
/// We use `SCScreenshotManager.captureImage(contentFilter:configuration:)`
/// (macOS 14+) — `CGWindowListCreateImage` is unavailable in the latest SDK.
/// The overlay windows hide themselves before capture; only the actual screen
/// content under the selection makes it into the resulting image.
@MainActor
final class ScreenshotAreaSelector {
    private var overlayWindows: [NSWindow] = []
    private var escapeMonitor: Any?
    private var inFlight = false

    /// Returns the captured image, or `nil` if the user cancelled.
    /// Throws if Screen Recording is unavailable or capture itself fails.
    func capture() async throws -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenshotError.noPermission
        }
        // Re-entrancy: drop the duplicate request silently. We deliberately do
        // NOT tear down the in-flight capture — the user's first selection
        // should win.
        guard !inFlight else { return nil }
        inFlight = true
        defer { inFlight = false }

        let globalRect: CGRect? = await withCheckedContinuation { (cont: CheckedContinuation<CGRect?, Never>) in
            var resumed = false
            let resume: (CGRect?) -> Void = { rect in
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: rect)
            }
            startOverlays(onRect: { resume($0) }, onCancel: { resume(nil) })
        }
        teardownOverlays()
        guard let rect = globalRect else { return nil }

        // Give the windowserver one tick to actually remove our overlay windows
        // before SCStream snapshots the display.
        try? await Task.sleep(nanoseconds: 50_000_000)
        return try await captureImage(globalRect: rect)
    }

    func cancel() {
        teardownOverlays()
    }

    // MARK: - Overlay lifecycle

    private func startOverlays(onRect: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        var didFinish = false
        let finish: (CGRect?) -> Void = { [weak self] rect in
            guard !didFinish else { return }
            didFinish = true
            self?.teardownOverlays()
            if let rect { onRect(rect) } else { onCancel() }
        }

        // Catch-all Esc handler — `keyDown` on the borderless overlay window
        // can be flaky depending on key-window focus order, so we add a local
        // monitor as a guaranteed back-stop. Right-click / mouse-up cancel
        // paths still go through `SelectionOverlayView`.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                finish(nil)
                return nil
            }
            return event
        }

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isReleasedWhenClosed = false
            window.sharingType = .none // exclude from screen capture

            let view = SelectionOverlayView(screen: screen)
            view.onSelectionGlobal = { rect in finish(rect) }
            view.onCancel = { finish(nil) }
            window.contentView = view

            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            overlayWindows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func teardownOverlays() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
        for window in overlayWindows {
            window.orderOut(nil)
            window.contentView = nil
        }
        overlayWindows.removeAll()
    }

    // MARK: - Capture (ScreenCaptureKit)

    /// Captures the requested region from the display that contains it.
    ///
    /// `globalRect` is in AppKit screen coordinates (Y up, origin at primary
    /// bottom-left). ScreenCaptureKit wants per-display coordinates with Y
    /// down, so we map twice: first pick the right `SCDisplay` from the
    /// containing `NSScreen`, then convert to display-local rect.
    ///
    /// If the selection straddles two displays (rare — usually impossible
    /// because each overlay window only catches events on its own screen),
    /// we pick the screen with the largest intersection area and crop the
    /// rect to that screen.
    private func captureImage(globalRect: CGRect) async throws -> CGImage {
        let screen = NSScreen.screens.max(by: { lhs, rhs in
            intersectionArea(lhs.frame, globalRect) < intersectionArea(rhs.frame, globalRect)
        }) ?? NSScreen.main
        guard let screen, intersectionArea(screen.frame, globalRect) > 0 else {
            throw ScreenshotError.noDisplay
        }
        // Clamp the selection to the chosen screen so any overflow into a
        // neighbouring display is silently dropped instead of producing
        // out-of-bounds `sourceRect` for ScreenCaptureKit.
        let clampedGlobal = globalRect.intersection(screen.frame)
        let cgDisplayID = screen.displayID

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw ScreenshotError.captureFailed(error)
        }
        guard let display = content.displays.first(where: { $0.displayID == cgDisplayID })
                ?? content.displays.first else {
            throw ScreenshotError.noDisplay
        }

        // Convert global rect → display-local rect with Y flipped.
        let screenFrame = screen.frame
        let localX = clampedGlobal.origin.x - screenFrame.origin.x
        let localY = screenFrame.height - (clampedGlobal.origin.y - screenFrame.origin.y) - clampedGlobal.height
        let sourceRect = CGRect(x: localX, y: localY, width: clampedGlobal.width, height: clampedGlobal.height).integral

        let scale = screen.backingScaleFactor
        let pixelWidth = max(1, Int(sourceRect.width * scale))
        let pixelHeight = max(1, Int(sourceRect.height * scale))

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = pixelWidth
        config.height = pixelHeight
        config.showsCursor = false
        config.scalesToFit = false
        config.capturesAudio = false

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw ScreenshotError.captureFailed(error)
        }
    }
}

/// `NSWindow` subclass that can become key/main even with a `.borderless`
/// style mask. Required so the overlay actually receives keyDown events —
/// stock `NSWindow` with borderless style returns `false` from
/// `canBecomeKey`, which means `SelectionOverlayView.keyDown` is never called.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let i = a.intersection(b)
    return i.isNull ? 0 : i.width * i.height
}

private extension NSScreen {
    /// The `CGDirectDisplayID` for this NSScreen, used to match against
    /// `SCDisplay.displayID`.
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = deviceDescription[key] as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }
        return CGMainDisplayID()
    }
}
