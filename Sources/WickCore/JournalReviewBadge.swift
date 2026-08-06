import SwiftUI
import WickSync

// MARK: - Review badge

/// Verdict mark for a reviewed journal item. `.seal` is the paper-journal
/// "stamp" shown on editor cards (double ring, slight tilt); `.mini` is the
/// plain glyph used in sidebar rows.
struct JournalReviewBadge: View {
    enum Style {
        case seal
        case mini
    }

    @Environment(\.wickPalette) private var palette

    let verdict: JournalReviewVerdict
    var style: Style = .seal
    /// Seal diameter in points; ring widths and glyph scale with it.
    var size: CGFloat = 34

    var body: some View {
        switch style {
        case .seal:
            seal
        case .mini:
            glyph
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
        }
    }

    private var seal: some View {
        ZStack {
            Circle()
                .strokeBorder(color.opacity(0.85), lineWidth: size * 0.047)
            Circle()
                .strokeBorder(color.opacity(0.45), lineWidth: size * 0.029)
                .padding(size * 0.1)
            glyph
                .font(.system(size: size * 0.44, weight: .heavy))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-8))
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private var glyph: Image {
        switch verdict {
        case .correct: return Image(systemName: "checkmark")
        case .wrong: return Image(systemName: "xmark")
        }
    }

    private var color: Color {
        switch verdict {
        case .correct: return palette.reviewCorrect.color
        case .wrong: return palette.reviewWrong.color
        }
    }
}

extension JournalReviewVerdict {
    /// Glyph color for custom chrome (e.g. the verdict picker buttons).
    func color(in palette: WickPalette) -> Color {
        switch self {
        case .correct: return palette.reviewCorrect.color
        case .wrong: return palette.reviewWrong.color
        }
    }
}
