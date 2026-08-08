import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Trackpad haptics for the tear — a thin cross-platform shim.
@MainActor
enum Haptics {
    /// Small tick while the paper stretches / the events page flips.
    static func tick() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #else
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// The moment the page lets go.
    static func rip() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #else
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}
