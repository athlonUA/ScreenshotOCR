import AppKit
import CoreGraphics

enum ScreenRecordingPermission: Equatable {
    case notDetermined
    case granted
    case denied
}

/// Coordinates the Screen Recording permission.
///
/// macOS does not push permission changes to a running process, so this class
/// caches the last-known status, exposes `refresh()` for explicit re-checks
/// (e.g. when the menu opens), and keeps a `didRequest` flag in `UserDefaults`
/// so we can distinguish "user has never been asked" from "user denied".
@MainActor
final class PermissionsService: ObservableObject {
    static let didRequestScreenRecordingKey = "screenshotocr.didRequestScreenRecording"

    @Published private(set) var screenRecording: ScreenRecordingPermission = .notDetermined

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refresh()
    }

    func refresh() {
        if CGPreflightScreenCaptureAccess() {
            screenRecording = .granted
            return
        }
        let didRequest = defaults.bool(forKey: Self.didRequestScreenRecordingKey)
        screenRecording = didRequest ? .denied : .notDetermined
    }

    /// Triggers the standard macOS prompt the first time, then a settings panel
    /// reminder thereafter. macOS will NOT update the running process's
    /// permission state mid-session — the user must restart the app.
    @discardableResult
    func requestScreenRecording() -> Bool {
        defaults.set(true, forKey: Self.didRequestScreenRecordingKey)
        let granted = CGRequestScreenCaptureAccess()
        refresh()
        return granted
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
