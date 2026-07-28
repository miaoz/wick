import AppKit
import SwiftUI

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
    var style: Style = .rounded
    var onChange: (() -> Void)?

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
        field.textColor = .labelColor
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
    }
}

// MARK: - Multi-line

/// AppKit-backed multi-line editor that preserves IME marked text across SwiftUI redraws.
struct IMESafeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var onChange: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = scrollView.documentView as! NSTextView
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

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }

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

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newValue = textView.string
            guard parent.text != newValue else { return }
            parent.text = newValue
            parent.onChange?()
        }
    }
}
