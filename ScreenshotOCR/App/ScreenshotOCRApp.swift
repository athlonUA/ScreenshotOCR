import SwiftUI

@main
struct ScreenshotOCRApp: App {
    @StateObject private var storage: AppSettings
    @StateObject private var permissions: PermissionsService
    @StateObject private var coordinator: AppCoordinator

    init() {
        let storage = AppSettings()
        let permissions = PermissionsService()
        let coordinator = AppCoordinator(storage: storage, permissions: permissions)
        _storage = StateObject(wrappedValue: storage)
        _permissions = StateObject(wrappedValue: permissions)
        _coordinator = StateObject(wrappedValue: coordinator)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                coordinator: coordinator,
                storage: storage,
                permissions: permissions
            )
        } label: {
            StatusBarLabel(isWorking: coordinator.isWorking)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Status-bar label. Uses the stock `text.viewfinder` SF Symbol — it stays
/// crisp at menu-bar sizes (16-18 px) and auto-tints with the system theme.
/// A small accent ring overlays in the corner while work is in progress.
private struct StatusBarLabel: View {
    let isWorking: Bool

    var body: some View {
        ZStack {
            Image(systemName: "text.viewfinder")
            if isWorking {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .frame(width: 6, height: 6)
                    .offset(x: 6, y: -6)
            }
        }
    }
}
