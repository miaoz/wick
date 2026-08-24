import SwiftUI
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: Symbol + Side + Time Range
            HStack(alignment: .firstTextBaseline) {
                Text(position.symbol)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoneTheme.receiptInk)

                Text(position.side == .long ? "多 LONG" : "空 SHORT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(position.side == .long ? PhoneTheme.cinnabar : PhoneTheme.dai)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        (position.side == .long ? PhoneTheme.cinnabar : PhoneTheme.dai).opacity(0.12)
                    )
                    .cornerRadius(2)

                Spacer()

                Text(timeString(for: position.openTime))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(PhoneTheme.receiptInk.opacity(0.6))
            }

            // Dashed Divider
            Rectangle()
                .fill(PhoneTheme.receiptInk.opacity(0.15))
                .frame(height: 1)

            // Price & Size row
            HStack {
                Text("开仓 VWAP: \(formatPrice(position.entryPrice))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(PhoneTheme.receiptInk.opacity(0.8))

                Spacer()

                if let exitPrice = position.exitPrice {
                    Text("平仓: \(formatPrice(exitPrice))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(PhoneTheme.receiptInk.opacity(0.8))
                }
            }

            // Realized PnL Row
            HStack {
                Text("已实现盈亏")
                    .font(.system(size: 10.5, weight: .semibold, design: .serif))
                    .foregroundColor(PhoneTheme.receiptInk)

                Spacer()

                let pnl = position.realizedPnl
                let isGain = pnl >= 0
                Text(formatPnl(pnl))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(isGain ? PhoneTheme.cinnabar : PhoneTheme.dai)
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
    }

    private func timeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
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
        return "\(prefix)\(String(format: "%.2f", pnl)) USDT"
    }
}
