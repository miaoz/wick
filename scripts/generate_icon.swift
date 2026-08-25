import AppKit
import CoreGraphics
import Foundation

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

func makeGradient(colors: [NSColor], locations: [CGFloat]? = nil) -> CGGradient {
    let cgColors = colors.map(\.cgColor) as CFArray
    return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations)!
}

func drawLinearGradient(
    _ context: CGContext,
    colors: [NSColor],
    locations: [CGFloat]? = nil,
    start: CGPoint,
    end: CGPoint,
    extend: Bool = false
) {
    // Default: do not extend past the gradient segment. Extending used to
    // flood the whole icon (and its transparent corners) with solid color.
    let options: CGGradientDrawingOptions = extend
        ? [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        : []
    context.drawLinearGradient(
        makeGradient(colors: colors, locations: locations),
        start: start,
        end: end,
        options: options
    )
}

func drawRadialGradient(
    _ context: CGContext,
    colors: [NSColor],
    locations: [CGFloat]? = nil,
    startCenter: CGPoint,
    startRadius: CGFloat,
    endCenter: CGPoint,
    endRadius: CGFloat,
    extend: Bool = false
) {
    let options: CGGradientDrawingOptions = extend
        ? [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        : []
    context.drawRadialGradient(
        makeGradient(colors: colors, locations: locations),
        startCenter: startCenter,
        startRadius: startRadius,
        endCenter: endCenter,
        endRadius: endRadius,
        options: options
    )
}

func teardropPath(center: CGPoint, width: CGFloat, height: CGFloat) -> CGPath {
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

/// macOS app-icon silhouette: inset rounded rect matching system icons
/// (transparent outside, continuous-looking corners ~22.5% of the shape side).
func macOSIconMaskPath(canvasSize: CGFloat) -> (rect: CGRect, path: CGPath) {
    // System icons keep ~9–10% outer margin so Dock/Launchpad can apply shadows.
    let margin = canvasSize * (96.0 / 1024.0)
    let side = canvasSize - margin * 2
    let rect = CGRect(x: margin, y: margin, width: side, height: side)
    // Apple-style corner radius ≈ 22.6% of the icon shape edge.
    let radius = side * (188.0 / 832.0)
    let path = CGPath(
        roundedRect: rect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )
    return (rect, path)
}

/// Web/Favicon app-icon silhouette: edge-to-edge rounded rect (no outer transparent margin, fills entire square).
func webIconMaskPath(canvasSize: CGFloat) -> (rect: CGRect, path: CGPath) {
    let rect = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
    // Continuous Apple-style corner radius ≈ 22.4% of the icon shape edge.
    let radius = canvasSize * (224.0 / 1024.0)
    let path = CGPath(
        roundedRect: rect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )
    return (rect, path)
}

/// Zero-out alpha outside the icon mask so Launchpad never shows square corners.
func applyIconMask(to bitmap: NSBitmapImageRep, path: CGPath, size: Int) {
    guard let maskBitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return
    }

    maskBitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: maskBitmap)
    guard let maskContext = NSGraphicsContext.current?.cgContext else {
        NSGraphicsContext.restoreGraphicsState()
        return
    }

    maskContext.setAllowsAntialiasing(true)
    maskContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
    maskContext.setFillColor(NSColor.white.cgColor)
    maskContext.addPath(path)
    maskContext.fillPath()
    NSGraphicsContext.restoreGraphicsState()

    guard let iconData = bitmap.bitmapData, let maskData = maskBitmap.bitmapData else {
        return
    }

    let pixelCount = size * size
    for i in 0..<pixelCount {
        let offset = i * 4
        let maskAlpha = Int(maskData[offset + 3])
        if maskAlpha == 255 {
            continue
        }
        if maskAlpha == 0 {
            iconData[offset] = 0
            iconData[offset + 1] = 0
            iconData[offset + 2] = 0
            iconData[offset + 3] = 0
            continue
        }
        // Premultiplied-style fade at the anti-aliased edge.
        iconData[offset] = UInt8((Int(iconData[offset]) * maskAlpha) / 255)
        iconData[offset + 1] = UInt8((Int(iconData[offset + 1]) * maskAlpha) / 255)
        iconData[offset + 2] = UInt8((Int(iconData[offset + 2]) * maskAlpha) / 255)
        iconData[offset + 3] = UInt8((Int(iconData[offset + 3]) * maskAlpha) / 255)
    }
}

guard CommandLine.arguments.count > 1 else {
    fputs("usage: generate_icon.swift <output-png-path> [--ios] [--web]\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
/// iOS icons are full-bleed (the system applies its own mask).
let isIOS = CommandLine.arguments.contains("--ios")
/// Web/Favicon icons are edge-to-edge with continuous rounded corners (no outer transparent padding).
let isWeb = CommandLine.arguments.contains("--web")
let size = 1024

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("failed to allocate bitmap\n", stderr)
    exit(1)
}

bitmap.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("failed to create graphics context\n", stderr)
    exit(1)
}

context.setAllowsAntialiasing(true)
context.interpolationQuality = .high
context.clear(CGRect(x: 0, y: 0, width: size, height: size))

let iconMask = isWeb
    ? webIconMaskPath(canvasSize: CGFloat(size))
    : macOSIconMaskPath(canvasSize: CGFloat(size))
let canvas = isWeb
    ? CGRect(x: 96, y: 96, width: 832, height: 832)
    : iconMask.rect
let roundedCanvas = iconMask.path

// Clip every paint operation to the icon silhouette so unclipped gradients
// cannot fill the transparent corners.
context.saveGState()
if isIOS {
    // Full bleed: artwork expands to cover the whole canvas (iOS masks corners dynamically).
    let scale = CGFloat(size) / 832.0
    context.translateBy(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -CGFloat(size) / 2, y: -CGFloat(size) / 2)
    context.clip(to: CGRect(x: 0, y: 0, width: size, height: size))
} else if isWeb {
    // Edge-to-edge rounded rect: artwork expands to fill the 1024 canvas with rounded corners.
    context.addPath(roundedCanvas)
    context.clip()

    let scale = CGFloat(size) / 832.0
    context.translateBy(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -CGFloat(size) / 2, y: -CGFloat(size) / 2)
} else {
    context.addPath(roundedCanvas)
    context.clip()
}

drawLinearGradient(
    context,
    colors: [
        NSColor(hex: 0x2B160F),
        NSColor(hex: 0x5B2A17),
        NSColor(hex: 0x7B3D1B)
    ],
    locations: [0.0, 0.55, 1.0],
    start: CGPoint(x: canvas.minX, y: canvas.maxY),
    end: CGPoint(x: canvas.maxX, y: canvas.minY),
    extend: true
)

drawRadialGradient(
    context,
    colors: [
        NSColor(hex: 0xFFCF7A, alpha: 0.46),
        NSColor(hex: 0xFF9F42, alpha: 0.08),
        NSColor(hex: 0xFF9F42, alpha: 0.0)
    ],
    locations: [0.0, 0.38, 1.0],
    startCenter: CGPoint(x: 512, y: 688),
    startRadius: 6,
    endCenter: CGPoint(x: 512, y: 688),
    endRadius: 330
)

drawRadialGradient(
    context,
    colors: [
        NSColor(hex: 0xFFF2D2, alpha: 0.16),
        NSColor(hex: 0xFFF2D2, alpha: 0.0)
    ],
    startCenter: CGPoint(x: 512, y: 432),
    startRadius: 20,
    endCenter: CGPoint(x: 512, y: 432),
    endRadius: 280
)

drawLinearGradient(
    context,
    colors: [
        NSColor(hex: 0xFFFFFF, alpha: 0.14),
        NSColor(hex: 0xFFFFFF, alpha: 0.0)
    ],
    start: CGPoint(x: canvas.minX, y: canvas.maxY - 30),
    end: CGPoint(x: canvas.minX, y: canvas.midY)
)

context.setLineWidth(4)
context.addPath(roundedCanvas)
context.setStrokeColor(NSColor(hex: 0xFFD6A4, alpha: 0.18).cgColor)
if !isIOS && !isWeb {
    // Squircle rim highlight for macOS desktop icon
    context.strokePath()
}

let haloCenter = CGPoint(x: 512, y: 648)
drawRadialGradient(
    context,
    colors: [
        NSColor(hex: 0xFFD46A, alpha: 0.72),
        NSColor(hex: 0xFFAD39, alpha: 0.20),
        NSColor(hex: 0xFFAD39, alpha: 0.0)
    ],
    locations: [0.0, 0.34, 1.0],
    startCenter: haloCenter,
    startRadius: 4,
    endCenter: haloCenter,
    endRadius: 205
)

let candleShadowRect = CGRect(x: 358, y: 220, width: 308, height: 68)
context.saveGState()
context.setShadow(offset: .zero, blur: 34, color: NSColor(hex: 0x160B07, alpha: 0.50).cgColor)
context.setFillColor(NSColor(hex: 0x3C1E13, alpha: 0.64).cgColor)
context.fillEllipse(in: candleShadowRect)
context.restoreGState()

let candleRect = CGRect(x: 394, y: 266, width: 236, height: 320)
let candlePath = CGPath(
    roundedRect: candleRect,
    cornerWidth: 76,
    cornerHeight: 76,
    transform: nil
)

context.saveGState()
context.addPath(candlePath)
context.clip()

drawLinearGradient(
    context,
    colors: [
        NSColor(hex: 0xFFF8EE),
        NSColor(hex: 0xF6E9D7),
        NSColor(hex: 0xE7D4BF)
    ],
    locations: [0.0, 0.58, 1.0],
    start: CGPoint(x: candleRect.minX, y: candleRect.maxY),
    end: CGPoint(x: candleRect.maxX, y: candleRect.minY)
)

let leftHighlight = CGRect(x: candleRect.minX + 20, y: candleRect.minY + 40, width: 58, height: candleRect.height - 60)
context.setFillColor(NSColor(hex: 0xFFFFFF, alpha: 0.24).cgColor)
context.fillEllipse(in: leftHighlight)

let waxDrips: [CGRect] = [
    CGRect(x: 426, y: 452, width: 42, height: 104),
    CGRect(x: 486, y: 428, width: 54, height: 132),
    CGRect(x: 558, y: 448, width: 40, height: 92)
]
context.setFillColor(NSColor(hex: 0xEEDFCC, alpha: 0.92).cgColor)
for drip in waxDrips {
    context.fillEllipse(in: drip)
}

let lowerShade = CGRect(x: candleRect.minX - 12, y: candleRect.minY - 12, width: candleRect.width + 24, height: 126)
drawLinearGradient(
    context,
    colors: [
        NSColor(hex: 0xDABFA7, alpha: 0.0),
        NSColor(hex: 0xD0B398, alpha: 0.28)
    ],
    locations: [0.0, 1.0],
    start: CGPoint(x: lowerShade.midX, y: lowerShade.maxY),
    end: CGPoint(x: lowerShade.midX, y: lowerShade.minY)
)

context.restoreGState()

context.saveGState()
context.addPath(candlePath)
context.setLineWidth(3)
context.setStrokeColor(NSColor(hex: 0xFFFDF8, alpha: 0.34).cgColor)
context.strokePath()
context.restoreGState()

let rimRect = CGRect(x: 404, y: 548, width: 216, height: 58)
context.saveGState()
context.addEllipse(in: rimRect)
context.clip()
drawLinearGradient(
    context,
    colors: [
        NSColor(hex: 0xF6EAD9),
        NSColor(hex: 0xE5D3BD)
    ],
    start: CGPoint(x: rimRect.midX, y: rimRect.maxY),
    end: CGPoint(x: rimRect.midX, y: rimRect.minY)
)
context.setFillColor(NSColor(hex: 0xF5E7D7, alpha: 0.88).cgColor)
context.fillEllipse(in: rimRect)
context.restoreGState()
context.setStrokeColor(NSColor(hex: 0xFFFFFF, alpha: 0.25).cgColor)
context.setLineWidth(2.5)
context.strokeEllipse(in: rimRect)

let wickRect = CGRect(x: 506, y: 600, width: 12, height: 48)
let wickPath = CGPath(roundedRect: wickRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
context.saveGState()
context.addPath(wickPath)
context.setFillColor(NSColor(hex: 0x3A251B).cgColor)
context.fillPath()
context.restoreGState()

let outerFlame = teardropPath(center: CGPoint(x: 512, y: 714), width: 154, height: 214)
context.saveGState()
context.addPath(outerFlame)
context.clip()
drawLinearGradient(
    context,
    colors: [
        NSColor(hex: 0xFFF3A8),
        NSColor(hex: 0xFFBE4D),
        NSColor(hex: 0xFF7C19)
    ],
    locations: [0.0, 0.56, 1.0],
    start: CGPoint(x: 512, y: 834),
    end: CGPoint(x: 512, y: 600)
)
context.restoreGState()

context.saveGState()
context.setShadow(offset: .zero, blur: 28, color: NSColor(hex: 0xFFB552, alpha: 0.44).cgColor)
context.addPath(outerFlame)
context.setLineWidth(3)
context.setStrokeColor(NSColor(hex: 0xFFF7C4, alpha: 0.30).cgColor)
context.strokePath()
context.restoreGState()

let innerFlame = teardropPath(center: CGPoint(x: 512, y: 714), width: 84, height: 128)
context.saveGState()
context.addPath(innerFlame)
context.clip()
drawLinearGradient(
    context,
    colors: [
        NSColor(hex: 0xFFFCE0),
        NSColor(hex: 0xFFE48B),
        NSColor(hex: 0xFFB234)
    ],
    locations: [0.0, 0.52, 1.0],
    start: CGPoint(x: 512, y: 788),
    end: CGPoint(x: 512, y: 648)
)
context.restoreGState()

let coreFlame = teardropPath(center: CGPoint(x: 512, y: 715), width: 38, height: 64)
context.saveGState()
context.addPath(coreFlame)
context.setFillColor(NSColor(hex: 0xFFFDF0, alpha: 0.96).cgColor)
context.fillPath()
context.restoreGState()

let lightPoolRect = CGRect(x: 352, y: 230, width: 320, height: 54)
drawRadialGradient(
    context,
    colors: [
        NSColor(hex: 0xFFCF76, alpha: 0.42),
        NSColor(hex: 0xFFCF76, alpha: 0.0)
    ],
    startCenter: CGPoint(x: lightPoolRect.midX, y: lightPoolRect.midY),
    startRadius: 8,
    endCenter: CGPoint(x: lightPoolRect.midX, y: lightPoolRect.midY),
    endRadius: 170
)

context.restoreGState()

if isWeb {
    // Edge-to-edge rounded rect highlight
    context.saveGState()
    context.setLineWidth(4)
    context.addPath(roundedCanvas)
    context.setStrokeColor(NSColor(hex: 0xFFD6A4, alpha: 0.20).cgColor)
    context.strokePath()
    context.restoreGState()
}

NSGraphicsContext.restoreGraphicsState()

if isIOS {
    // Full-bleed artwork must be fully opaque (no alpha at the corners).
    if let pixels = bitmap.bitmapData {
        for i in 0..<(size * size) {
            pixels[i * 4 + 3] = 255
        }
    }
} else {
    // Belt-and-suspenders: force transparent corners even if a draw call escapes the clip.
    applyIconMask(to: bitmap, path: roundedCanvas, size: size)
}

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to create png data\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL)
print(outputURL.path)
