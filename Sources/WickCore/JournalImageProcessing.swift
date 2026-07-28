import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Resizes and re-encodes journal images so long-term libraries stay small.
enum JournalImageProcessing {
    /// Longest edge in pixels after import.
    static let maxDimension: CGFloat = 2048
    /// JPEG quality for photos without alpha.
    static let jpegQuality: CGFloat = 0.82

    struct ProcessedImage {
        let data: Data
        let fileExtension: String
    }

    static func process(data: Data, preferredExtension: String = "png") -> ProcessedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return processViaNSImage(data: data, preferredExtension: preferredExtension)
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let longest = max(width, height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let targetSize = CGSize(
            width: max(1, (width * scale).rounded()),
            height: max(1, (height * scale).rounded())
        )

        let hasAlpha = cgImage.alphaInfo != .none
            && cgImage.alphaInfo != .noneSkipLast
            && cgImage.alphaInfo != .noneSkipFirst

        let drawn: CGImage
        if scale < 1 {
            guard let resized = resize(cgImage, to: targetSize) else {
                return nil
            }
            drawn = resized
        } else {
            drawn = cgImage
        }

        if hasAlpha {
            if let png = encode(drawn, type: UTType.png.identifier as CFString, quality: nil) {
                return ProcessedImage(data: png, fileExtension: "png")
            }
        } else {
            if let jpeg = encode(drawn, type: UTType.jpeg.identifier as CFString, quality: jpegQuality) {
                return ProcessedImage(data: jpeg, fileExtension: "jpg")
            }
        }

        return processViaNSImage(data: data, preferredExtension: preferredExtension)
    }

    static func process(nsImage: NSImage) -> ProcessedImage? {
        guard let tiff = nsImage.tiffRepresentation else {
            return nil
        }
        return process(data: tiff, preferredExtension: "png")
    }

    static func process(fileURL: URL) -> ProcessedImage? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        let ext = fileURL.pathExtension.isEmpty ? "png" : fileURL.pathExtension
        return process(data: data, preferredExtension: ext)
    }

    /// Thumbnail for UI; does not write to disk.
    static func thumbnail(from image: NSImage, maxPixel: CGFloat = 320) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return image
        }
        let longest = max(size.width, size.height)
        if longest <= maxPixel {
            return image
        }
        let scale = maxPixel / longest
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let thumb = NSImage(size: target)
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .medium
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        thumb.unlockFocus()
        return thumb
    }

    // MARK: - Private

    private static func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else {
            // Fallback with premultiplied last alpha.
            guard let fallback = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }
            fallback.interpolationQuality = .high
            fallback.draw(image, in: CGRect(origin: .zero, size: size))
            return fallback.makeImage()
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    private static func encode(
        _ image: CGImage,
        type: CFString,
        quality: CGFloat?
    ) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else {
            return nil
        }
        var props: [CFString: Any] = [:]
        if let quality {
            props[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    private static func processViaNSImage(data: Data, preferredExtension: String) -> ProcessedImage? {
        guard let image = NSImage(data: data) else {
            return nil
        }
        let size = image.size
        let longest = max(size.width, size.height)
        let working: NSImage
        if longest > maxDimension {
            let scale = maxDimension / longest
            let target = NSSize(width: size.width * scale, height: size.height * scale)
            let resized = NSImage(size: target)
            resized.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(
                in: NSRect(origin: .zero, size: target),
                from: NSRect(origin: .zero, size: size),
                operation: .copy,
                fraction: 1
            )
            resized.unlockFocus()
            working = resized
        } else {
            working = image
        }

        guard let tiff = working.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }

        let hasAlpha = rep.hasAlpha
        if hasAlpha, let png = rep.representation(using: .png, properties: [:]) {
            return ProcessedImage(data: png, fileExtension: "png")
        }
        if let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality]) {
            return ProcessedImage(data: jpeg, fileExtension: "jpg")
        }
        if let png = rep.representation(using: .png, properties: [:]) {
            return ProcessedImage(data: png, fileExtension: "png")
        }
        _ = preferredExtension
        return nil
    }
}

/// In-memory thumbnail cache for journal image grids.
@MainActor
final class JournalThumbnailCache {
    static let shared = JournalThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 200
    }

    func thumbnail(filename: String, url: URL, maxPixel: CGFloat = 320) -> NSImage? {
        let key = "\(filename)|\(Int(maxPixel))" as NSString
        if let hit = cache.object(forKey: key) {
            return hit
        }
        guard let full = NSImage(contentsOf: url) else {
            return nil
        }
        let thumb = JournalImageProcessing.thumbnail(from: full, maxPixel: maxPixel)
        cache.setObject(thumb, forKey: key)
        return thumb
    }

    func invalidate(filename: String) {
        // NSCache has no key prefix removal; clear all on mutation of known files.
        cache.removeAllObjects()
        _ = filename
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
