import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WickCalendarKit
import WickSync
import WickTrading

// MARK: - Editor

/// Right-hand journal editor: a continuous date timeline (newest first).
/// - Day mode: every journal day is a scrollable section (full day chrome).
/// - Item-scoped mode (tag / search filter): matching items only, grouped by day,
///   still a continuous scrollable timeline — not a single selected day/item.
struct JournalEditorPane: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.wickPalette) private var palette
    @ObservedObject private var positionCoordinator = ExchangePositionCoordinator.shared

    /// Per-entry drafts so multi-day editing survives LazyVStack recycling.
    @State private var drafts: [UUID: JournalEntry] = [:]
    @State private var saveTasks: [UUID: Task<Void, Never>] = [:]
    /// Entries whose draft differs from the store (uncommitted typing). This is
    /// the real dirty set — `saveTasks` only tracks pending debounced saves.
    @State private var dirtyEntryIDs: Set<UUID> = []
    @State private var showDeleteDayConfirm = false
    @State private var showDeleteItemConfirm = false
    @State private var pendingDeleteDayID: UUID?
    @State private var pendingDeleteItem: JournalItemRef?
    @State private var datePickerEntryID: UUID?
    @State private var imageImportTarget: JournalItemRef?
    @State private var showImageImporter = false
    @State private var pendingScrollID: String?
    /// Only this item mounts AppKit text views (P1). Nil = all items are `Text`.
    @State private var editingItemID: UUID?
    @State private var editingFocus: ItemEditorFocus = .body

    private var isItemScoped: Bool { store.isItemScoped }

    var body: some View {
        Group {
            if isItemScoped {
                if store.filteredTimelineItems.isEmpty {
                    emptyFilter
                } else {
                    timelineChrome
                }
            } else if store.filteredEntries.isEmpty {
                noSelection
            } else {
                timelineChrome
            }
        }
        .background(palette.editorCanvas.color)
        .onAppear {
            queueScrollToSelection()
        }
        .onChange(of: store.selection) { _ in
            seedDraftsForVisibleTimeline()
            queueScrollToSelection()
        }
        .onChange(of: store.selectedTagFilter) { _ in
            seedDraftsForVisibleTimeline()
            queueScrollToSelection()
        }
        .onChange(of: store.searchText) { _ in
            seedDraftsForVisibleTimeline()
            queueScrollToSelection()
        }
        .onChange(of: store.entries) { _ in
            pruneDrafts()
            seedDraftsForVisibleTimeline()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wickWillFlushJournalDrafts)) { _ in
            flushAllDraftsImmediately()
        }
        .onReceive(store.remoteEntryDidApply) { apply in
            rebaseDraftIfClean(apply)
        }
        .onDisappear {
            flushAllDraftsImmediately()
        }
        .disabled(store.isReadOnlyDueToLoadFailure)
        .fileImporter(
            isPresented: $showImageImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            // Read the target before clearing: isPresented resets *before*
            // this completion runs, so a payload-driven binding would
            // already be nil here (that bug made picks no-op).
            defer { imageImportTarget = nil }
            guard case .success(let urls) = result,
                  let target = imageImportTarget
            else {
                return
            }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                _ = store.addImage(from: url, to: target.entryID, itemID: target.itemID)
            }
            mergeImagesFromStore(entryID: target.entryID)
        }
        .confirmationDialog(
            L10n.string(.journalDeleteConfirm, language: settings.language),
            isPresented: $showDeleteDayConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.string(.journalDelete, language: settings.language), role: .destructive) {
                if let id = pendingDeleteDayID {
                    cancelSave(for: id)
                    drafts[id] = nil
                    store.deleteEntry(id: id)
                }
                pendingDeleteDayID = nil
            }
            Button(L10n.string(.cancel, language: settings.language), role: .cancel) {
                pendingDeleteDayID = nil
            }
        }
        .confirmationDialog(
            L10n.string(.journalDeleteItemConfirm, language: settings.language),
            isPresented: $showDeleteItemConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.string(.journalDeleteItem, language: settings.language), role: .destructive) {
                if let ref = pendingDeleteItem {
                    cancelSave(for: ref.entryID)
                    if let draft = drafts[ref.entryID] {
                        store.updateEntry(draft)
                    }
                    store.deleteItem(itemID: ref.itemID, from: ref.entryID)
                    if let entry = store.entries.first(where: { $0.id == ref.entryID }) {
                        drafts[ref.entryID] = entry
                    } else {
                        drafts[ref.entryID] = nil
                    }
                    dirtyEntryIDs.remove(ref.entryID)
                }
                pendingDeleteItem = nil
            }
            Button(L10n.string(.cancel, language: settings.language), role: .cancel) {
                pendingDeleteItem = nil
            }
        }
    }

    // MARK: - Empty states

    private var noSelection: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text(L10n.string(.journalSelectPrompt, language: settings.language))
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Button {
                _ = store.openOrCreateToday()
            } label: {
                Text(L10n.string(.journalNewEntry, language: settings.language))
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFilter: some View {
        VStack(spacing: 14) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text(L10n.string(.journalFilterEmptyTitle, language: settings.language))
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(L10n.string(.journalFilterEmptySubtitle, language: settings.language))
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Timeline

    /// 烛痕进度:今天 = 实时已燃比例;过去 = 1(燃尽);未来 = 0(未点燃)。
    private func burnElapsed(for date: Date) -> Double {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return 1 - TimeProgressCalculator.dayFractionRemaining(at: Date(), calendar: calendar)
        }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: Date()) ? 1 : 0
    }

    static let timelineTopScrollID = "timeline-top"

    private var timelineChrome: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .id(Self.timelineTopScrollID)

                LazyVStack(alignment: .leading, spacing: 30) {
                    if isItemScoped {
                        itemScopedSections
                    } else {
                        dayScopedSections
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 28)
                .frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            .hidesAppKitScrollers()
            .onChange(of: pendingScrollID) { target in
                guard let target else { return }
                // Double-pass: first layout pass may not have built LazyVStack rows yet.
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(target, anchor: .top)
                        if pendingScrollID == target {
                            pendingScrollID = nil
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dayScopedSections: some View {
        ForEach(store.filteredEntries) { entry in
            daySection(
                entryID: entry.id,
                isFocused: store.selectedEntryID == entry.id
            )
            .id(Self.dayScrollID(entry.id))
            .onAppear {
                ensureDraft(for: entry.id)
            }
        }
    }

    @ViewBuilder
    private var itemScopedSections: some View {
        ForEach(itemDayGroups) { group in
            VStack(alignment: .leading, spacing: 0) {
                itemScopedDayHeader(group)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, row in
                        itemCard(
                            entryID: row.ref.entryID,
                            itemID: row.ref.itemID
                        )
                        .id(Self.itemScrollID(row.ref))
                        .onAppear {
                            ensureDraft(for: row.ref.entryID)
                        }
                        if index < group.items.count - 1 {
                            Rectangle()
                                .fill(palette.divider.color.opacity(0.8))
                                .frame(height: 1)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 26)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.pageSurface.color)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .shadow(color: palette.pageShadow.color.opacity(0.3), radius: 13, x: 0, y: 5)
        }
    }

    private func itemScopedDayHeader(_ group: ItemDayGroup) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(formattedDate(group.day))
                .font(.system(size: 17, weight: .black, design: .serif))
                .foregroundStyle(palette.textPrimary.color)

            Spacer(minLength: 8)

            Button {
                // Leave filter mode and open this calendar day fully.
                store.selectedTagFilter = nil
                store.searchText = ""
                store.selectDay(group.representativeEntryID)
            } label: {
                Image(systemName: "calendar")
            }
            .buttonStyle(JournalQuietIconButtonStyle())
            .help(L10n.string(.journalOpenFullDay, language: settings.language))
            .accessibilityLabel(Text(L10n.string(.journalOpenFullDay, language: settings.language)))
        }
    }

    // MARK: - Day section(一天 = 一页纸,秉烛 §03)

    @ViewBuilder
    private func daySection(
        entryID: UUID,
        isFocused: Bool
    ) -> some View {
        let draft = drafts[entryID] ?? store.entries.first(where: { $0.id == entryID }) ?? JournalEntry()

        VStack(alignment: .leading, spacing: 0) {
            dayHeader(entryID: entryID, draft: draft, isFocused: isFocused)

            dayBurnStrip(for: draft.date)
                .padding(.top, 12)

            // 条目沿发丝线下排,不加卡片壳。
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(draft.items.enumerated()), id: \.element.id) { index, item in
                    itemCard(
                        entryID: entryID,
                        itemID: item.id,
                        itemIndex: index
                    )
                    if index < draft.items.count - 1 {
                        Rectangle()
                            .fill(palette.divider.color.opacity(0.8))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.top, 4)

            addItemRow(entryID: entryID)
                .padding(.top, 10)
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.pageSurface.color)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: palette.pageShadow.color.opacity(0.3), radius: 13, x: 0, y: 5)
    }

    /// 页眉:粗衬线大日期(点开可改日)+ 星期农历小注 + 当日已实现盈亏 + 删除。
    /// 单行排不下时(ViewThatFits 按理想宽度判定)退成两行版——所有部件都是
    /// fixedSize,绝不把盈亏数字压成竖排;页宽一致后各页也不会宽窄不一。
    private func dayHeader(
        entryID: UUID,
        draft: JournalEntry,
        isFocused: Bool
    ) -> some View {
        ViewThatFits {
            // 舒适宽:单行全件。
            HStack(alignment: .bottom, spacing: 14) {
                dayHeaderDateButton(entryID: entryID, draft: draft)
                dayHeaderStamp(draft: draft)
                Spacer(minLength: 8)
                dayHeaderPnL(draft: draft)
                dayHeaderMeta(isFocused: isFocused)
                dayHeaderTrash(entryID: entryID)
            }

            // 地板宽:大日期+小注+删除一行,盈亏与保存注挪到下行靠右。
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 14) {
                    dayHeaderDateButton(entryID: entryID, draft: draft)
                    dayHeaderStamp(draft: draft)
                    Spacer(minLength: 8)
                    dayHeaderTrash(entryID: entryID)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    Spacer(minLength: 8)
                    dayHeaderPnL(draft: draft)
                    dayHeaderMeta(isFocused: isFocused)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 大日期钮(点开改日),两种排版共用。
    private func dayHeaderDateButton(entryID: UUID, draft: JournalEntry) -> some View {
        Button {
            datePickerEntryID = entryID
        } label: {
            Text(bigDayDate(draft.date))
                .font(.system(size: 28, weight: .black, design: .serif))
                .foregroundStyle(palette.textPrimary.color)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L10n.string(.journalChangeDate, language: settings.language)))
        .popover(isPresented: Binding(
            get: { datePickerEntryID == entryID },
            set: { if !$0 { datePickerEntryID = nil } }
        ), arrowEdge: .top) {
            JournalDatePickerView(
                selectedDate: Binding(
                    get: { drafts[entryID]?.date ?? draft.date },
                    set: { newValue in
                        mutateDraft(entryID) { entry in
                            entry.date = Calendar.current.startOfDay(for: newValue)
                        }
                        scheduleSave(for: entryID)
                    }
                ),
                onSelectDate: { _ in
                    datePickerEntryID = nil
                }
            )
        }
    }

    /// 刻印小注:星期 · 农历干支(宋体);竖排两行,不折行。
    private func dayHeaderStamp(draft: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(draft.date.formatted(.dateTime.weekday(.wide).locale(settings.locale)))
            if let lunar = LunarLine.string(for: draft.date) {
                Text(lunar)
            }
        }
        .font(.custom("Songti SC", size: 11))
        .foregroundStyle(palette.textSecondary.color)
        .lineLimit(1)
        .fixedSize()
        .padding(.bottom, 3)
    }

    /// 当日已实现盈亏:单据等宽数字,红盈黛亏;该日无成交则不占版。
    /// fixedSize 钉死——宁可换行排版也绝不逐字竖排。
    @ViewBuilder
    private func dayHeaderPnL(draft: JournalEntry) -> some View {
        if let pnl = dayPnLs[Calendar.current.startOfDay(for: draft.date)] {
            VStack(alignment: .trailing, spacing: 2) {
                Text(L10n.string(.exchangePositionNetPnl, language: settings.language))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textTertiary.color)
                Text(Self.format(pnl: pnl) + " USDT")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(pnl >= 0 ? palette.pnlUp.color : palette.pnlDown.color)
            }
            .fixedSize()
            .padding(.bottom, 2)
        }
    }

    /// 保存状态小注(只读告警 / 已自动保存),无则空视图。
    @ViewBuilder
    private func dayHeaderMeta(isFocused: Bool) -> some View {
        if store.isReadOnlyDueToLoadFailure {
            Text(L10n.string(.journalReadOnly, language: settings.language))
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.bottom, 5)
        } else if isFocused {
            Text(L10n.string(.journalAutosaved, language: settings.language))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(palette.textTertiary.color)
                .lineLimit(1)
                .fixedSize()
                .padding(.bottom, 5)
        }
    }

    private func dayHeaderTrash(entryID: UUID) -> some View {
        Button {
            pendingDeleteDayID = entryID
            showDeleteDayConfirm = true
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(JournalQuietIconButtonStyle(role: .destructive))
        .padding(.bottom, 2)
        .help(L10n.string(.journalDelete, language: settings.language))
        .accessibilityLabel(Text(L10n.string(.journalDelete, language: settings.language)))
    }

    /// 页内烛痕条:今天烧到此刻(带烛苗与进度小字),过去的天天然燃尽。
    private func dayBurnStrip(for date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let elapsed = burnElapsed(for: date)
        return VStack(spacing: 5) {
            BurnStripView(elapsed: elapsed, ticks: 24, showsFlame: isToday)
                .frame(height: 8)
            if isToday {
                HStack {
                    Text(String(
                        format: L10n.string(.journalDayElapsedFormat, language: settings.language),
                        Int((elapsed * 100).rounded())
                    ))
                    Spacer()
                    Text("00:00 — 24:00")
                }
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(palette.textTertiary.color)
            }
        }
    }

    /// 新建条目:虚线位,安静的一行,不抢版面。
    private func addItemRow(entryID: UUID) -> some View {
        Button {
            addItem(to: entryID)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text(L10n.string(.journalAddItem, language: settings.language))
                    .font(.custom("Songti SC", size: 11).weight(.medium))
            }
            .foregroundStyle(palette.textTertiary.color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        palette.divider.color,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            }
        }
        .buttonStyle(.plain)
        .help(L10n.string(.journalAddItem, language: settings.language))
        .accessibilityLabel(Text(L10n.string(.journalAddItem, language: settings.language)))
    }

    /// 各日已实现盈亏(本地日分桶,与盈亏月历同一来源)。
    private var dayPnLs: [Date: Double] {
        positionCoordinator.pnlByDay
    }

    private static let pnlFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static func format(pnl: Double) -> String {
        let sign = pnl >= 0 ? "+" : "−"
        let digits = pnlFormatter.string(from: NSNumber(value: pnl.magnitude)) ?? "0.00"
        return sign + digits
    }

    /// 页眉大日期:中文「8月20日」,英文「Aug 20」。
    private func bigDayDate(_ date: Date) -> String {
        WickDateFormat.string(from: date, template: "MMMd", locale: settings.language.locale)
    }

    // MARK: - Item card

    private func itemCard(
        entryID: UUID,
        itemID: UUID,
        itemIndex: Int? = nil
    ) -> some View {
        let draft = drafts[entryID] ?? store.entries.first(where: { $0.id == entryID }) ?? JournalEntry()
        let index = itemIndex ?? displayIndex(for: itemID, in: draft, fallback: 0)
        let canDelete = isItemScoped || draft.items.count > 1
        let reviewEligible = Calendar.current.startOfDay(for: draft.date)
            < Calendar.current.startOfDay(for: Date())

        return JournalItemEditorCard(
            entryID: entryID,
            entryDayKey: draft.dayKey,
            index: index,
            item: binding(entryID: entryID, itemID: itemID),
            canDelete: canDelete,
            reviewEligible: reviewEligible,
            onDelete: {
                if isItemScoped {
                    pendingDeleteItem = JournalItemRef(entryID: entryID, itemID: itemID)
                    showDeleteItemConfirm = true
                } else {
                    deleteItem(itemID: itemID, from: entryID)
                }
            },
            onPasteImage: {
                pasteImage(to: itemID, in: entryID)
            },
            onPickImage: {
                imageImportTarget = JournalItemRef(entryID: entryID, itemID: itemID)
                showImageImporter = true
            },
            onDrop: { providers in
                handleDrop(providers, itemID: itemID, entryID: entryID)
            },
            onChange: { scheduleSave(for: entryID) },
            isEditing: editingItemID == itemID,
            initialFocus: editingFocus,
            onBeginEditing: { focus in
                editingItemID = itemID
                editingFocus = focus
            }
        )
        .onDisappear {
            if editingItemID == itemID {
                editingItemID = nil
            }
        }
    }

    // MARK: - Item-scoped grouping

    private struct ItemDayGroup: Identifiable {
        /// Start-of-day key.
        var id: Date { day }
        let day: Date
        let items: [JournalTimelineItem]

        var representativeEntryID: UUID {
            items.first?.ref.entryID ?? UUID()
        }
    }

    private var itemDayGroups: [ItemDayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.filteredTimelineItems) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped.keys.sorted(by: >).map { day in
            ItemDayGroup(day: day, items: grouped[day] ?? [])
        }
    }

    // MARK: - Draft helpers

    private static func dayScrollID(_ entryID: UUID) -> String {
        "day-\(entryID.uuidString)"
    }

    private static func itemScrollID(_ ref: JournalItemRef) -> String {
        "item-\(ref.id)"
    }

    private func scrollID(for selection: JournalSelection?) -> String? {
        switch selection {
        case .day(let id):
            if id == store.filteredEntries.first?.id {
                return Self.timelineTopScrollID
            }
            return Self.dayScrollID(id)
        case .item(let ref):
            if isItemScoped {
                if let firstGroup = itemDayGroups.first,
                   let firstItem = firstGroup.items.first,
                   firstItem.ref == ref
                {
                    return Self.timelineTopScrollID
                }
            } else if ref.entryID == store.filteredEntries.first?.id && ref.itemID == store.filteredEntries.first?.items.first?.id {
                return Self.timelineTopScrollID
            }
            return Self.itemScrollID(ref)
        case nil:
            return nil
        }
    }

    private func queueScrollToSelection() {
        guard let id = scrollID(for: store.selection) else { return }
        pendingScrollID = id
    }

    private func seedDraftsForVisibleTimeline() {
        if let id = store.selectedEntryID {
            ensureDraft(for: id)
        }
    }

    private func ensureDraft(for entryID: UUID) {
        guard drafts[entryID] == nil,
              let entry = store.entries.first(where: { $0.id == entryID })
        else {
            return
        }
        drafts[entryID] = entry
    }

    private func pruneDrafts() {
        let live = Set(store.entries.map(\.id))
        for key in drafts.keys where !live.contains(key) {
            cancelSave(for: key)
            drafts[key] = nil
            dirtyEntryIDs.remove(key)
        }
    }

    private func mutateDraft(_ entryID: UUID, _ body: (inout JournalEntry) -> Void) {
        ensureDraft(for: entryID)
        guard var draft = drafts[entryID] else { return }
        body(&draft)
        drafts[entryID] = draft
        dirtyEntryIDs.insert(entryID)
    }

    private func binding(entryID: UUID, itemID: UUID) -> Binding<JournalItem> {
        Binding(
            get: {
                if let item = drafts[entryID]?.items.first(where: { $0.id == itemID }) {
                    return item
                }
                if let item = store.entries
                    .first(where: { $0.id == entryID })?
                    .items.first(where: { $0.id == itemID })
                {
                    return item
                }
                return JournalItem(id: itemID)
            },
            set: { newValue in
                mutateDraft(entryID) { entry in
                    if let index = entry.items.firstIndex(where: { $0.id == itemID }) {
                        entry.items[index] = newValue
                    }
                }
            }
        )
    }

    private func displayIndex(for itemID: UUID, in draft: JournalEntry, fallback: Int) -> Int {
        if let index = draft.items.firstIndex(where: { $0.id == itemID }) {
            return index
        }
        return fallback
    }

    private func formattedDate(_ date: Date) -> String {
        WickDateFormat.string(from: date, template: "yMMMd", locale: settings.language.locale)
    }

    // MARK: - Persistence

    private func scheduleSave(for entryID: UUID) {
        guard !store.isReadOnlyDueToLoadFailure else { return }
        cancelSave(for: entryID)
        saveTasks[entryID] = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                if TextInputComposition.isActive {
                    continue
                }
                if let draft = drafts[entryID] {
                    store.updateEntry(draft)
                    dirtyEntryIDs.remove(entryID)
                }
                saveTasks[entryID] = nil
                return
            }
        }
    }

    private func cancelSave(for entryID: UUID) {
        saveTasks[entryID]?.cancel()
        saveTasks[entryID] = nil
    }

    private func flushAllDraftsImmediately() {
        let dirty = Array(dirtyEntryIDs)
        for entryID in dirty { cancelSave(for: entryID) }
        guard !store.isReadOnlyDueToLoadFailure else { return }
        for entryID in dirty {
            guard let draft = drafts[entryID],
                  store.entries.contains(where: { $0.id == entryID })
            else { continue }
            store.updateEntry(draft)
            dirtyEntryIDs.remove(entryID)
        }
    }

    /// A remote apply replaced the store entry for `apply.dayKey`. Rebasing the
    /// local draft is only safe when it is clean (no uncommitted typing); a
    /// dirty draft stays put and commits/merges on its own later.
    private func rebaseDraftIfClean(_ apply: JournalRemoteApply) {
        guard apply.journalID == store.activeJournalID else { return }
        guard let fresh = store.entries.first(where: { $0.id == apply.entryID }) else { return }
        // The draft may still be keyed by the pre-merge entry id on the same day.
        guard let draftKey = drafts.first(where: { $0.value.dayKey == apply.dayKey })?.key,
              !dirtyEntryIDs.contains(draftKey)
        else { return }
        cancelSave(for: draftKey)
        drafts[draftKey] = nil
        drafts[fresh.id] = fresh
    }

    private func mergeImagesFromStore(entryID: UUID) {
        guard let entry = store.entries.first(where: { $0.id == entryID }) else { return }
        mutateDraft(entryID) { draft in
            var merged = entry
            for index in merged.items.indices {
                let itemID = merged.items[index].id
                if let local = draft.items.first(where: { $0.id == itemID }) {
                    merged.items[index].tag = local.tag
                    merged.items[index].body = local.body
                }
            }
            merged.title = draft.title
            merged.date = draft.date
            draft = merged
        }
    }

    private func addItem(to entryID: UUID) {
        cancelSave(for: entryID)
        if let draft = drafts[entryID] {
            store.updateEntry(draft)
        }
        guard let item = store.addItem(to: entryID) else { return }
        mutateDraft(entryID) { draft in
            draft.items.append(item)
            draft.updatedAt = Date()
        }
    }

    private func deleteItem(itemID: UUID, from entryID: UUID) {
        cancelSave(for: entryID)
        if let draft = drafts[entryID] {
            store.updateEntry(draft)
        }
        store.deleteItem(itemID: itemID, from: entryID)
        if let entry = store.entries.first(where: { $0.id == entryID }) {
            drafts[entryID] = entry
        } else {
            drafts[entryID] = nil
        }
    }

    private func pasteImage(to itemID: UUID, in entryID: UUID) -> Bool {
        cancelSave(for: entryID)
        if let draft = drafts[entryID] {
            store.updateEntry(draft)
        }
        if store.pasteImageFromClipboard(to: entryID, itemID: itemID) {
            mergeImagesFromStore(entryID: entryID)
            return true
        }
        return false
    }

    private func handleDrop(_ providers: [NSItemProvider], itemID: UUID, entryID: UUID) -> Bool {
        var accepted = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        cancelSave(for: entryID)
                        if let draft = drafts[entryID] {
                            store.updateEntry(draft)
                        }
                        _ = store.addImage(
                            from: data,
                            to: entryID,
                            itemID: itemID,
                            preferredExtension: "png"
                        )
                        mergeImagesFromStore(entryID: entryID)
                    }
                }
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let value = item as? URL {
                        url = value
                    } else {
                        url = nil
                    }
                    guard let url else { return }
                    Task { @MainActor in
                        cancelSave(for: entryID)
                        if let draft = drafts[entryID] {
                            store.updateEntry(draft)
                        }
                        _ = store.addImage(from: url, to: entryID, itemID: itemID)
                        mergeImagesFromStore(entryID: entryID)
                    }
                }
            }
        }

        return accepted
    }
}
