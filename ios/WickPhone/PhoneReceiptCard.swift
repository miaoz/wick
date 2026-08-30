import SwiftUI
import WickCalendarKit
import WickSync
import WickTrading

/// Torn receipt shape with jagged top/bottom edges.
struct ReceiptShape: Shape {
    var teethCount: Int = 18
    var toothDepth: CGFloat = 3.5

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + toothDepth))

        // Top jagged teeth
        let toothWidth = rect.width / CGFloat(teethCount)
        for i in 0..<teethCount {
            let x1 = rect.minX + CGFloat(i) * toothWidth + toothWidth * 0.5
            let y1 = (i % 2 == 0) ? rect.minY : (rect.minY + toothDepth)
            let x2 = rect.minX + CGFloat(i + 1) * toothWidth
            let y2 = (i % 2 == 0) ? (rect.minY + toothDepth) : rect.minY
            p.addLine(to: CGPoint(x: x1, y: y1))
            p.addLine(to: CGPoint(x: x2, y: y2))
        }

        // Right edge
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - toothDepth))

        // Bottom jagged teeth
        for i in 0..<teethCount {
            let x1 = rect.maxX - (CGFloat(i) * toothWidth + toothWidth * 0.5)
            let y1 = (i % 2 == 0) ? rect.maxY : (rect.maxY - toothDepth)
            let x2 = rect.maxX - CGFloat(i + 1) * toothWidth
            let y2 = (i % 2 == 0) ? (rect.maxY - toothDepth) : rect.maxY
            p.addLine(to: CGPoint(x: x1, y: y1))
            p.addLine(to: CGPoint(x: x2, y: y2))
        }

        // Left edge
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + toothDepth))
        p.closeSubpath()
        return p
    }
}

/// Exchange trade receipt component attached to journal item cards.
struct PhoneReceiptCard: View {
    let position: TradingPosition
    var language: AppLanguage? = nil
    @Environment(\.appLanguage) private var envLanguage: AppLanguage

    private var currentLanguage: AppLanguage {
        language ?? envLanguage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: Symbol + Side + Time Range
            HStack(alignment: .firstTextBaseline) {
                Text(position.headerTitle(isChinese: currentLanguage == .chinese))
                    .font(PhoneFont.ui(11.5, weight: .bold, monospacedDigit: true))
                    .foregroundColor(PhoneTheme.receiptInk)

                let isLong = position.side == .long
                Text(L10n.string(isLong ? .exchangePositionLong : .exchangePositionShort, language: currentLanguage))
                    .font(PhoneFont.ui(9, weight: .bold))
                    .foregroundColor(PhoneTheme.pnlColor(isGain: isLong))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        PhoneTheme.pnlColorSoft(isGain: isLong)
                    )
                    .cornerRadius(2)

                Spacer()

                Text(dateRangeText)
                    .font(PhoneFont.ui(9.5, monospacedDigit: true))
                    .foregroundColor(PhoneTheme.receiptInk.opacity(0.6))
            }

            // Dashed Divider
            Rectangle()
                .fill(PhoneTheme.receiptInk.opacity(0.15))
                .frame(height: 1)

            // Row 1: VWAP
            HStack {
                Text(L10n.string(.exchangePositionVwap, language: currentLanguage))
                    .font(PhoneFont.ui(10, weight: .medium))
                    .foregroundColor(PhoneTheme.receiptInk.opacity(0.8))

                Spacer()

                let priceText = position.exitPrice.map { "\(formatPrice(position.entryPrice)) → \(formatPrice($0))" } ?? formatPrice(position.entryPrice)
                Text(priceText)
                    .font(PhoneFont.ui(10, monospacedDigit: true))
                    .foregroundColor(PhoneTheme.receiptInk.opacity(0.8))
            }

            // Row 2: Size · Duration
            HStack {
                Text(L10n.string(.exchangePositionSize, language: currentLanguage))
                    .font(PhoneFont.ui(10, weight: .medium))
                    .foregroundColor(PhoneTheme.receiptInk.opacity(0.8))

                Spacer()

                let base = SymbolTagMatcher.baseAsset(of: position.symbol)
                let duration = position.durationText(isChinese: currentLanguage == .chinese)
                Text("\(formatPrice(position.peakSize)) \(base) · \(duration)")
                    .font(PhoneFont.ui(10, monospacedDigit: true))
                    .foregroundColor(PhoneTheme.receiptInk.opacity(0.8))
            }

            // Total / Holding Row
            if position.isClosed {
                HStack {
                    Text(L10n.string(.exchangePositionNetPnl, language: currentLanguage))
                        .font(PhoneFont.paper(10.5, weight: .semibold))
                        .foregroundColor(PhoneTheme.receiptInk)

                    Spacer()

                    let net = position.netPnl
                    let isGain = net >= 0
                    Text(formatPnl(net))
                        .font(PhoneFont.ui(12, weight: .bold, monospacedDigit: true))
                        .foregroundColor(PhoneTheme.pnlColor(isGain: isGain))
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.string(.exchangePositionOpen, language: currentLanguage))
                        .font(PhoneFont.paper(10.5, weight: .semibold))
                        .foregroundColor(PhoneTheme.receiptInk)

                    Spacer()

                    Text(formatDate(position.openTime))
                        .font(PhoneFont.ui(9.5, monospacedDigit: true))
                        .foregroundColor(PhoneTheme.receiptInk.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            ReceiptShape()
                .fill(PhoneTheme.receipt)
                .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
        )
        .overlay(
            // Tape Strip
            Rectangle()
                .fill(PhoneTheme.tape)
                .frame(width: 32, height: 8)
                .rotationEffect(.degrees(-1.5))
                .offset(y: -4),
            alignment: .top
        )
        .padding(.vertical, 4)
        .contextMenu {
            Button(L10n.string(.exchangeSharePosition, language: currentLanguage)) {
                if let image = renderForShare() { ImageShare.presentShareSheet(for: image, scale: Self.shareRenderScale) }
            }
            Button(L10n.string(.journalCopyImage, language: currentLanguage)) {
                if let image = renderForShare() { ImageShare.copy(image, scale: Self.shareRenderScale) }
            }
        }
    }

    /// Higher than the calendar page's 2x: the receipt is a small card and
    /// chat apps recompress, so extra pixels keep the print crisp.
    private static let shareRenderScale: CGFloat = 3

    /// Renders the receipt for sharing / copying. ImageRenderer builds an
    /// isolated tree, so the language is passed explicitly rather than relying
    /// on the environment.
    private func renderForShare() -> CGImage? {
        let renderer = ImageRenderer(
            content: PhoneReceiptCard(position: position, language: currentLanguage)
        )
        renderer.scale = Self.shareRenderScale
        return renderer.cgImage
    }

    private var dateRangeText: String {
        let open = formatDate(position.openTime)
        if let close = position.closeTime {
            return "\(open) → \(formatDate(close))"
        }
        return open
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func formatPrice(_ price: Double) -> String {
        if price >= 1000 {
            return String(format: "%.1f", price)
        } else if price >= 1 {
            return String(format: "%.2f", price)
        } else {
            return String(format: "%.4f", price)
        }
    }

    private func formatPnl(_ pnl: Double) -> String {
        let prefix = pnl >= 0 ? "+" : ""
        let quote = position.quoteAsset.map { " \($0)" } ?? " USDT"
        return "\(prefix)\(String(format: "%.2f", pnl))\(quote)"
    }
}
