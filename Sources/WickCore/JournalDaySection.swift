import AppKit
import SwiftUI
import WickCalendarKit
import WickSync

// MARK: - Day section

/// One journal day in the editor timeline (UI-04).
///
/// `Equatable` on its data inputs so SwiftUI skips `body` re-evaluation when a
/// keystroke only touched another day's draft — the day section is the unit of
/// "currently editing block". Interaction closures are deliberately excluded
/// from `==` (they capture the pane and are never equal); they only read/mutate
/// shared `@State` storage, so a skipped section still behaves correctly when
/// the user re-enters it.
struct JournalDaySection: View, Equatable {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.wickPalette) private var palette

    let entryID: UUID
    let draft: JournalEntry
    let isFocused: Bool
    /// Day-scoped (false) vs item-scoped timeline; affects delete affordance.
    let isItemScoped: Bool
    /// Resolved day PnL (nil = no trades that day). Included in equality so a
    /// PnL update refreshes just that day's header.
    let dayPnL: Double?

    // MARK: Interaction closures (excluded from ==)

    let onChangeDate: (Date) -> Void
    let onAddItem: () -> Void
    let onRequestDeleteDay: () -> Void
    let isShowingDatePicker: () -> Bool
    let setShowingDatePicker: (Bool) -> Void
    let makeItemBinding: (UUID) -> Binding<JournalItem>
    let onDeleteItem: (UUID) -> Void
    let onPasteImage: (UUID) -> Bool
    let onPickImage: (UUID) -> Void
    let onDrop: (UUID, [NSItemProvider]) -> Bool
    let onItemChange: () -> Void
    let onPreviewImage: ([String], Int) -> Void
    let onBeginEditingItem: (UUID, ItemEditorFocus) -> Void
    let onItemDisappear: (UUID) -> Void
    let editingItemID: UUID?
    let editingFocus: ItemEditorFocus

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entryID == rhs.entryID
            && lhs.draft == rhs.draft
            && lhs.isFocused == rhs.isFocused
            && lhs.isItemScoped == rhs.isItemScoped
            && lhs.dayPnL == rhs.dayPnL
            && lhs.editingItemID == rhs.editingItemID
            && lhs.editingFocus == rhs.editingFocus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayHeader

            dayBurnStrip(for: draft.date)
                .padding(.top, 12)

            // 条目沿发丝线下排,不加卡片壳。
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(draft.items.enumerated()), id: \.element.id) { index, item in
                    itemCard(itemID: item.id, itemIndex: index)
                    if index < draft.items.count - 1 {
                        Rectangle()
                            .fill(palette.divider.color.opacity(0.8))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.top, 4)

            addItemRow
                .padding(.top, 10)
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .journalPaperSheet()
    }

    // MARK: Header

    /// 页眉:粗衬线大日期(点开可改日)+ 星期农历小注 + 当日已实现盈亏 + 删除。
    /// 单行排不下时(ViewThatFits 按理想宽度判定)退成两行版——所有部件都是
    /// fixedSize,绝不把盈亏数字压成竖排;页宽一致后各页也不会宽窄不一。
    private var dayHeader: some View {
        ViewThatFits {
            // 舒适宽:单行全件。
            HStack(alignment: .bottom, spacing: 14) {
                dayHeaderDateButton
                dayHeaderStamp
                Spacer(minLength: 8)
                dayHeaderPnL
                dayHeaderMeta
                dayHeaderTrash
            }

            // 地板宽:大日期+小注+删除一行,盈亏与保存注挪到下行靠右。
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 14) {
                    dayHeaderDateButton
                    dayHeaderStamp
                    Spacer(minLength: 8)
                    dayHeaderTrash
                }
                HStack(alignment: .bottom, spacing: 10) {
                    Spacer(minLength: 8)
                    dayHeaderPnL
                    dayHeaderMeta
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 大日期钮(点开改日),两种排版共用。
    private var dayHeaderDateButton: some View {
        Button {
            setShowingDatePicker(true)
        } label: {
            Text(bigDayDate(draft.date))
                .font(AppFont.ui(28, weight: .black, design: .serif))
                .foregroundStyle(palette.textPrimary.color)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L10n.string(.journalChangeDate, language: settings.language)))
        .popover(isPresented: Binding(
            get: { isShowingDatePicker() },
            set: { setShowingDatePicker($0) }
        ), arrowEdge: .top) {
            JournalDatePickerView(
                selectedDate: Binding(
                    get: { draft.date },
                    set: { onChangeDate(Calendar.current.startOfDay(for: $0)) }
                ),
                onSelectDate: { _ in
                    setShowingDatePicker(false)
                }
            )
        }
    }

    /// 刻印小注:周几 · 农历干支(宋体);竖排两行,不折行。
    private var dayHeaderStamp: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(draft.date.formatted(.dateTime.weekday(.abbreviated).locale(settings.locale)))
            if let lunar = LunarLine.string(for: draft.date) {
                Text(lunar)
            }
        }
        .font(AppFont.paper(11))
        .foregroundStyle(palette.textSecondary.color)
        .lineLimit(1)
        .fixedSize()
        .padding(.bottom, 3)
    }

    /// 当日已实现盈亏:单据等宽数字,红盈黛亏;该日无成交则不占版。
    /// fixedSize 钉死——宁可换行排版也绝不逐字竖排。
    @ViewBuilder
    private var dayHeaderPnL: some View {
        if let pnl = dayPnL {
            VStack(alignment: .trailing, spacing: 2) {
                Text(L10n.string(.exchangePositionNetPnl, language: settings.language))
                    .font(AppFont.ui(9, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textTertiary.color)
                Text(Self.format(pnl: pnl) + " USDT")
                    .font(AppFont.ui(14, weight: .bold, design: .monospaced))
                    .foregroundStyle(pnl >= 0 ? gainLoss.gain : gainLoss.loss)
            }
            .fixedSize()
            .padding(.bottom, 2)
        }
    }

    /// 保存状态小注(只读告警 / 已自动保存),无则空视图。
    @ViewBuilder
    private var dayHeaderMeta: some View {
        if store.isReadOnlyDueToLoadFailure {
            Text(L10n.string(.journalReadOnly, language: settings.language))
                .font(AppFont.preset(.caption))
                .foregroundStyle(.orange)
                .padding(.bottom, 5)
        } else if isFocused {
            Text(L10n.string(.journalAutosaved, language: settings.language))
                .font(AppFont.ui(9, design: .monospaced))
                .foregroundStyle(palette.textTertiary.color)
                .lineLimit(1)
                .fixedSize()
                .padding(.bottom, 5)
        }
    }

    private var dayHeaderTrash: some View {
        Button {
            onRequestDeleteDay()
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
            BurnStripView(elapsed: elapsed, ticks: 24, showsFlame: isToday, flameAnimates: isToday)
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
                .font(AppFont.ui(9.5, design: .monospaced))
                .foregroundStyle(palette.textTertiary.color)
            }
        }
    }

    /// 新建条目:虚线位,安静的一行,不抢版面。
    private var addItemRow: some View {
        Button {
            onAddItem()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(AppFont.ui(10, weight: .semibold))
                Text(L10n.string(.journalAddItem, language: settings.language))
                    .font(AppFont.paper(11, weight: .medium))
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

    // MARK: Item card

    private func itemCard(itemID: UUID, itemIndex: Int) -> some View {
        let canDelete = isItemScoped || draft.items.count > 1
        let reviewEligible = Calendar.current.startOfDay(for: draft.date)
            < Calendar.current.startOfDay(for: Date())

        return JournalItemEditorCard(
            entryID: entryID,
            entryDate: draft.date,
            index: itemIndex,
            item: makeItemBinding(itemID),
            canDelete: canDelete,
            reviewEligible: reviewEligible,
            onDelete: { onDeleteItem(itemID) },
            onPasteImage: { onPasteImage(itemID) },
            onPickImage: { onPickImage(itemID) },
            onDrop: { providers in onDrop(itemID, providers) },
            onChange: onItemChange,
            onPreviewImage: { filenames, index in onPreviewImage(filenames, index) },
            isEditing: editingItemID == itemID,
            initialFocus: editingFocus,
            onBeginEditing: { focus in onBeginEditingItem(itemID, focus) }
        )
        .equatable()
        .onDisappear {
            onItemDisappear(itemID)
        }
    }

    // MARK: Helpers

    /// 烛痕进度:今天 = 实时已燃比例;过去 = 1(燃尽);未来 = 0(未点燃)。
    private func burnElapsed(for date: Date) -> Double {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return 1 - TimeProgressCalculator.dayFractionRemaining(at: Date(), calendar: calendar)
        }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: Date()) ? 1 : 0
    }

    /// 涨跌配色下的盈/亏色(只换用哪个已有色值,不改色值本身)。
    private var gainLoss: (gain: Color, loss: Color) {
        let pair = palette.upDownColors(settings.pnlColorConvention)
        return (pair.gain.color, pair.loss.color)
    }

    /// 页眉大日期:中文「8月20日」,英文「Aug 20」。
    private func bigDayDate(_ date: Date) -> String {
        WickDateFormat.string(from: date, template: "MMMd", locale: settings.language.locale)
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
}
