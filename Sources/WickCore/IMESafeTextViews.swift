import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Composition detection

/// Shared helpers for Chinese / Japanese / Korean IME composition (marked text).
enum TextInputComposition {
    /// True when the current field editor or first-responder text view is mid-composition.
    @MainActor
    static var isActive: Bool {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            return textView.hasMarkedText()
        }
        if let fieldEditor = NSApp.keyWindow?.fieldEditor(false, for: nil) as? NSTextView {
            return fieldEditor.hasMarkedText()
        }
        return false
    }
}

// MARK: - Single-line

/// AppKit-backed single-line field that ignores external string writes while IME is composing.
struct IMESafeTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var textColor: NSColor = .labelColor
    var style: Style = .rounded
    var onChange: (() -> Void)?
    /// Handles ⌘V when the pasteboard carries an image (text pastes use the default path).
    var onPasteImage: (() -> Bool)?

    enum Style {
        case plain
        case rounded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.font = font
        field.placeholderString = placeholder
        field.textColor = textColor
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.maximumNumberOfLines = 1
        applyStyle(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self

        // While the field editor has marked text, never push SwiftUI state back in —
        // that is the usual cause of "swallowed" CJK characters.
        if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {
            return
        }

        if field.stringValue != text {
            field.stringValue = text
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }
        if field.font != font {
            field.font = font
        }
        if field.textColor != textColor {
            field.textColor = textColor
        }
        applyStyle(field)
    }

    private func applyStyle(_ field: NSTextField) {
        switch style {
        case .plain:
            field.isBordered = false
            field.isBezeled = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.backgroundColor = .clear
        case .rounded:
            field.isBordered = true
            field.isBezeled = true
            field.bezelStyle = .roundedBezel
            field.drawsBackground = true
            field.focusRingType = .default
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: IMESafeTextField

        init(_ parent: IMESafeTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let newValue = field.stringValue
            guard parent.text != newValue else { return }
            parent.text = newValue
            parent.onChange?()
        }

        /// Single-line fields edit through the shared field editor, so image
        /// pastes are intercepted at the command level. The standard key
        /// binding usually resolves ⌘V to `paste:`, but it can also arrive as
        /// `noop:` (e.g. synthetic events), so both shapes are recognized.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard Self.isPasteCommand(commandSelector),
                  let onPasteImage = parent.onPasteImage,
                  IMETextView.pasteboardHasImage(NSPasteboard.general)
            else { return false }
            return onPasteImage()
        }

        private static func isPasteCommand(_ selector: Selector) -> Bool {
            if selector == #selector(NSTextView.paste(_:)) {
                return true
            }
            guard selector == NSSelectorFromString("noop:"),
                  let event = NSApp.currentEvent,
                  event.type == .keyDown,
                  event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "v"
            else { return false }
            return true
        }
    }
}

// MARK: - Multi-line

/// Plain-text view that routes image pastes (screenshots, copied images,
/// image files) to a handler instead of dropping them on the floor.
final class IMETextView: NSTextView {
    /// Image-paste handler; returns true when the paste was consumed.
    var onPasteImage: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        // Route ⌘V explicitly: the key-binding path is unreliable for this
        // manually created text view, and image pastes need to reach `paste:`.
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v"
        {
            paste(event)
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        if let onPasteImage, Self.pasteboardHasImage(NSPasteboard.general), onPasteImage() {
            return
        }
        super.paste(sender)
    }

    /// Same two shapes `JournalStore.pasteImageFromClipboard` accepts.
    static func pasteboardHasImage(_ pasteboard: NSPasteboard) -> Bool {
        if NSImage(pasteboard: pasteboard) != nil {
            return true
        }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]) as? [URL]
        return urls?.isEmpty == false
    }
}

/// AppKit-backed multi-line editor that preserves IME marked text across SwiftUI redraws.
struct IMESafeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var onChange: (() -> Void)?
    /// Handles ⌘V when the pasteboard carries an image (text pastes use the default path).
    var onPasteImage: (() -> Bool)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = IMETextView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = font
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.onPasteImage = onPasteImage

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        context.coordinator.textView = textView
        context.coordinator.trackClipWidth(of: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? IMETextView else { return }
        textView.onPasteImage = onPasteImage

        if textView.hasMarkedText() {
            return
        }

        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            let location = min(selected.location, length)
            let maxLength = max(0, length - location)
            let restoredLength = min(selected.length, maxLength)
            textView.setSelectedRange(NSRange(location: location, length: restoredLength))
        }

        if textView.font != font {
            textView.font = font
        }
        if textView.textColor != NSColor.labelColor {
            textView.textColor = .labelColor
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IMESafeTextEditor
        weak var textView: NSTextView?

        init(_ parent: IMESafeTextEditor) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        /// Keeps the document text view exactly as wide as the clip view. A
        /// manually assembled scroll view does not propagate shrink resizes
        /// to the document view on macOS 13, so long lines overflowed instead
        /// of wrapping (the width never tracked the window size there).
        func trackClipWidth(of scrollView: NSScrollView, textView: NSTextView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            syncWidth(scrollView.contentView, textView: textView)
        }

        @objc private func clipBoundsDidChange(_ note: Notification) {
            guard let clipView = note.object as? NSClipView, let textView else { return }
            syncWidth(clipView, textView: textView)
        }

        private func syncWidth(_ clipView: NSClipView, textView: NSTextView) {
            let width = clipView.bounds.width
            guard width > 0, abs(textView.frame.width - width) > 0.5 else { return }
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newValue = textView.string
            guard parent.text != newValue else { return }
            parent.text = newValue
            parent.onChange?()
        }
    }
}
