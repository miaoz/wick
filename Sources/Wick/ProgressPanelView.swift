import AppKit
import SwiftUI

private enum PanelViewLayout {
    static let width: CGFloat = 360
    static let outerPadding: CGFloat = 12
    static let contentPadding: CGFloat = 18
}

struct ProgressPanelView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let items = TimeProgressCalculator.allProgress(at: context.date)
            let theme = PanelTheme.forColorScheme(colorScheme)

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: theme.backgroundColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [theme.ambientGlow, theme.ambientGlow.opacity(0)],
                                    center: .center,
                                    startRadius: 4,
                                    endRadius: 180
                                )
                            )
                            .frame(width: 220, height: 220)
                            .offset(x: -40, y: -70)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(theme.panelStroke, lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 18) {
                    header(date: context.date, theme: theme)

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, theme.dividerAccent, Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)

                    VStack(spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            MetricProgressCard(
                                item: item,
                                theme: theme.metricTheme(for: index),
                                panelTheme: theme
                            )
                        }
                    }
                }
                .padding(PanelViewLayout.contentPadding)
            }
            .padding(PanelViewLayout.outerPadding)
            .frame(width: PanelViewLayout.width)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func header(date: Date, theme: PanelTheme) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: theme.iconGradient,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 46, height: 46)
                    .shadow(color: theme.iconGlow, radius: 12, y: 4)

                Text(theme.icon)
                    .font(.system(size: 23))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(theme.title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primaryText)

                Text("一寸光阴一寸金。")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)

                Text(date.formatted(.dateTime.year().month().day().weekday(.abbreviated).hour().minute()))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.tertiaryText)
            }

            Spacer(minLength: 8)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.primaryText.opacity(0.76))
                    .frame(width: 28, height: 28)
                    .background(theme.controlBackground, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(theme.controlBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help("退出")
        }
    }
}

private struct MetricProgressCard: View {
    let item: TimeProgress
    let theme: MetricTheme
    let panelTheme: PanelTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
                Text(item.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(theme.primary.opacity(0.14), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(theme.primary.opacity(0.18), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.subtitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(panelTheme.primaryText)
                    Text(item.remainingText)
                        .font(.caption)
                        .foregroundStyle(panelTheme.secondaryText)
                }

                Spacer(minLength: 8)

                Text(item.percentageText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(panelTheme.primaryText)
            }

            WickProgressBar(value: item.fractionRemaining, theme: theme)
                .frame(height: 12)

            HStack {
                Text(item.endText)
                Spacer()
                Text(progressLabel(for: item.fractionRemaining))
            }
            .font(.caption2)
            .foregroundStyle(panelTheme.tertiaryText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [theme.cardTop, theme.cardBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(panelTheme.cardBorder, lineWidth: 1)
        }
        .shadow(color: theme.glow, radius: 10, y: 4)
    }

    private func progressLabel(for value: Double) -> String {
        if value < 0.15 {
            return "所剩不多"
        }

        if value < 0.4 {
            return "正在燃尽"
        }

        return "余量充足"
    }
}

private struct WickProgressBar: View {
    let value: Double
    let theme: MetricTheme

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, min(proxy.size.width, proxy.size.width * value))

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(theme.trackFill)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(theme.trackStroke, lineWidth: 1)
                    }

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [theme.primary, theme.secondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width)
                    .shadow(color: theme.glow, radius: 8, y: 2)
                    .overlay(alignment: .trailing) {
                        Circle()
                            .fill(theme.spark.opacity(width > 10 ? 1 : 0))
                            .frame(width: 8, height: 8)
                            .blur(radius: 0.4)
                            .padding(.trailing, 2)
                    }
            }
        }
    }
}

private enum PanelTheme {
    case candlelight
    case midnight

    static func forColorScheme(_ colorScheme: ColorScheme) -> PanelTheme {
        switch colorScheme {
        case .light:
            return .candlelight
        case .dark:
            return .midnight
        @unknown default:
            return .midnight
        }
    }

    var title: String {
        switch self {
        case .candlelight:
            return "烛火进度"
        case .midnight:
            return "夜幕进度"
        }
    }

    var icon: String {
        switch self {
        case .candlelight:
            return "🕯️"
        case .midnight:
            return "🌙"
        }
    }

    var backgroundColors: [Color] {
        switch self {
        case .candlelight:
            return [Color(hex: 0xFFF7ED), Color(hex: 0xF8EAD8), Color(hex: 0xF3E2D2)]
        case .midnight:
            return [Color(hex: 0x0E1320), Color(hex: 0x131A2B), Color(hex: 0x0D111B)]
        }
    }

    var ambientGlow: Color {
        switch self {
        case .candlelight:
            return Color(hex: 0xFFBE66, opacity: 0.24)
        case .midnight:
            return Color(hex: 0x6CA6FF, opacity: 0.18)
        }
    }

    var panelStroke: Color {
        switch self {
        case .candlelight:
            return Color(hex: 0xDDBB93, opacity: 0.65)
        case .midnight:
            return Color.white.opacity(0.10)
        }
    }

    var dividerAccent: Color {
        switch self {
        case .candlelight:
            return Color(hex: 0xD98F44, opacity: 0.55)
        case .midnight:
            return Color(hex: 0x8AB4FF, opacity: 0.42)
        }
    }

    var iconGradient: [Color] {
        switch self {
        case .candlelight:
            return [Color(hex: 0xFFD78A), Color(hex: 0xE69943)]
        case .midnight:
            return [Color(hex: 0x9BB9FF), Color(hex: 0x4C68C7)]
        }
    }

    var iconGlow: Color {
        switch self {
        case .candlelight:
            return Color(hex: 0xF7C673, opacity: 0.26)
        case .midnight:
            return Color(hex: 0x7FA9FF, opacity: 0.24)
        }
    }

    var primaryText: Color {
        switch self {
        case .candlelight:
            return Color(hex: 0x2F241B)
        case .midnight:
            return Color.white.opacity(0.96)
        }
    }

    var secondaryText: Color {
        switch self {
        case .candlelight:
            return Color(hex: 0x6D5A49)
        case .midnight:
            return Color.white.opacity(0.64)
        }
    }

    var tertiaryText: Color {
        switch self {
        case .candlelight:
            return Color(hex: 0x917C67)
        case .midnight:
            return Color.white.opacity(0.50)
        }
    }

    var controlBackground: Color {
        switch self {
        case .candlelight:
            return Color.white.opacity(0.55)
        case .midnight:
            return Color.white.opacity(0.05)
        }
    }

    var controlBorder: Color {
        switch self {
        case .candlelight:
            return Color(hex: 0xD7B28A, opacity: 0.75)
        case .midnight:
            return Color.white.opacity(0.10)
        }
    }

    var cardBorder: Color {
        switch self {
        case .candlelight:
            return Color(hex: 0xDFC6A9, opacity: 0.65)
        case .midnight:
            return Color.white.opacity(0.07)
        }
    }

    func metricTheme(for index: Int) -> MetricTheme {
        let themes: [MetricTheme]

        switch self {
        case .candlelight:
            themes = [
                MetricTheme(
                    primary: Color(hex: 0xE2903A),
                    secondary: Color(hex: 0xF7B261),
                    glow: Color(hex: 0xE2903A, opacity: 0.18),
                    cardTop: Color(hex: 0xFFF8F0),
                    cardBottom: Color(hex: 0xF7E8D8),
                    trackFill: Color.black.opacity(0.06),
                    trackStroke: Color.black.opacity(0.05),
                    spark: Color.white.opacity(0.90)
                ),
                MetricTheme(
                    primary: Color(hex: 0x4B8EF4),
                    secondary: Color(hex: 0x82B7FF),
                    glow: Color(hex: 0x4B8EF4, opacity: 0.14),
                    cardTop: Color(hex: 0xF4F8FF),
                    cardBottom: Color(hex: 0xE5EEF9),
                    trackFill: Color.black.opacity(0.06),
                    trackStroke: Color.black.opacity(0.05),
                    spark: Color.white.opacity(0.92)
                ),
                MetricTheme(
                    primary: Color(hex: 0x8E6CE6),
                    secondary: Color(hex: 0xC2A6FF),
                    glow: Color(hex: 0x8E6CE6, opacity: 0.14),
                    cardTop: Color(hex: 0xF7F3FF),
                    cardBottom: Color(hex: 0xECE4FA),
                    trackFill: Color.black.opacity(0.06),
                    trackStroke: Color.black.opacity(0.05),
                    spark: Color.white.opacity(0.92)
                ),
                MetricTheme(
                    primary: Color(hex: 0x2DA37C),
                    secondary: Color(hex: 0x80D8BA),
                    glow: Color(hex: 0x2DA37C, opacity: 0.14),
                    cardTop: Color(hex: 0xF2FCF8),
                    cardBottom: Color(hex: 0xE0F0E8),
                    trackFill: Color.black.opacity(0.06),
                    trackStroke: Color.black.opacity(0.05),
                    spark: Color.white.opacity(0.92)
                )
            ]
        case .midnight:
            themes = [
                MetricTheme(
                    primary: Color(hex: 0x9BB6FF),
                    secondary: Color(hex: 0x6B86F5),
                    glow: Color(hex: 0x7D96FF, opacity: 0.18),
                    cardTop: Color(hex: 0x171F33, opacity: 0.88),
                    cardBottom: Color(hex: 0x101727, opacity: 0.94),
                    trackFill: Color.white.opacity(0.08),
                    trackStroke: Color.white.opacity(0.05),
                    spark: Color.white.opacity(0.32)
                ),
                MetricTheme(
                    primary: Color(hex: 0x79D4FF),
                    secondary: Color(hex: 0x3C9DE8),
                    glow: Color(hex: 0x79D4FF, opacity: 0.16),
                    cardTop: Color(hex: 0x132332, opacity: 0.88),
                    cardBottom: Color(hex: 0x101A28, opacity: 0.94),
                    trackFill: Color.white.opacity(0.08),
                    trackStroke: Color.white.opacity(0.05),
                    spark: Color.white.opacity(0.32)
                ),
                MetricTheme(
                    primary: Color(hex: 0xB9A7FF),
                    secondary: Color(hex: 0x7A67E6),
                    glow: Color(hex: 0xB9A7FF, opacity: 0.16),
                    cardTop: Color(hex: 0x1A1E38, opacity: 0.88),
                    cardBottom: Color(hex: 0x111427, opacity: 0.94),
                    trackFill: Color.white.opacity(0.08),
                    trackStroke: Color.white.opacity(0.05),
                    spark: Color.white.opacity(0.32)
                ),
                MetricTheme(
                    primary: Color(hex: 0x8AE0D0),
                    secondary: Color(hex: 0x3CB7A6),
                    glow: Color(hex: 0x8AE0D0, opacity: 0.15),
                    cardTop: Color(hex: 0x142627, opacity: 0.88),
                    cardBottom: Color(hex: 0x10191B, opacity: 0.94),
                    trackFill: Color.white.opacity(0.08),
                    trackStroke: Color.white.opacity(0.05),
                    spark: Color.white.opacity(0.32)
                )
            ]
        }

        return themes[index % themes.count]
    }
}

private struct MetricTheme {
    let primary: Color
    let secondary: Color
    let glow: Color
    let cardTop: Color
    let cardBottom: Color
    let trackFill: Color
    let trackStroke: Color
    let spark: Color
}

private extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
