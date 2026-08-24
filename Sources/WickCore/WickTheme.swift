import AppKit
import SwiftUI
import WickCalendarKit

// MARK: - 印刷字态(字态四声部之一:宋体 = 写在纸上的内容)

@MainActor
enum WickPrintFont {
    private static var cache: [String: NSFont] = [:]

    /// Paper text face (Songti SC, or 文悦古典明朝体 when selected), optional bold.
    /// Cached so `NSFont` identity is stable across SwiftUI updates (P2):
    /// `NSFontManager.convert` otherwise returns a new instance every call
    /// and `updateNSView` keeps re-assigning the font.
    static func songti(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let key = "\(size)/\(bold ? "b" : "r")"
        if let cached = cache[key] { return cached }
        let font = AppFont.paperNSFont(size, bold: bold)
        cache[key] = font
        return font
    }
}
