import AppKit
import SwiftUI

private enum PanelViewLayout {
    static let width: CGFloat = 360
    static let outerPadding: CGFloat = 12
    static let contentPadding: CGFloat = 18
}

struct ProgressPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @State private var showsSettings = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let theme = PanelTheme.forColorScheme(colorScheme)
            let language = settings.language

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
                    if showsSettings {
                        settingsHeader(theme: theme, language: language)
                        settingsDivider(theme: theme)
                        SettingsContentView(theme: theme, language: language)
                    } else {
                        progressHeader(date: context.date, theme: theme, language: language)
                        settingsDivider(theme: theme)

                        let items = TimeProgressCalculator.allProgress(
                            at: context.date,
                            language: language
                        )

                        VStack(spacing: 12) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                MetricProgressCard(
                                    item: item,
                                    theme: theme.metricTheme(for: index),
                                    panelTheme: theme,
                                    language: language
                                )
                            }
                        }
                    }
                }
                .padding(PanelViewLayout.contentPadding)
            }
            .padding(PanelViewLayout.outerPadding)
            .frame(width: PanelViewLayout.width)
            .fixedSize(horizontal: false, vertical: true)
            .animation(.easeInOut(duration: 0.18), value: showsSettings)
            .animation(.easeInOut(duration: 0.18), value: settings.language)
            .animation(.easeInOut(duration: 0.18), value: settings.appearance)
        }
    }

    @ViewBuilder
    private func progressHeader(date: Date, theme: PanelTheme, language: AppLanguage) -> some View {
        HStack(alignment: .top, spacing: 14) {
            themeIcon(theme: theme)

            VStack(alignment: .leading, spacing: 4) {
                Text(theme.title(language: language))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primaryText)

                Text(L10n.string(.motto, language: language))
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)

                Text(
                    date.formatted(
                        .dateTime
                        .year()
                        .month()
                        .day()
                        .weekday(.abbreviated)
                        .hour()
                        .minute()
                        .locale(language.locale)
                    )
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.tertiaryText)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                headerButton(
                    systemName: "gearshape",
                    help: L10n.string(.settings, language: language),
                    theme: theme
                ) {
                    showsSettings = true
                }

                headerButton(
                    systemName: "power",
                    help: L10n.string(.quit, language: language),
                    theme: theme
                ) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    @ViewBuilder
    private func settingsHeader(theme: PanelTheme, language: AppLanguage) -> some View {
        HStack(alignment: .center, spacing: 14) {
            themeIcon(theme: theme)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(.settingsTitle, language: language))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primaryText)

                Text(theme.title(language: language))
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: 8)

            headerButton(
                systemName: "chevron.left",
                help: L10n.string(.back, language: language),
                theme: theme
            ) {
                showsSettings = false
            }
        }
    }

    private func themeIcon(theme: PanelTheme) -> some View {
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
    }

    private func settingsDivider(theme: PanelTheme) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.clear, theme.dividerAccent, Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    private func headerButton(
        systemName: String,
        help: String,
        theme: PanelTheme,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
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
        .help(help)
    }
}

private struct SettingsContentView: View {
    @EnvironmentObject private var settings: AppSettings

    let theme: PanelTheme
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 12) {
            settingsSection(
                title: L10n.string(.language, language: language)
            ) {
                HStack(spacing: 8) {
                    ForEach(AppLanguage.allCases) { option in
                        settingsOptionButton(
                            title: option.displayName,
                            isSelected: settings.language == option
                        ) {
                            settings.language = option
                        }
                    }
                }
            }

            settingsSection(
                title: L10n.string(.appearance, language: language)
            ) {
                VStack(spacing: 8) {
                    ForEach(AppAppearance.allCases) { option in
                        settingsOptionButton(
                            title: option.displayName(language: language),
                            isSelected: settings.appearance == option,
                            expands: true
                        ) {
                            settings.appearance = option
                        }
                    }
                }
            }
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.6)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: theme.settingsCardColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.cardBorder, lineWidth: 1)
        }
    }

    private func settingsOptionButton(
        title: String,
        isSelected: Bool,
        expands: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)

                if expands {
                    Spacer(minLength: 8)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.selectionAccent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? theme.selectionBackground : theme.controlBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme.selectionAccent.opacity(0.45) : theme.controlBorder,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MetricProgressCard: View {
    let item: TimeProgress
    let theme: MetricTheme
    let panelTheme: PanelTheme
    let language: AppLanguage

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
            return L10n.string(.progressLow, language: language)
        }

        if value < 0.4 {
            return L10n.string(.progressBurning, language: language)
        }

        return L10n.string(.progressPlenty, language: language)
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

    func title(language: AppLanguage) -> String {
        switch self {
        case .candlelight:
            return L10n.string(.themeCandlelight, language: language)
        case .midnight:
            return L10n.string(.themeMidnight, language: language)
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

    var settingsCardColors: [Color] {
        switch self {
        case .candlelight:
            return [Color(hex: 0xFFF8F0), Color(hex: 0xF7E8D8)]
        case .midnight:
            return [Color(hex: 0x171F33, opacity: 0.88), Color(hex: 0x101727, opacity: 0.94)]
        }
    }

    var selectionBackground: Color {
        switch self {
        case .candlelight:
            return Color(hex: 0xFFE8C8, opacity: 0.9)
        case .midnight:
            return Color.white.opacity(0.10)
        }
    }

    var selectionAccent: Color {
        switch self {
        case .candlelight:
            return Color(hex: 0xE2903A)
        case .midnight:
            return Color(hex: 0x9BB6FF)
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
