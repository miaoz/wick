import AppKit
import CoreGraphics

enum MenuBarIcon {
    /// Template candle silhouette for the macOS menu bar.
    /// Opaque black on transparent; the system tints it for light/dark bars.
    ///
    /// Built once, marked as a template, and never mutated afterwards.
    static let image: NSImage = {
        let pointSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: pointSize)

        for scale in [1.0, 2.0] as [CGFloat] {
            let pixelsWide = Int((pointSize.width * scale).rounded())
            let pixelsHigh = Int((pointSize.height * scale).rounded())

            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelsWide,
                pixelsHigh: pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                continue
            }

            rep.size = pointSize

            NSGraphicsContext.saveGraphicsState()
            if let context = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = context
                context.imageInterpolation = .high
                context.shouldAntialias = true
                drawCandle(in: NSRect(origin: .zero, size: pointSize))
            }
            NSGraphicsContext.restoreGraphicsState()

            image.addRepresentation(rep)
        }

        image.isTemplate = true
        return image
    }()

    private static func drawCandle(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        context.saveGState()
        context.setFillColor(NSColor.black.cgColor)

        let midX = rect.midX

        // Flame — upright teardrop
        let flame = teardropPath(
            center: CGPoint(x: midX, y: 14.0),
            width: 4.2,
            height: 5.4
        )
        context.addPath(flame)
        context.fillPath()

        // Wick
        context.fill(CGRect(x: midX - 0.5, y: 9.2, width: 1.0, height: 2.0))

        // Candle body — slightly tapered rectangle with rounded base
        let body = CGMutablePath()
        let topY: CGFloat = 9.2
        let bottomY: CGFloat = 1.4
        let topHalf: CGFloat = 3.4
        let bottomHalf: CGFloat = 3.8

        body.move(to: CGPoint(x: midX - topHalf, y: topY))
        body.addLine(to: CGPoint(x: midX + topHalf, y: topY))
        body.addLine(to: CGPoint(x: midX + bottomHalf, y: bottomY + 1.0))
        body.addQuadCurve(
            to: CGPoint(x: midX - bottomHalf, y: bottomY + 1.0),
            control: CGPoint(x: midX, y: bottomY - 0.15)
        )
        body.closeSubpath()
        context.addPath(body)
        context.fillPath()

        // Small wax drip on the right
        let drip = CGMutablePath()
        drip.move(to: CGPoint(x: midX + topHalf - 0.15, y: topY))
        drip.addQuadCurve(
            to: CGPoint(x: midX + topHalf + 0.7, y: topY - 2.6),
            control: CGPoint(x: midX + topHalf + 1.25, y: topY - 0.7)
        )
        drip.addQuadCurve(
            to: CGPoint(x: midX + topHalf - 0.7, y: topY - 0.4),
            control: CGPoint(x: midX + topHalf + 0.15, y: topY - 1.9)
        )
        drip.closeSubpath()
        context.addPath(drip)
        context.fillPath()

        context.restoreGState()
    }

    private static func teardropPath(center: CGPoint, width: CGFloat, height: CGFloat) -> CGPath {
        let halfWidth = width / 2
        let halfHeight = height / 2
        let top = CGPoint(x: center.x, y: center.y + halfHeight)
        let bottom = CGPoint(x: center.x, y: center.y - halfHeight)

        let path = CGMutablePath()
        path.move(to: top)
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: center.x - halfWidth * 1.05, y: center.y + height * 0.10),
            control2: CGPoint(x: center.x - halfWidth * 0.75, y: center.y - height * 0.32)
        )
        path.addCurve(
            to: top,
            control1: CGPoint(x: center.x + halfWidth * 0.75, y: center.y - height * 0.32),
            control2: CGPoint(x: center.x + halfWidth * 1.05, y: center.y + height * 0.10)
        )
        path.closeSubpath()
        return path
    }
}
