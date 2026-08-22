import AppKit
import SwiftUI

/// The journal controls hosted by the native window titlebar accessory.
/// AppKit owns the titlebar geometry and traffic lights; this view only lays
/// out Wick's controls inside the titlebar row.
struct JournalTopBarView: View {
    static let preferredHeight: CGFloat = 48

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @ObservedObject private var calendarWindow = TradingCalendarWindowController.shared
    @Environment(\.colorScheme) private var colorScheme

    let columnModeOverride: Int?

    init(columnModeOverride: Int? = nil) {
        self.columnModeOverride = columnModeOverride
    }

    private var columnMode: Int {
        columnModeOverride ?? settings.journalColumnMode
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { _ in
            let palette = DayArcEngine.palette(at: DayArcEngine.currentDate(), scheme: colorScheme)
            content(palette: palette)
        }
        .preferredColorScheme(settings.preferredColorScheme)
    }

    private func content(palette: WickPalette) -> some View {
        HStack(spacing: 10) {
            InkIconButton(
                systemName: columnModeIcon,
                help: L10n.string(.journalCycleColumns, language: settings.language)
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    settings.journalColumnMode = (settings.journalColumnMode + 1) % 3
                }
            }

            journalTitle(palette: palette)

            Text(selectedDayStamp)
                .font(AppFont.ui(11))
                .foregroundStyle(palette.textTertiary.color)
                .lineLimit(1)

            Spacer(minLength: 8)

            searchField

            InkIconButton(
                systemName: "square.and.pencil",
                help: L10n.string(.journalNewEntry, language: settings.language)
            ) {
                _ = store.openOrCreateToday()
            }

            if settings.physicalCalendarEnabled {
                InkIconButton(
                    systemName: "calendar",
                    help: L10n.string(.tradingCalendar, language: settings.language),
                    isOn: calendarWindow.isPresented
                ) {
                    calendarWindow.toggleCalendar()
                }
            } else {
                InkIconButton(
                    systemName: "sidebar.right",
                    help: L10n.string(.inspectorToggle, language: settings.language),
                    isOn: settings.journalInspectorVisible
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        settings.journalInspectorVisible.toggle()
                    }
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, minHeight: Self.preferredHeight, maxHeight: Self.preferredHeight)
        // Keep the accessory transparent so the themed NSWindow background is
        // the only fill behind both it and the traffic lights.
        .background(Color.clear)
        .windowDragBackground()
    }

    private var columnModeIcon: String {
        switch columnMode {
        case 1: return "rectangle.split.2x1"
        case 2: return "rectangle"
        default: return "sidebar.left"
        }
    }

    private var selectedDayStamp: String {
        let date: Date
        if let id = store.selectedEntryID,
           let entry = store.entries.first(where: { $0.id == id })
        {
            date = entry.date
        } else {
            date = Date()
        }
        let day = date.formatted(.dateTime.month().day().locale(settings.locale))
        let weekday = date.formatted(.dateTime.weekday(.wide).locale(settings.locale))
        return "\(day) · \(weekday)"
    }

    private func journalTitle(palette: WickPalette) -> some View {
        Text(
            store.activeJournal?.name
                ?? L10n.string(.journalLibraryDefaultName, language: settings.language)
        )
        .font(AppFont.ui(13, weight: .semibold))
        .foregroundStyle(palette.textPrimary.color)
        .lineLimit(1)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(AppFont.ui(11))
                .foregroundStyle(.secondary)
            TextField(
                L10n.string(.journalSearchPlaceholder, language: settings.language),
                text: $store.searchText
            )
            .textFieldStyle(.plain)
            .font(AppFont.ui(12))

            if !store.searchText.isEmpty {
                Button {
                    store.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(width: 180, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }
}
