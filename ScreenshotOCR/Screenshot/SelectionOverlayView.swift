import AppKit

/// Crosshair overlay view that lives on a single screen. Captures mouse drag
/// and Esc, draws a dimmed background with a "punch-out" selection rectangle.
///
/// All coordinates passed to callbacks are in **global screen coordinates**
/// (origin at bottom-left of the primary screen, Y up — i.e. AppKit
/// `NSScreen.frame` space), so the controller can capture them with
/// `CGWindowListCreateImage` after converting to `CGRect` (Y flipped).
final class SelectionOverlayView: NSView {
    var onSelectionGlobal: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let screen: NSScreen
    private var anchorLocal: CGPoint?
    private var currentLocal: CGPoint?
    private var trackingArea: NSTrackingArea?

    init(screen: NSScreen) {
        self.screen = screen
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .cursorUpdate, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseDown(with event: NSEvent) {
        anchorLocal = convert(event.locationInWindow, from: nil)
        currentLocal = anchorLocal
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentLocal = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentLocal = convert(event.locationInWindow, from: nil)
        defer {
            anchorLocal = nil
            currentLocal = nil
            needsDisplay = true
        }
        guard let rect = currentLocalRect, rect.width >= 3, rect.height >= 3 else {
            onCancel?()
            return
        }
        let global = CGRect(
            x: rect.origin.x + screen.frame.origin.x,
            y: rect.origin.y + screen.frame.origin.y,
            width: rect.width,
            height: rect.height
        )
        onSelectionGlobal?(global)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
        ctx.fill(bounds)

        guard let rect = currentLocalRect else { return }

        // Punch hole — clear the dim layer inside the selection.
        ctx.clear(rect)

        // Selection border.
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.0)
        ctx.stroke(rect)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1.0)
        ctx.stroke(rect.insetBy(dx: -1, dy: -1))

        // Size label.
        let sizeText = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let attr = NSAttributedString(string: sizeText, attributes: attrs)
        let size = attr.size()
        let labelOrigin = CGPoint(
            x: rect.maxX - size.width - 6,
            y: max(rect.minY - size.height - 4, 4)
        )
        let bgRect = CGRect(
            x: labelOrigin.x - 4,
            y: labelOrigin.y - 2,
            width: size.width + 8,
            height: size.height + 4
        )
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        ctx.fill(bgRect)
        attr.draw(at: labelOrigin)
    }

    private var currentLocalRect: CGRect? {
        guard let a = anchorLocal, let c = currentLocal else { return nil }
        return CGRect(
            x: min(a.x, c.x),
            y: min(a.y, c.y),
            width: abs(a.x - c.x),
            height: abs(a.y - c.y)
        ).integral
    }
}
