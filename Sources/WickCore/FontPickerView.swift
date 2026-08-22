import AppKit
import SwiftUI

/// Settings row for the 字体风格 section: shows the current choice and opens the
/// searchable `FontPickerView`. Selecting a font (or "default") applies it app-wide
/// live — `AppSettings` is an `ObservableObject`, so the panel re-renders itself.
@MainActor
struct FontPickerSettingRow: View {
    @EnvironmentObject private var settings: AppSettings
    let theme: PanelTheme
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 8) {
                Text(currentDisplay)
                    .font(AppFont.ui(12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(L10n.string(.chooseFont, language: settings.language))
                    .font(AppFont.ui(12, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.selectionAccent)
                Image(systemName: "chevron.right")
                    .font(AppFont.ui(9, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(theme.controlBackground.opacity(0.45))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(theme.palette.divider.color.opacity(0.8), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker, arrowEdge: .top) {
            FontPickerView(theme: theme)
                .environmentObject(settings)
        }
    }

    private var currentDisplay: String {
        if settings.journalFontName.isEmpty {
            return L10n.string(.fontDefault, language: settings.language)
        }
        return NSFont(name: settings.journalFontName, size: 12)?.familyName
            ?? settings.journalFontName
    }
}

/// 秉烛-style searchable list of installed font families. The first row clears
/// the choice (default system/Songti look); every other row previews itself in
/// its own face. Filtering matches the family or PostScript name.
@MainActor
struct FontPickerView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let theme: PanelTheme

    @State private var query = ""
    private let fonts: [AppFont.InstalledFont]

    init(theme: PanelTheme) {
        self.theme = theme
        fonts = AppFont.installedFonts()
    }

    private var filteredFonts: [AppFont.InstalledFont] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return fonts }
        return fonts.filter {
            $0.displayName.localizedCaseInsensitiveContains(q)
                || $0.postScriptName.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            Rectangle()
                .fill(theme.palette.divider.color.opacity(0.6))
                .frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 0) {
                    row(
                        name: "",
                        display: L10n.string(.fontDefault, language: settings.language),
                        isSelected: settings.journalFontName.isEmpty
                    )
                    ForEach(filteredFonts) { font in
                        row(
                            name: font.postScriptName,
                            display: font.displayName,
                            isSelected: settings.journalFontName == font.postScriptName
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 280, height: 340)
        .background(theme.palette.columnPaper.color)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(AppFont.ui(10, weight: .medium))
                .foregroundStyle(theme.tertiaryText)
            TextField(L10n.string(.fontSearchPlaceholder, language: settings.language), text: $query)
                .textFieldStyle(.plain)
                .font(AppFont.ui(12))
                .foregroundStyle(theme.primaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(theme.controlBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(theme.palette.divider.color.opacity(0.7), lineWidth: 0.8)
        }
    }

    private func row(name: String, display: String, isSelected: Bool) -> some View {
        Button {
            settings.journalFontName = name
            dismiss()
        } label: {
            HStack(spacing: 8) {
                // Preview the row in its own face; the "default" row previews in
                // the currently chosen font (or system when none is set).
                Text(display)
                    .font(name.isEmpty ? AppFont.ui(13) : .custom(name, size: 13))
                    .foregroundStyle(isSelected ? theme.selectionAccent : theme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AppFont.ui(10, weight: .bold))
                        .foregroundStyle(theme.selectionAccent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(isSelected ? theme.selectionBackground.opacity(0.5) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
