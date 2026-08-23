import AppKit
import SwiftUI

/// Central typeface resolution for the 秉烛 paper UI — the single source every
/// font in the app routes through. Paper text (journal, settings captions) uses
/// `paper`/`paperNSFont`, all remaining UI text uses `ui`, preset styles use
/// `preset`. When the user picks an installed font (`AppSettings.journalFontName`),
/// every one of these resolves to that face; an empty name keeps the shipped
/// Songti/system look. A chosen face that lacks a needed glyph falls back to the
/// system font per glyph (CoreText handles this).
@MainActor
enum AppFont {
    /// PostScript name of 文悦古典明朝体 — kept only to migrate the pre-picker
    /// setting; the font is no longer bundled, so it must be installed by the user.
    static let classicalMingName = "WenYue_GuDianMingChaoTi_JRFC"

    /// The installed-font PostScript name the user chose ("" = default look).
    static var selectedFontName: String {
        AppSettings.shared.journalFontName
    }

    /// SwiftUI font for journal/settings paper text.
    static func paper(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(selectedFontName.isEmpty ? "Songti SC" : selectedFontName, size: size)
            .weight(weight)
    }

    /// SwiftUI font for all remaining UI text. Without a chosen font this
    /// reproduces the exact `.system(size:weight:design:)` call the view used;
    /// a chosen font overrides the family (design is dropped — a face has no
    /// such variants).
    static func ui(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        monospacedDigit: Bool = false
    ) -> Font {
        if !selectedFontName.isEmpty {
            return .custom(selectedFontName, size: size).weight(weight)
        }
        var font = Font.system(size: size, weight: weight, design: design)
        if monospacedDigit {
            font = font.monospacedDigit()
        }
        return font
    }

    /// SwiftUI preset text style (`.caption`, `.headline`, …). Default mode
    /// returns the exact preset so nothing shifts; a chosen font maps the style
    /// to its point size.
    static func preset(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        if !selectedFontName.isEmpty {
            return .custom(selectedFontName, size: pointSize(for: style))
                .weight(weight ?? .regular)
        }
        return Font.system(style, weight: weight)
    }

    private static func pointSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .caption: return 12
        case .caption2: return 11
        case .callout: return 16
        case .headline: return 17
        case .footnote: return 13
        case .body: return 17
        case .subheadline: return 15
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .largeTitle: return 34
        @unknown default: return 17
        }
    }

    /// AppKit font for the journal editor (`IMESafeTextViews`). Most chosen
    /// faces have a single weight, so bold is synthesized by the font manager.
    static func paperNSFont(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let name = selectedFontName.isEmpty ? "Songti SC" : selectedFontName
        let base = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
        return bold ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) : base
    }

    /// Computes the adaptive extra line spacing (`lineSpacing` in pt) for body text.
    ///
    /// CJK fonts, Latin fonts, and historical/classical reprint faces carry wildly
    /// different intrinsic vertical metrics (e.g. Songti SC has a 1.40x raw height,
    /// while WenYue Classical Ming has a 1.00x height with 0 leading).
    ///
    /// This resolves a harmonious target line height (~1.55x font size) across all
    /// faces and languages while preserving a minimum 2.5pt breathing room for faces
    /// that already bundle generous metrics.
    static func adaptiveLineSpacing(
        for font: NSFont,
        targetMultiplier: CGFloat = 1.55,
        minSpacing: CGFloat = 2.5
    ) -> CGFloat {
        let natural = font.ascender - font.descender + font.leading
        let target = font.pointSize * targetMultiplier
        return max(minSpacing, ceil((target - natural) * 2) / 2)
    }

    /// Convenience resolver for paper text line spacing at a given point size.
    static func paperLineSpacing(_ size: CGFloat) -> CGFloat {
        adaptiveLineSpacing(for: paperNSFont(size))
    }

    // MARK: - Installed fonts

    /// One entry per installed font family (regular weight), so the picker shows
    /// families rather than every weight/style of each face.
    struct InstalledFont: Identifiable, Hashable {
        let postScriptName: String
        let displayName: String
        var id: String { postScriptName }
    }

    /// Lists the font families installed on this machine, one (PostScript name,
    /// family name) pair each.
    static func installedFonts() -> [InstalledFont] {
        let manager = NSFontManager.shared
        var result: [InstalledFont] = []
        for family in manager.availableFontFamilies {
            guard let members = manager.availableMembers(ofFontFamily: family), !members.isEmpty else {
                continue
            }
            // Prefer the regular-weight member (AppKit weight 5); fall back to the first.
            // Each member is [PostScriptName, styleName, weight, traits].
            let chosen = members.first { member in
                member.count > 2 && (member[2] as? NSNumber)?.intValue == 5
            } ?? members.first
            guard let chosen, let postScriptName = chosen.first as? String else {
                continue
            }
            result.append(InstalledFont(postScriptName: postScriptName, displayName: family))
        }
        return result.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}
