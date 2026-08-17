import SwiftUI

/// Exchange positions matched to a journal item, shown inside the item card:
/// positions whose open day equals the entry's day and whose symbol loosely
/// matches the item's tag. Hidden entirely when nothing matches.
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
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textTertiary.color)
                    .textCase(.uppercase)
                    .tracking(0.4)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(matched) { position in
                        positionRow(position)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.cardTop.scaledAlpha(0.4).color)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(palette.cardStroke.scaledAlpha(0.4).color, lineWidth: 1)
            }
        }
    }

    private func positionRow(_ position: TradingPosition) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 8) {
                Text(position.symbol)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textPrimary.color)

                sideBadge(position.side)

                Spacer(minLength: 8)

                Text(
                    L10n.string(
                        position.isClosed ? .exchangePositionClosed : .exchangePositionOpen,
                        language: settings.language
                    )
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textTertiary.color)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(sizeAndPriceText(position))
                Spacer(minLength: 8)
                Text(pnlText(position))
                    .foregroundStyle(pnlColor(position))
            }
            .font(.system(size: 11, design: .rounded).monospacedDigit())
            .foregroundStyle(palette.textSecondary.color)
        }
        .accessibilityElement(children: .combine)
    }

    private func sideBadge(_ side: TradingPositionSide) -> some View {
        let isLong = side == .long
        let text = L10n.string(
            isLong ? .exchangePositionLong : .exchangePositionShort,
            language: settings.language
        )
        return HStack(spacing: 2) {
            Image(systemName: isLong ? "arrow.up.forward" : "arrow.down.forward")
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(isLong ? palette.accentText.color : palette.textSecondary.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(isLong ? palette.accentSoft.color : palette.controlBackground.color)
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(palette.controlBorder.color, lineWidth: 1)
        }
    }

    // MARK: - Formatting

    private func sizeAndPriceText(_ position: TradingPosition) -> String {
        var text = "\(Self.format(quantity: position.peakSize)) @ \(Self.format(price: position.entryPrice))"
        if let exitPrice = position.exitPrice {
            text += " -> \(Self.format(price: exitPrice))"
        }
        return text
    }

    private func pnlText(_ position: TradingPosition) -> String {
        var text = position.realizedPnl >= 0 ? "+" : "-"
        text += Self.format(pnl: position.realizedPnl.magnitude)
        if let quote = position.quoteAsset {
            text += " \(quote)"
        }
        return text
    }

    private func pnlColor(_ position: TradingPosition) -> Color {
        position.realizedPnl >= 0
            ? palette.reviewCorrect.color
            : palette.reviewWrong.color
    }

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
