import SwiftUI
import UniformTypeIdentifiers
import UIKit
import WickSync

// MARK: - Phone Font Picker Sheet

public struct PhoneFontPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language: AppLanguage
    @AppStorage("wick.journal.fontName") private var selectedFontName = ""

    @State private var query = ""
    @State private var customFonts: [InstalledFontItem] = []
    @State private var systemFonts: [InstalledFontItem] = []
    @State private var isShowingDocumentPicker = false
    @State private var importErrorMessage: String?
    @State private var showingErrorAlert = false

    public init() {}

    private var filteredCustomFonts: [InstalledFontItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return customFonts }
        return customFonts.filter {
            $0.displayName.localizedCaseInsensitiveContains(q) ||
            $0.postScriptName.localizedCaseInsensitiveContains(q)
        }
    }

    private var filteredSystemFonts: [InstalledFontItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return systemFonts }
        return systemFonts.filter {
            $0.displayName.localizedCaseInsensitiveContains(q) ||
            $0.postScriptName.localizedCaseInsensitiveContains(q)
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search & Import Header
                VStack(spacing: 10) {
                    searchBar

                    Button {
                        isShowingDocumentPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(PhoneFont.ui(13, weight: .bold))
                            Text(language == .chinese ? "从文件导入字体 (.ttf / .otf)…" : "Import font file (.ttf / .otf)…")
                                .font(PhoneFont.paper(12.5, weight: .semibold))
                        }
                        .foregroundColor(PhoneTheme.cinnabar)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .background(PhoneTheme.cinnabarSoft)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(PhoneTheme.cinnabar.opacity(0.3), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(PhoneTheme.paperHi)
                .overlay(alignment: .bottom) {
                    Divider().background(PhoneTheme.rule)
                }

                // Font List
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // 1. Default Option
                        fontRow(
                            name: "",
                            display: L10n.string(.fontDefault, language: language),
                            isSelected: selectedFontName.isEmpty,
                            isCustom: false
                        )

                        // 2. Custom Imported Fonts Section
                        if !filteredCustomFonts.isEmpty {
                            sectionHeader(title: language == .chinese ? "已导入字体" : "Imported Fonts")
                            ForEach(filteredCustomFonts) { font in
                                fontRow(
                                    name: font.postScriptName,
                                    display: font.displayName,
                                    isSelected: selectedFontName == font.postScriptName,
                                    isCustom: true
                                )
                            }
                        }

                        // 3. System Font Families Section
                        if !filteredSystemFonts.isEmpty {
                            sectionHeader(title: language == .chinese ? "系统字体族" : "System Fonts")
                            ForEach(filteredSystemFonts) { font in
                                fontRow(
                                    name: font.postScriptName,
                                    display: font.displayName,
                                    isSelected: selectedFontName == font.postScriptName,
                                    isCustom: false
                                )
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .background(PhoneTheme.paper.ignoresSafeArea())
            .navigationTitle(L10n.string(.journalFontStyle, language: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string(.ok, language: language)) {
                        dismiss()
                    }
                    .font(PhoneFont.paper(14, weight: .bold))
                    .foregroundColor(PhoneTheme.cinnabar)
                }
            }
            .sheet(isPresented: $isShowingDocumentPicker) {
                FontDocumentPicker { result in
                    handleFontImport(result)
                }
            }
            .alert(isPresented: $showingErrorAlert) {
                Alert(
                    title: Text(language == .chinese ? "导入失败" : "Import Failed"),
                    message: Text(importErrorMessage ?? ""),
                    dismissButton: .default(Text(L10n.string(.ok, language: language)))
                )
            }
            .onAppear {
                loadFonts()
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(PhoneFont.ui(13))
                .foregroundColor(PhoneTheme.inkTertiary)

            TextField(L10n.string(.fontSearchPlaceholder, language: language), text: $query)
                .font(PhoneFont.paper(13))
                .foregroundColor(PhoneTheme.inkPrimary)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(PhoneFont.ui(13))
                        .foregroundColor(PhoneTheme.inkTertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(PhoneTheme.paper)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(PhoneTheme.rule, lineWidth: 1))
    }

    // MARK: - Section Header

    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(PhoneFont.paper(11, weight: .bold))
                .foregroundColor(PhoneTheme.inkSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Font Row

    private func fontRow(name: String, display: String, isSelected: Bool, isCustom: Bool) -> some View {
        Button {
            selectedFontName = name
            PhoneFont.selectedFontName = name
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(display)
                        .font(name.isEmpty ? .system(size: 15, weight: .medium, design: .serif) : .custom(name, size: 15))
                        .foregroundColor(PhoneTheme.inkPrimary)
                        .lineLimit(1)

                    if !name.isEmpty && name != display {
                        Text(name)
                            .font(PhoneFont.ui(10, monospacedDigit: true))
                            .foregroundColor(PhoneTheme.inkTertiary)
                    }
                }

                Spacer()

                if isCustom {
                    Button(role: .destructive) {
                        PhoneFontManager.deleteCustomFont(postScriptName: name)
                        loadFonts()
                    } label: {
                        Image(systemName: "trash")
                            .font(PhoneFont.ui(12))
                            .foregroundColor(PhoneTheme.inkTertiary)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(PhoneFont.ui(13, weight: .bold))
                        .foregroundColor(PhoneTheme.cinnabar)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? PhoneTheme.cinnabarSoft.opacity(0.4) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Loading & Import

    private func loadFonts() {
        let (c, s) = PhoneFontManager.allAvailableFonts()
        customFonts = c
        systemFonts = s
    }

    private func handleFontImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let item = try PhoneFontManager.importFont(from: url)
                loadFonts()
                selectedFontName = item.postScriptName
                PhoneFont.selectedFontName = item.postScriptName
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } catch {
                importErrorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }
}

// MARK: - UIDocumentPickerViewController Wrapper

private struct FontDocumentPicker: UIViewControllerRepresentable {
    let onPick: (Result<URL, Error>) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [
            UTType.font,
            UTType(filenameExtension: "ttf") ?? .font,
            UTType(filenameExtension: "otf") ?? .font,
            UTType(filenameExtension: "ttc") ?? .font
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (Result<URL, Error>) -> Void

        init(onPick: @escaping (Result<URL, Error>) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(.success(url))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
