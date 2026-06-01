import AppKit
import SwiftUI

/// Owns the floating window that hosts `HotkeyRecorderView`. Keeps a single
/// instance at a time and centres it on the active screen.
@MainActor
final class HotkeyRecorderWindow {
    private var window: NSWindow?
    private var resignObserver: NSObjectProtocol?

    func present(initial: Hotkey, onSave: @escaping (Hotkey) -> Void) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = HotkeyRecorderView(
            initial: initial,
            onSave: { [weak self] hotkey in
                onSave(hotkey)
                self?.dismiss()
            },
            onCancel: { [weak self] in
                self?.dismiss()
            }
        )

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Replace hotkey"
        window.styleMask = [.titled, .closable]
        window.level = .modalPanel
        window.isReleasedWhenClosed = false
        window.center()
        window.collectionBehavior = [.moveToActiveSpace]
        self.window = window

        // Close button → treat as cancel.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.dismiss() }
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        if let observer = resignObserver {
            NotificationCenter.default.removeObserver(observer)
            resignObserver = nil
        }
        window?.orderOut(nil)
        window = nil
    }
}
