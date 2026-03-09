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
    end: CGPoint
) {
    context.drawLinearGradient(
        makeGradient(colors: colors, locations: locations),
        start: start,
        end: end,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

func drawRadialGradient(
    _ context: CGContext,
    colors: [NSColor],
    locations: [CGFloat]? = nil,
    startCenter: CGPoint,
    startRadius: CGFloat,
    endCenter: CGPoint,
    endRadius: CGFloat
) {
    context.drawRadialGradient(
        makeGradient(colors: colors, locations: locations),
        startCenter: startCenter,
        startRadius: startRadius,
        endCenter: endCenter,
        endRadius: endRadius,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
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

guard CommandLine.arguments.count > 1 else {
    fputs("usage: generate_icon.swift <output-png-path>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
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

let canvas = CGRect(x: 96, y: 96, width: 832, height: 832)
let roundedCanvas = CGPath(
    roundedRect: canvas,
    cornerWidth: 188,
    cornerHeight: 188,
    transform: nil
)

context.saveGState()
context.addPath(roundedCanvas)
context.clip()

drawLinearGradient(
    context,
    colors: [
        NSColor(hex: 0x2B160F),
        NSColor(hex: 0x5B2A17),
        NSColor(hex: 0x7B3D1B)
    ],
    locations: [0.0, 0.55, 1.0],
    start: CGPoint(x: canvas.minX, y: canvas.maxY),
    end: CGPoint(x: canvas.maxX, y: canvas.minY)
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

context.restoreGState()

context.saveGState()
context.setLineWidth(4)
context.addPath(roundedCanvas)
context.setStrokeColor(NSColor(hex: 0xFFD6A4, alpha: 0.18).cgColor)
context.strokePath()
context.restoreGState()

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

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to create png data\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL)
print(outputURL.path)
