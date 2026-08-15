import SwiftUI
import UIKit
import WickCalendarKit
import WickSync

/// Full-screen host for the shared `WickCalendarKit` trading calendar on iPhone.
/// The pad is laid out like a normal app: the cream page fills the display
/// edge-to-edge (stapled binding across the notch row, printed matter clear of
/// the Dynamic Island and home indicator), and the layout scales with the
/// device so it reads the same from SE to Pro Max. A torn sheet is presented as
/// a full-screen overlay (the iOS counterpart of the macOS click-through
/// overlay window) that falls off the bottom of the display.
struct CalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tornPiece: FallingPage?

    private let language = AppLanguage.system

    var body: some View {
        GeometryReader { geo in
            // A GeometryReader under .ignoresSafeArea() reports ZERO safe-area
            // insets on some OS versions, which would shove the printed frame
            // under the Dynamic Island - ask the key window directly instead.
            let safe = keyWindowSafeInsets
            let layout = PaperLayout.fullScreen(
                size: geo.size,
                safeTop: min(max(safe.top, geo.safeAreaInsets.top), 140),
                safeBottom: min(max(safe.bottom, geo.safeAreaInsets.bottom), 60)
            )
            ZStack {
                // The paper is the app - no wall behind it, no scaling: the pad
                // is composed directly at screen size.
                TradingCalendarTheme.paper
                if geo.size.width > 1, geo.size.height > 1 {
                    TradingCalendarRootView(
                        language: language,
                        onClose: { dismiss() },
                        onPageTorn: { tornPiece = $0 },
                        layout: layout
                    )
                    // The solver/scene state is sized when the pad is inserted;
                    // the cover's first layout proposal can be zero-size, so key
                    // the whole pad to the final metrics and let it rebuild once
                    // they settle.
                    .id(layout)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .overlay {
                if let tornPiece {
                    iOSFallingPageOverlay(piece: tornPiece) {
                        self.tornPiece = nil
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private var keyWindowSafeInsets: (top: CGFloat, bottom: CGFloat) {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
        if let insets = keyWindow?.safeAreaInsets {
            return (insets.top, insets.bottom)
        }
        return (0, 0)
    }
}

/// A torn page falling off the bottom of the screen, in a full-screen overlay.
private struct iOSFallingPageOverlay: View {
    let piece: FallingPage
    let onFinished: () -> Void

    var body: some View {
        GeometryReader { geo in
            // From the page's resting spot to fully past the screen bottom.
            // headroom cancels FallingPageView's own top padding so the torn
            // edge starts exactly on the pad's tear line (the pad sits at the
            // very top of a full-screen layout, so there is no air above it).
            let fallDistance = geo.size.height
                - piece.layout.blockTopPad
                - piece.layout.pageTopInset
                + 60
            FallingPageView(page: piece, fallDistance: max(fallDistance, 400), headroom: 14)
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
