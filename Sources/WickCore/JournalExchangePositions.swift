import SwiftUI

/// Exchange positions matched to a journal item, shown inside the item card as
/// pasted exchange receipts (撕边小票 + 胶带). Receipt paper is physical: it
/// stays cream in dark mode, and its inks are print constants. Hidden entirely
/// when nothing matches.
struct JournalExchangePositions: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var coordinator = ExchangePositionCoordinator.shared
    @Environment(\.wickPalette) private var palette

    let entryDayKey: String
    let tag: String

    private var matched: [TradingPosition] {
        coordinator.positions(entryDayKey: entryDayKey, tag: tag)
    }

    var body: some View {
        if !matched.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string(.exchangePositionsTitle, language: settings.language))
                    .font(AppFont.ui(11, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textTertiary.color)
                    .textCase(.uppercase)
                    .tracking(0.4)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(matched.enumerated()), id: \.element.id) { index, position in
                        ReceiptView(position: position, tilt: index.isMultiple(of: 2) ? -0.4 : 0.5)
                    }
                }
            }
        }
    }
}

// MARK: - Receipt · 交易所单据

/// One position as a torn receipt pasted on the page. Layout: symbol + lane +
/// date range on top, dashed rules, tabular figures, realized PnL as the
/// total. 红盈黛亏 — print constants on physical paper (theme-exempt).
private struct ReceiptView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.wickPalette) private var palette

    let position: TradingPosition
    let tilt: Double

    /// Whether the realized / commission / funding breakdown is expanded.
    @State private var showsBreakdown = false

    /// Print inks on receipt paper (constant across schemes — the paper is).
    private let printUp = Color(red: 0.69, green: 0.20, blue: 0.12)   // #B0341E
    private let printDown = Color(red: 0.24, green: 0.36, blue: 0.31) // #3E5C50

    /// 涨跌配色下的盈/亏色 —— 只在上面两个纸面墨色里互换，不改墨色值本身。
    private var printGain: Color {
        settings.pnlColorConvention == .redUp ? printUp : printDown
    }
    private var printLoss: Color {
        settings.pnlColorConvention == .redUp ? printDown : printUp
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: symbol + lane + date range
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(headerTitle)
                    .font(AppFont.ui(11, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.receiptInk.color)
                laneBadge
                Spacer(minLength: 6)
                Text(dateRange)
                    .font(AppFont.ui(9, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.receiptInk.color.opacity(0.6))
            }
            .padding(.bottom, 5)
            .overlay(alignment: .bottom) {
                DashedRule()
            }

            row(label: priceLabel, value: priceText)
                .padding(.top, 5)
            row(label: sizeLabel, value: sizeText)
            totalRow
            breakdown
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 9)
        .background(ReceiptShape().fill(palette.receipt.color))
        .overlay(alignment: .top) {
            // Two tape strips half over the top edge
            HStack {
                TapeStrip().frame(width: 46, height: 13).rotationEffect(.degrees(-4)).offset(y: -6)
                Spacer()
                TapeStrip().frame(width: 46, height: 13).rotationEffect(.degrees(3)).offset(y: -6)
            }
            .padding(.horizontal, 14)
            .allowsHitTesting(false)
        }
        .rotationEffect(.degrees(tilt))
        .shadow(color: palette.textPrimary.color.opacity(0.14), radius: 3, y: 1)
        .accessibilityElement(children: .combine)
    }

    // MARK: Rows

    private func row(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer(minLength: 8)
            Text(value)
        }
        .font(AppFont.ui(10.5, weight: .medium, design: .monospaced))
        .foregroundStyle(palette.receiptInk.color.opacity(0.78))
        .padding(.vertical, 2.5)
        .overlay(alignment: .bottom) {
            DashedRule().opacity(0.6)
        }
    }

    private var totalRow: some View {
        Group {
            if position.isClosed {
                closedTotalRow
            } else {
                holdingRow
            }
        }
        .padding(.top, 5)
    }

    private var closedTotalRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsBreakdown.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(showsBreakdown ? "▾" : "▸")
                        .font(AppFont.ui(8, weight: .bold, design: .monospaced))
                    Text(L10n.string(.exchangePositionNetPnl, language: settings.language))
                        .font(AppFont.ui(10.5, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(palette.receiptInk.color.opacity(0.78))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Text(netText)
                .font(AppFont.ui(12.5, weight: .bold, design: .monospaced))
                .foregroundStyle(position.netPnl >= 0 ? printGain : printLoss)
        }
    }

    /// Open positions have no realized result yet — a net PnL figure would be
    /// misleading, so the receipt carries a "holding" note instead.
    private var holdingRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.string(.exchangePositionOpen, language: settings.language))
                .font(AppFont.ui(10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.receiptInk.color)
            Spacer(minLength: 8)
            Text(Self.dateFormatter.string(from: position.openTime))
                .font(AppFont.ui(10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.receiptInk.color.opacity(0.6))
        }
    }

    /// Expanded fee breakdown: realized / commission / funding. Rows with a
    /// zero value are omitted so the paper stays clean.
    @ViewBuilder
    private var breakdown: some View {
        if showsBreakdown {
            breakdownRow(
                label: L10n.string(.exchangePositionRealizedPnl, language: settings.language),
                value: signedText(position.realizedPnl),
                valueColor: position.realizedPnl >= 0 ? printGain : printLoss,
                shows: abs(position.realizedPnl) > 1e-9
            )
            breakdownRow(
                label: L10n.string(.exchangePositionCommission, language: settings.language),
                value: "−" + Self.format(pnl: position.commissionTotal) + quoteSuffix,
                valueColor: printLoss,
                shows: position.commissionTotal > 1e-9
            )
            breakdownRow(
                label: L10n.string(.exchangePositionFunding, language: settings.language),
                value: signedText(position.fundingPnl),
                valueColor: position.fundingPnl >= 0 ? printGain : printLoss,
                shows: abs(position.fundingPnl) > 1e-9
            )
        }
    }

    private func breakdownRow(label: String, value: String, valueColor: Color, shows: Bool) -> some View {
        Group {
            if shows {
                HStack(alignment: .firstTextBaseline) {
                    Text(label)
                    Spacer(minLength: 8)
                    Text(value)
                        .foregroundStyle(valueColor)
                }
                .font(AppFont.ui(10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.receiptInk.color.opacity(0.78))
                .padding(.vertical, 2.5)
                .overlay(alignment: .bottom) {
                    DashedRule().opacity(0.5)
                }
            }
        }
    }

    private var laneBadge: some View {
        let isLong = position.side == .long
        return Text(L10n.string(isLong ? .exchangePositionLong : .exchangePositionShort, language: settings.language))
            .font(AppFont.ui(9, weight: .bold))
            .foregroundStyle(isLong ? printUp : printDown)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background((isLong ? printUp : printDown).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
    }

    // MARK: Text

    private var headerTitle: String {
        position.symbol
    }

    private var dateRange: String {
        let open = Self.dateFormatter.string(from: position.openTime)
        if let close = position.closeTime {
            return "\(open) → \(Self.dateFormatter.string(from: close))"
        }
        return open
    }

    private var priceLabel: String {
        L10n.string(.exchangePositionVwap, language: settings.language)
    }

    private var priceText: String {
        var text = Self.format(price: position.entryPrice)
        if let exitPrice = position.exitPrice {
            text += " → \(Self.format(price: exitPrice))"
        }
        return text
    }

    private var sizeLabel: String {
        L10n.string(.exchangePositionSize, language: settings.language)
    }

    private var sizeText: String {
        Self.format(quantity: position.peakSize)
    }

    private var netText: String {
        signedText(position.netPnl)
    }

    private var quoteSuffix: String {
        position.quoteAsset.map { " \($0)" } ?? ""
    }

    private func signedText(_ value: Double) -> String {
        var text = value >= 0 ? "+" : "−"
        text += Self.format(pnl: value.magnitude)
        return text + quoteSuffix
    }

    // MARK: Formatters

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static let priceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumSignificantDigits = 6
        return formatter
    }()

    private static let pnlFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static func format(price value: Double) -> String {
        priceFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func format(quantity value: Double) -> String {
        priceFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func format(pnl value: Double) -> String {
        pnlFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// 1pt dashed rule, receipt style.
private struct DashedRule: View {
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 1)
            .overlay {
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 0.7, dash: [3, 2.5]))
                    .foregroundStyle(Color(red: 0.2, green: 0.16, blue: 0.1).opacity(0.35))
            }
    }
}
