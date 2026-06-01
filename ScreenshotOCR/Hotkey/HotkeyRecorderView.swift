import SwiftUI
import AppKit
import CoreGraphics

/// Records a new global hotkey by capturing the next valid key-with-modifiers
/// combo from a local NSEvent monitor. Mirrors the recorder pattern used by
/// Transcribr's `MicMuteService.startCapture`.
struct HotkeyRecorderView: View {
    let initial: Hotkey
    let onSave: (Hotkey) -> Void
    let onCancel: () -> Void

    @State private var draft: Hotkey
    @State private var isRecording = true
    @State private var monitor: Any?

    init(initial: Hotkey, onSave: @escaping (Hotkey) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Press a new shortcut")
                .font(.headline)

            Text(draft.description)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .frame(minWidth: 220, minHeight: 64)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.4),
                                lineWidth: isRecording ? 2 : 1)
                )

            Text(isRecording
                 ? "Hold modifiers (⌘ ⇧ ⌃ ⌥), then press a key. Esc to cancel."
                 : "Press Save to confirm or Cancel to keep the previous hotkey.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack {
                Button("Reset to default") {
                    draft = .default
                    isRecording = false
                }
                Spacer()
                Button("Cancel") { finish(saving: false) }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { finish(saving: true) }
                    .keyboardShortcut(.defaultAction)
                    // Block Save while the recorder is still listening — otherwise
                    // pressing Save before a valid combo silently re-saves `initial`.
                    .disabled(isRecording)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { startMonitoring() }
        .onDisappear { stopMonitoring() }
    }

    private func startMonitoring() {
        stopMonitoring()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            return handle(event: event)
        }
    }

    private func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handle(event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { // Esc
            finish(saving: false)
            return nil
        }
        let keyCode = Int64(event.keyCode)
        let flags = UInt64(event.modifierFlags.rawValue) & Hotkey.modifierMask
        guard Hotkey.isValidForGlobal(keyCode: keyCode, flags: flags) else {
            NSSound.beep()
            return nil
        }
        draft = Hotkey(keyCode: keyCode, flags: flags)
        isRecording = false
        return nil
    }

    private func finish(saving: Bool) {
        stopMonitoring()
        if saving {
            onSave(draft)
        } else {
            onCancel()
        }
    }
}
