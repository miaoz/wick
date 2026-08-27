import CoreGraphics
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Delivers a rendered image through the system: clipboard copy or the native
/// share UI (`NSSharingServicePicker` on macOS, `UIActivityViewController` on
/// iOS). Shared by the tear-off calendar page and the exchange receipt cards.
@MainActor
public enum ImageShare {
    /// Copies the image to the general pasteboard. `scale` must be the render
    /// scale the bitmap was produced at — without it the receiving app treats
    /// every pixel as a point and the image looks blurry on Retina screens.
    public static func copy(_ image: CGImage, scale: CGFloat) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([platformImage(image, scale: scale)])
        #else
        UIPasteboard.general.image = platformImage(image, scale: scale)
        #endif
    }

    /// Presents the system share UI, anchored near the mouse on macOS and
    /// presented from the topmost view controller on iOS.
    public static func presentShareSheet(for image: CGImage, scale: CGFloat) {
        #if os(macOS)
        let picker = NSSharingServicePicker(items: [platformImage(image, scale: scale)])
        activePicker = picker // keep alive while its menu is open
        let mouse = NSEvent.mouseLocation
        guard let window = NSApp.keyWindow
            ?? NSApp.windows.first(where: { $0.isVisible && $0.frame.contains(mouse) })
            ?? NSApp.windows.first(where: { $0.isVisible }),
              let contentView = window.contentView else { return }
        var anchor = NSRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
        if window.frame.contains(mouse) {
            let inWindow = window.convertFromScreen(NSRect(origin: mouse, size: .zero)).origin
            let inView = contentView.convert(inWindow, from: nil)
            anchor = NSRect(x: inView.x - 1, y: inView.y - 1, width: 2, height: 2)
        }
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
        #else
        let activity = UIActivityViewController(
            activityItems: [platformImage(image, scale: scale)],
            applicationActivities: nil
        )
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        // iPad runs activity controllers as popovers and requires an anchor.
        if let popover = activity.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 1, height: 1)
        }
        presenter.present(activity, animated: true)
        #endif
    }

    #if os(macOS)
    private static var activePicker: NSSharingServicePicker?

    /// Logical point size = pixels / scale, so the bitmap reads as a Retina
    /// representation rather than a 1x image at an inflated point size.
    private static func platformImage(_ image: CGImage, scale: CGFloat) -> NSImage {
        NSImage(cgImage: image, size: NSSize(
            width: CGFloat(image.width) / scale,
            height: CGFloat(image.height) / scale
        ))
    }
    #else
    private static func platformImage(_ image: CGImage, scale: CGFloat) -> UIImage {
        UIImage(cgImage: image, scale: scale, orientation: .up)
    }
    #endif
}
