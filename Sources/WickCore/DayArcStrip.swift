import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Day arc strip
/// Signature day-arc element: a full-width 24h gradient of the day's four
/// phase accents. Shows a "now" marker when the edited entry is today.
struct DayArcStrip: View {
    let date: Date
    let language: AppLanguage

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.wickPalette) private var palette

    var body: some View {
        let isToday = Calendar.current.isDateInToday(date)

        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                LinearGradient(
                    stops: arcStops,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 4)

                if isToday {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .overlay {
                            Circle()
                                .strokeBorder(palette.accentText.color, lineWidth: 1.5)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                        .offset(x: nowMarkerX(width: proxy.size.width))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.string(.dayArcNowLabel, language: language)))
        .accessibilityHidden(!isToday)
    }

    /// Phase accents placed at their anchor hours across the 24h strip.
    private var arcStops: [Gradient.Stop] {
        [
            Gradient.Stop(color: phaseAccent(.night), location: 0),
            Gradient.Stop(color: phaseAccent(.dawn), location: DayPhase.dawn.anchorHour / 24),
            Gradient.Stop(color: phaseAccent(.day), location: DayPhase.day.anchorHour / 24),
            Gradient.Stop(color: phaseAccent(.dusk), location: DayPhase.dusk.anchorHour / 24),
            Gradient.Stop(color: phaseAccent(.night), location: DayPhase.night.anchorHour / 24),
            Gradient.Stop(color: phaseAccent(.night), location: 1),
        ]
    }

    private func phaseAccent(_ phase: DayPhase) -> Color {
        DayArcEngine.anchorPalette(phase, scheme: colorScheme).accent.color
    }

    private func nowMarkerX(width: CGFloat) -> CGFloat {
        let now = DayArcEngine.currentDate()
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        let hours = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        let fraction = min(max(hours / 24, 0), 1)
        return min(max(fraction * width - 3, 0), max(width - 6, 0))
    }
}
