import AppKit
import CoreGraphics

/// Single source of truth for the app's visual mark.
///
/// Same geometry is used for:
/// - the status-bar icon (template-rendered, foreground only, monochrome)
/// - the full-colour bundle icon (gradient background + rounded corners)
/// - the SwiftUI header chip in the popover
///
/// Geometry is normalised against a 1.0 canvas and scaled by `size`.
enum AppIconRenderer {
    /// Full-colour rounded-square icon (for `AppIcon.appiconset`).
    static func renderColor(size: CGFloat) -> CGImage? {
        let pixels = Int(size)
        guard pixels > 0 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let radius = size * 0.225
        let bg = CGPath(
            roundedRect: CGRect(origin: .zero, size: CGSize(width: size, height: size)),
            cornerWidth: radius, cornerHeight: radius, transform: nil
        )
        ctx.addPath(bg)
        ctx.clip()

        // Gradient — deep blue → bright blue. Matches the Transcribr aesthetic
        // family while staying distinct.
        let colors = [
            CGColor(red: 0.07, green: 0.27, blue: 0.62, alpha: 1.0),
            CGColor(red: 0.16, green: 0.50, blue: 0.92, alpha: 1.0),
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size),
                end: CGPoint(x: 0, y: 0),
                options: []
            )
        }

        drawMark(in: ctx, size: size, foreground: CGColor.white)

        return ctx.makeImage()
    }

    /// Monochrome mark for the status bar. Drawn in the given `tint`; should
    /// be wrapped in an `NSImage` with `isTemplate = true` so macOS adapts the
    /// colour to the menu-bar background.
    static func renderTemplate(size: CGFloat, tint: CGColor = CGColor.black) -> CGImage? {
        let pixels = Int(size)
        guard pixels > 0 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        drawMark(in: ctx, size: size, foreground: tint)
        return ctx.makeImage()
    }

    static func nsImage(size: CGFloat, template: Bool) -> NSImage? {
        guard let cg = template
                ? renderTemplate(size: size)
                : renderColor(size: size) else { return nil }
        let image = NSImage(cgImage: cg, size: CGSize(width: size, height: size))
        image.isTemplate = template
        return image
    }

    // MARK: - Drawing

    /// Viewfinder corner marks + three text-line bars. `foreground` is the
    /// colour for both elements; on the colour icon it's white, on the
    /// template it's the tint (rendered black, then `isTemplate` flips it).
    private static func drawMark(in ctx: CGContext, size: CGFloat, foreground: CGColor) {
        let inset = size * 0.18
        let frameRect = CGRect(
            x: inset, y: inset,
            width: size - 2 * inset, height: size - 2 * inset
        )
        let cornerLen = size * 0.12
        let stroke = max(1.0, size * 0.05)

        ctx.setStrokeColor(foreground)
        ctx.setLineWidth(stroke)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Four corner brackets. Each bracket is two strokes meeting at a corner
        // of `frameRect`, pointing inward along `cornerLen`.
        for corner in 0..<4 {
            let origin: CGPoint
            let dx: CGFloat
            let dy: CGFloat
            switch corner {
            case 0: origin = CGPoint(x: frameRect.minX, y: frameRect.minY); dx = 1; dy = 1
            case 1: origin = CGPoint(x: frameRect.maxX, y: frameRect.minY); dx = -1; dy = 1
            case 2: origin = CGPoint(x: frameRect.minX, y: frameRect.maxY); dx = 1; dy = -1
            default: origin = CGPoint(x: frameRect.maxX, y: frameRect.maxY); dx = -1; dy = -1
            }
            ctx.move(to: CGPoint(x: origin.x + dx * cornerLen, y: origin.y))
            ctx.addLine(to: origin)
            ctx.addLine(to: CGPoint(x: origin.x, y: origin.y + dy * cornerLen))
            ctx.strokePath()
        }

        // Three text-line bars centred in the frame, varying widths to suggest
        // a wrapped paragraph.
        let textInset = inset + size * 0.10
        let availableWidth = size - 2 * textInset
        let lineHeight = max(2.0, size * 0.055)
        let lineSpacing = size * 0.07
        let totalHeight = lineHeight * 3 + lineSpacing * 2
        let yTop = (size + totalHeight) / 2 - lineHeight

        let lineWidths: [CGFloat] = [
            availableWidth,
            availableWidth * 0.78,
            availableWidth * 0.52,
        ]

        ctx.setFillColor(foreground)
        for (i, width) in lineWidths.enumerated() {
            let y = yTop - CGFloat(i) * (lineHeight + lineSpacing)
            let rect = CGRect(x: textInset, y: y, width: width, height: lineHeight)
            ctx.addPath(CGPath(
                roundedRect: rect,
                cornerWidth: lineHeight / 2,
                cornerHeight: lineHeight / 2,
                transform: nil
            ))
            ctx.fillPath()
        }
    }
}
