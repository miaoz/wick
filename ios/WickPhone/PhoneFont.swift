import CoreText
import SwiftUI
import UIKit
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
    public static var fontsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fontsDir = docs.appendingPathComponent("Fonts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: fontsDir.path) {
            try? FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
        }
        return fontsDir
    }

    /// Registers all imported custom fonts in Documents/Fonts on startup.
    public static func registerCustomFonts() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: fontsDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where ["ttf", "otf", "ttc"].contains(file.pathExtension.lowercased()) {
            _ = registerFont(at: file)
        }
    }

    /// Registers a font file dynamically with CoreText.
    public static func registerFont(at url: URL) -> String? {
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)

        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first else {
            return nil
        }
        let postScriptName = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
        return postScriptName
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

        let psName = registerFont(at: dest) ?? sourceURL.deletingPathExtension().lastPathComponent
        let familyName = (UIFont(name: psName, size: 12)?.familyName) ?? sourceURL.deletingPathExtension().lastPathComponent

        return InstalledFontItem(postScriptName: psName, displayName: familyName, isCustomImported: true)
    }

    /// Deletes an imported custom font.
    public static func deleteCustomFont(postScriptName: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: fontsDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor],
               let first = descriptors.first,
               let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String,
               name == postScriptName {
                var error: Unmanaged<CFError>?
                CTFontManagerUnregisterFontsForURL(file as CFURL, .process, &error)
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
                if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor],
                   let first = descriptors.first,
                   let psName = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String {
                    let familyName = (UIFont(name: psName, size: 12)?.familyName) ?? file.deletingPathExtension().lastPathComponent
                    customFonts.append(InstalledFontItem(postScriptName: psName, displayName: familyName, isCustomImported: true))
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
