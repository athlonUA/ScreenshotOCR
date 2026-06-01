import AppKit
import Carbon.HIToolbox

/// Owns the global hotkey registration via Carbon `RegisterEventHotKey`.
///
/// Why Carbon and not `CGEventTap`:
/// - `RegisterEventHotKey` does **not** require the Accessibility permission;
///   it only needs the standard app event-target hook-up. For our flow that is
///   enough, and asking for one fewer permission is a better UX.
/// - We don't need to consume the keystroke from focused apps — only react.
///
/// **Single-instance invariant.** The Carbon API takes a C callback, so we
/// route through a static `activeManager` slot rather than `Unmanaged`. The
/// type is intended to be owned by exactly one component at a time
/// (`AppCoordinator`); creating a second instance silently steals the slot
/// from the first. Debug builds assert this; release builds tolerate the
/// situation but only the most recent registrant receives callbacks.
///
/// **Threading.** All public methods are `@MainActor`. Carbon's hotkey APIs
/// (`RegisterEventHotKey`, `UnregisterEventHotKey`, `InstallEventHandler`,
/// `RemoveEventHandler`) must run on the main thread because they mutate the
/// application event target, which lives on the main run loop. `deinit` runs
/// synchronously on whichever thread releases the last reference; the only
/// owner is `AppCoordinator` (a `@MainActor` class), so in practice this is
/// the main thread.
@MainActor
final class HotkeyManager {
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private static let signature: OSType = {
        // FourCharCode "SOCR" — Screenshot OCR. Just an identifier for the OS.
        let bytes: [UInt8] = [0x53, 0x4F, 0x43, 0x52]
        return bytes.reduce(0) { ($0 << 8) | OSType($1) }
    }()
    private static let hotKeyID: UInt32 = 1

    init() {
        assert(Self.activeManager == nil,
               "HotkeyManager is a single-instance type; the previous instance was not torn down before a new one was created.")
    }

    deinit {
        // Tear down our Carbon resources. `unregister()` would also reset
        // `Self.activeManager`, but we can't call `@MainActor` methods from a
        // nonisolated deinit. Instead inline the minimum:
        // - Carbon resource handles are released here (cheap, no actor hop).
        // - The static slot is cleared via `assumeIsolated` so a future `init`
        //   doesn't see a dangling reference.
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        MainActor.assumeIsolated {
            if Self.activeManager === self {
                Self.activeManager = nil
            }
        }
    }

    /// Registers `hotkey` globally. Replaces any previously registered combo.
    /// Returns `false` if the OS refused (most commonly because the combo is
    /// already taken by a system shortcut).
    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            return false
        }
        self.hotKeyRef = ref
        assert(Self.activeManager == nil || Self.activeManager === self,
               "Two HotkeyManagers are alive at once — only the most recent will receive callbacks.")
        Self.activeManager = self
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if Self.activeManager === self {
            Self.activeManager = nil
        }
    }

    // MARK: - Event handler installation

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handlerCallback,
            1,
            &spec,
            nil,
            &handler
        )
        if status == noErr {
            eventHandlerRef = handler
        }
    }

    /// Weak pointer to the currently registered manager. Read from the Carbon
    /// handler (which runs on the main run loop, then we re-dispatch to main
    /// to satisfy `@MainActor` `onTrigger` calls); written from
    /// `register`/`unregister`/`deinit`, all on the main thread.
    ///
    /// `nonisolated(unsafe)` is correct here because every actual access lands
    /// on the main thread; the singleton invariant (see type comment) keeps
    /// the slot from being trampled.
    nonisolated(unsafe) static weak var activeManager: HotkeyManager?

    private static let handlerCallback: EventHandlerUPP = { _, _, _ in
        DispatchQueue.main.async {
            HotkeyManager.activeManager?.onTrigger?()
        }
        return noErr
    }
}
