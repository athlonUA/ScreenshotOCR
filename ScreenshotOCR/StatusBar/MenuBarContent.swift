import SwiftUI

/// Popover-style menu shown by `MenuBarExtra` with `.menuBarExtraStyle(.window)`.
///
/// Visual style mirrors the Transcribr popover: stock `.borderedProminent` /
/// `.bordered` button styles with system tints, monospaced inline hotkey,
/// red-washed permission banner, terse error footer.
struct MenuBarContent: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var storage: AppSettings
    @ObservedObject var permissions: PermissionsService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            permissionsBanner
            primaryAction
            if let error = coordinator.lastError {
                errorBanner(error)
            }
            secondaryActions

            Divider()

            hotkeyRow

            Divider()
            quitRow
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { permissions.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.primary)
            Text("Screenshot OCR")
                .font(.headline)
            Spacer()
            if coordinator.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Primary action

    @ViewBuilder
    private var primaryAction: some View {
        if coordinator.isWorking {
            // Disabled busy spinner — mirrors Transcribr's `busyButton` shape.
            Button(action: {}) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Working…")
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .tint(.green)
            .buttonStyle(.borderedProminent)
            .disabled(true)
        } else {
            Button {
                Task { await coordinator.runScreenshotFlow() }
            } label: {
                Label("Capture", systemImage: "dot.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .tint(.green)
            .buttonStyle(.borderedProminent)
            // Permission gates the CTA. The red banner above is the only
            // signal the user needs — no error toast on click.
            .disabled(permissions.screenRecording != .granted)
        }
    }

    // MARK: - Secondary actions

    private var secondaryActions: some View {
        HStack(spacing: 6) {
            Button {
                coordinator.copyLastText()
            } label: {
                Label("Copy Last", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.regular)
            .buttonStyle(.bordered)
            .tint(.blue)
            .disabled(storage.lastExtractedText?.isEmpty ?? true)

            Button {
                Task { await coordinator.extractFromFile() }
            } label: {
                Label("Choose File…", systemImage: "doc")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.regular)
            .buttonStyle(.bordered)
            .tint(.blue)
            .disabled(coordinator.isWorking)
        }
    }

    // MARK: - Hotkey row

    private var hotkeyRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.viewfinder")
                .foregroundStyle(.primary)
                .frame(width: 14)
            Text("Capture:")
                .font(.caption)
            if coordinator.isCapturingHotkey {
                Text("Press shortcut…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    coordinator.cancelHotkeyCapture()
                }
                .controlSize(.small)
            } else {
                Text(storage.hotkey.description)
                    .font(.caption.monospaced())
                Spacer()
                Button("Change hotkey") {
                    coordinator.startHotkeyCapture()
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    // MARK: - Permission banner

    /// Always present in the hierarchy so the VStack layout stays consistent;
    /// the `.granted` branch returns `EmptyView()` and contributes no spacing.
    @ViewBuilder
    private var permissionsBanner: some View {
        switch permissions.screenRecording {
        case .granted:
            EmptyView()
        case .notDetermined:
            permissionBanner(
                title: "Screen Recording access required",
                detail: "Enable Screenshot OCR in System Settings → Privacy & Security → Screen Recording, then restart the app.",
                actions: [
                    .init(label: "Request Screen Recording Access") {
                        permissions.requestScreenRecording()
                    },
                ]
            )
        case .denied:
            permissionBanner(
                title: "Screen Recording access required",
                detail: "Enable Screenshot OCR in System Settings → Privacy & Security → Screen Recording, then restart the app.",
                actions: [
                    .init(label: "Request Screen Recording Access") {
                        permissions.requestScreenRecording()
                    },
                    .init(label: "Open System Settings") {
                        permissions.openScreenRecordingSettings()
                    },
                ]
            )
        }
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(5)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Quit

    private var quitRow: some View {
        HStack {
            Button("Quit") { coordinator.quit() }
                .keyboardShortcut("q")
            Spacer()
        }
    }

    // MARK: - Banner helper

    private struct BannerAction: Identifiable {
        var id: String { label }
        let label: String
        let action: () -> Void
    }

    private func permissionBanner(title: String, detail: String, actions: [BannerAction]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.red)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(actions) { entry in
                    Button(entry.label, action: entry.action)
                        .controlSize(.small)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .cornerRadius(6)
    }
}
