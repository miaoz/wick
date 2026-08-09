import SwiftUI
import WickCalendarKit
import WickSync

/// Full-screen host for the shared `WickCalendarKit` trading calendar on iOS.
///
/// The pad is drawn at its native design size and scaled to **fill the screen**:
/// on a portrait phone the taller dimension (screen height) wins, so the calendar
/// spans top-to-bottom while the 300pt page is narrow enough to still fit the width.
/// The scaled pad is centered and clipped to the screen so nothing spills off-edge,
/// and a torn page is presented as a full-screen overlay (the iOS counterpart of the
/// macOS click-through overlay window) that falls off the bottom of the display.
struct CalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tornPiece: FallingPage?

    private let language = AppLanguage.system

    var body: some View {
        GeometryReader { geo in
            let scale = max(
                geo.size.width / TradingCalendarGeometry.windowW,
                geo.size.height / TradingCalendarGeometry.windowH
            )
            ZStack {
                wall
                TradingCalendarRootView(
                    language: language,
                    onClose: { dismiss() },
                    onPageTorn: { tornPiece = $0 }
                )
                .scaleEffect(scale, anchor: .center)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .clipped()
            .overlay {
                if let tornPiece {
                    iOSFallingPageOverlay(piece: tornPiece, scale: scale) {
                        self.tornPiece = nil
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    /// The wall the pad hangs on (dark so the cream page and green ink pop).
    private var wall: some View {
        LinearGradient(
            colors: [
                Color(red: 0.16, green: 0.18, blue: 0.17),
                Color(red: 0.10, green: 0.12, blue: 0.11)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// A torn page falling off the bottom of the screen, in a full-screen overlay.
private struct iOSFallingPageOverlay: View {
    let piece: FallingPage
    let scale: CGFloat
    let onFinished: () -> Void

    var body: some View {
        GeometryReader { geo in
            // From the pad's resting spot to fully past the screen bottom.
            let fallDistance = geo.size.height
                - TradingCalendarGeometry.blockTopPad
                - TradingCalendarGeometry.pageTopInset
                + 60
            FallingPageView(page: piece, fallDistance: max(fallDistance, 400))
                .scaleEffect(scale, anchor: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                onFinished()
            }
        }
    }
}
