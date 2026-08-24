import CoreGraphics
import CoreText
import SwiftUI
import UIKit
import WickCalendarKit
import WickSync

// MARK: - Installed Font Model

public struct InstalledFontItem: Identifiable, Hashable, Sendable {
    public let postScriptName: String
    public let displayName: String
    public let isCustomImported: Bool
    public var id: String { postScriptName }

    public init(postScriptName: String, displayName: String, isCustomImported: Bool = false) {
        self.postScriptName = postScriptName
        self.displayName = displayName
        self.isCustomImported = isCustomImported
    }
}

// MARK: - Phone Font Manager & Custom Font Registration

@MainActor
public enum PhoneFontManager {
    private static var registeredPostScriptNames: Set<String> = []

    public static var fontsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fontsDir = docs.appendingPathComponent("Fonts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: fontsDir.path) {
            try? FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
        }
        return fontsDir
    }

    /// Reads font metadata from file without registering.
    public static func fontInfo(at url: URL) -> (postScriptName: String, displayName: String)? {
        guard let data = try? Data(contentsOf: url),
              let provider = CGDataProvider(data: data as CFData),
              let cgFont = CGFont(provider) else {
            return nil
        }
        let psName = (cgFont.postScriptName as String?) ?? url.deletingPathExtension().lastPathComponent
        let displayName = (cgFont.fullName as String?) ?? (UIFont(name: psName, size: 12)?.familyName) ?? url.deletingPathExtension().lastPathComponent
        return (psName, displayName)
    }

    /// Registers all imported custom fonts in Documents/Fonts on startup.
    public static func registerCustomFonts() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: fontsDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where ["ttf", "otf", "ttc"].contains(file.pathExtension.lowercased()) {
            _ = registerFont(at: file)
        }
        syncCalendarThemeFont()
    }

    /// Registers a font file dynamically with CoreText & UIKit if not already registered.
    public static func registerFont(at url: URL) -> (postScriptName: String, displayName: String)? {
        guard let info = fontInfo(at: url) else { return nil }
        if registeredPostScriptNames.contains(info.postScriptName) {
            return info
        }

        guard let data = try? Data(contentsOf: url),
              let provider = CGDataProvider(data: data as CFData),
              let cgFont = CGFont(provider) else {
            return info
        }

        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterGraphicsFont(cgFont, &error) {
            registeredPostScriptNames.insert(info.postScriptName)
        } else if let err = error?.takeRetainedValue() {
            let code = CFErrorGetCode(err)
            // kCTFontManagerErrorAlreadyRegistered = 105
            if code == 105 {
                registeredPostScriptNames.insert(info.postScriptName)
            }
        }

        return info
    }

    /// Imports a font file from user document picker into the app's private font folder.
    public static func importFont(from sourceURL: URL) throws -> InstalledFontItem {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let filename = sourceURL.lastPathComponent
        let dest = fontsDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)

        guard let (psName, displayName) = registerFont(at: dest) else {
            let fallbackName = sourceURL.deletingPathExtension().lastPathComponent
            return InstalledFontItem(postScriptName: fallbackName, displayName: fallbackName, isCustomImported: true)
        }

        return InstalledFontItem(postScriptName: psName, displayName: displayName, isCustomImported: true)
    }

    /// Deletes an imported custom font.
    public static func deleteCustomFont(postScriptName: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: fontsDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            if let info = fontInfo(at: file), info.postScriptName == postScriptName {
                var error: Unmanaged<CFError>?
                CTFontManagerUnregisterFontsForURL(file as CFURL, .process, &error)
                registeredPostScriptNames.remove(postScriptName)
                try? FileManager.default.removeItem(at: file)
            }
        }
        if PhoneFont.selectedFontName == postScriptName {
            PhoneFont.selectedFontName = ""
        }
    }

    /// Lists custom imported fonts and system installed fonts.
    public static func allAvailableFonts() -> (custom: [InstalledFontItem], system: [InstalledFontItem]) {
        // 1. Custom imported fonts in Documents/Fonts
        var customFonts: [InstalledFontItem] = []
        if let files = try? FileManager.default.contentsOfDirectory(at: fontsDirectory, includingPropertiesForKeys: nil) {
            for file in files where ["ttf", "otf", "ttc"].contains(file.pathExtension.lowercased()) {
                if let (psName, displayName) = registerFont(at: file) {
                    customFonts.append(InstalledFontItem(postScriptName: psName, displayName: displayName, isCustomImported: true))
                }
            }
        }

        // 2. System and pre-installed fonts
        var systemFonts: [InstalledFontItem] = []
        let customPsNames = Set(customFonts.map(\.postScriptName))
        let ignoredPrefixes = [".", "AppleColorEmoji", "AppleColorEmojiUI", "Apple SD Gothic Neo"]

        let families = UIFont.familyNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        for family in families {
            if ignoredPrefixes.contains(where: { family.hasPrefix($0) }) { continue }
            let fontNames = UIFont.fontNames(forFamilyName: family)
            guard let firstFont = fontNames.first else { continue }
            if customPsNames.contains(firstFont) { continue }

            let regularFont = fontNames.first(where: {
                let lower = $0.lowercased()
                return lower.contains("regular") || lower.contains("plain") || lower.contains("w3") || lower.contains("book")
            }) ?? firstFont

            systemFonts.append(InstalledFontItem(
                postScriptName: regularFont,
                displayName: family,
                isCustomImported: false
            ))
        }

        return (customFonts, systemFonts)
    }

    public static func syncCalendarThemeFont() {
        let font = PhoneFont.selectedFontName
        TradingCalendarTheme.fontStyle = font.isEmpty ? .default : .custom(postScriptName: font)
    }
}

// MARK: - App-Wide Unified Font Resolution (iOS)

@MainActor
public enum PhoneFont {
    public static let key = "wick.journal.fontName"

    /// The user selected font PostScript name ("" = default look).
    public static var selectedFontName: String {
        get {
            UserDefaults.standard.string(forKey: key) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            PhoneFontManager.syncCalendarThemeFont()
        }
    }

    /// Primary font for paper, journal, and serif titles.
    public static func paper(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = selectedFontName
        if !name.isEmpty {
            return .custom(name, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .serif)
    }

    /// Primary font for UI text.
    public static func ui(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        monospacedDigit: Bool = false
    ) -> Font {
        let name = selectedFontName
        if !name.isEmpty {
            return .custom(name, size: size).weight(weight)
        }
        var font = Font.system(size: size, weight: weight, design: design)
        if monospacedDigit {
            font = font.monospacedDigit()
        }
        return font
    }

    /// Preset text styles (.caption, .headline, ...).
    public static func preset(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let name = selectedFontName
        if !name.isEmpty {
            return .custom(name, size: pointSize(for: style)).weight(weight ?? .regular)
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

    /// UIFont resolution for UIKit views.
    public static func paperUIFont(_ size: CGFloat, bold: Bool = false) -> UIFont {
        let name = selectedFontName
        if !name.isEmpty, let font = UIFont(name: name, size: size) {
            return bold ? font.boldVersion() : font
        }
        return bold ? UIFont.systemFont(ofSize: size, weight: .bold) : UIFont.systemFont(ofSize: size)
    }
}

private extension UIFont {
    func boldVersion() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
