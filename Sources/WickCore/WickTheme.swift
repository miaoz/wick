import AppKit
import SwiftUI
import WickCalendarKit

// MARK: - 印刷字态(字态四声部之一:宋体 = 写在纸上的内容)

@MainActor
enum WickPrintFont {
    private struct CacheKey: Hashable {
        let postScriptName: String
        let size: CGFloat
        let bold: Bool
    }

    private static var cache: [CacheKey: NSFont] = [:]

    /// Paper text face (Songti SC, or 文悦古典明朝体 when selected), optional bold.
    /// Cached so `NSFont` identity is stable across SwiftUI updates (P2):
    /// `NSFontManager.convert` otherwise returns a new instance every call
    /// and `updateNSView` keeps re-assigning the font.
    static func songti(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let selectedName = AppFont.selectedFontName
        let key = CacheKey(postScriptName: selectedName, size: size, bold: bold)
        if let cached = cache[key] { return cached }
        let font = AppFont.paperNSFont(size, bold: bold)

        // A font can be temporarily unavailable while the system font database
        // is rebuilding after an OS upgrade. Do not make that fallback sticky.
        if !selectedName.isEmpty, NSFont(name: selectedName, size: size) == nil {
            return font
        }

        cache[key] = font
        return font
    }

    static func invalidateCache() {
        cache.removeAll()
    }
}
