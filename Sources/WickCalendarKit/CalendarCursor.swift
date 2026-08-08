import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Cursor feedback for the tear gesture — a no-op on iOS (no mouse cursor).
enum CalendarCursor {
    static func openHand() {
        #if os(macOS)
        NSCursor.openHand.set()
        #endif
    }

    static func arrow() {
        #if os(macOS)
        NSCursor.arrow.set()
        #endif
    }

    static func closedHand() {
        #if os(macOS)
        NSCursor.closedHand.set()
        #endif
    }
}

extension View {
    /// Switches the cursor to a hand while hovering the tear zone (macOS only).
    @ViewBuilder
    func calendarCursorOnHover() -> some View {
        #if os(macOS)
        onHover { inside in
            inside ? CalendarCursor.openHand() : CalendarCursor.arrow()
        }
        #else
        self
        #endif
    }
}
