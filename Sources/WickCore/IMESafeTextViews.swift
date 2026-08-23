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
@MainActor
struct IMESafeTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: NSFont = AppFont.paperNSFont(NSFont.systemFontSize)
    var textColor: NSColor = .labelColor
    var style: Style = .rounded
    var onChange: (() -> Void)?
    /// Handles ⌘V when the pasteboard carries an image (text pastes use the default path).
    var onPasteImage: (() -> Bool)?
    /// Steal first responder once after the field is installed (click-to-edit).
    var becomeFirstResponder: Bool = false

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
        context.coordinator.appliedStyle = style
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
        if context.coordinator.appliedStyle != style {
            applyStyle(field)
            context.coordinator.appliedStyle = style
        }
        if becomeFirstResponder, !context.coordinator.didBecomeFirstResponder {
            context.coordinator.didBecomeFirstResponder = true
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
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
        var appliedStyle: IMESafeTextField.Style?
        var didBecomeFirstResponder = false

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
            guard selector == NSSelectorFromString("noop:") else { return false }
            return MainActor.assumeIsolated {
                guard let event = NSApp.currentEvent,
                      event.type == .keyDown,
                      event.modifierFlags.contains(.command),
                      event.charactersIgnoringModifiers?.lowercased() == "v"
                else { return false }
                return true
            }
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

/// Scroll view that reports a fitted content height to SwiftUI via
/// `intrinsicContentSize`, so journal item bodies can grow with text instead
/// of sitting in a fixed-height box.
final class AutoHeightScrollView: NSScrollView {
    var fittedHeight: CGFloat = 48 {
        didSet {
            guard abs(oldValue - fittedHeight) > 0.5 else { return }
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: fittedHeight)
    }
}

/// AppKit-backed multi-line editor that preserves IME marked text across SwiftUI redraws.
///
/// Height tracks the laid-out text (clamped to `minHeight`…`maxHeight`). When
/// content exceeds `maxHeight`, a vertical scroller appears; otherwise the
/// outer journal timeline scrolls as one continuous surface.
@MainActor
struct IMESafeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = AppFont.paperNSFont(NSFont.systemFontSize)
    var lineSpacing: CGFloat? = nil
    /// Empty / short bodies still get a couple of lines of breathing room.
    var minHeight: CGFloat = 48
    /// Soft cap; `nil` grows without limit (preferred for timeline cards).
    var maxHeight: CGFloat? = nil
    var onChange: (() -> Void)?
    /// Handles ⌘V when the pasteboard carries an image (text pastes use the default path).
    var onPasteImage: (() -> Bool)?
    /// Steal first responder once after the editor is installed (click-to-edit).
    var becomeFirstResponder: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AutoHeightScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? (nsView.bounds.width > 1 ? nsView.bounds.width : 400)
        let effectiveWidth = max(width, 100)
        let height = context.coordinator.calculateHeight(for: effectiveWidth)
        return CGSize(width: proposal.width ?? NSView.noIntrinsicMetric, height: height)
    }

    func makeNSView(context: Context) -> AutoHeightScrollView {
        let textView = IMETextView(frame: NSRect(x: 0, y: 0, width: 400, height: minHeight))
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = font
        let effectiveLineSpacing = lineSpacing ?? AppFont.adaptiveLineSpacing(for: font)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = effectiveLineSpacing
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]
        if !text.isEmpty, let textStorage = textView.textStorage {
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: textStorage.length))
        }
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
            width: 400,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.onPasteImage = onPasteImage

        let scrollView = AutoHeightScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        let initialHeight = context.coordinator.calculateHeight(for: 400)
        scrollView.fittedHeight = initialHeight

        context.coordinator.trackClipWidth(of: scrollView, textView: textView)
        // Do not measure here: clip width is still 0 during `makeNSView`,
        // and `setFrameSize` posts frame-change notifications that re-enter
        // SwiftUI layout. On macOS 13 a timeline of many editors hangs the
        // main thread in that loop. `updateNSView` measures once width is real.
        if becomeFirstResponder {
            context.coordinator.didBecomeFirstResponder = true
            DispatchQueue.main.async { [weak textView] in
                textView?.window?.makeFirstResponder(textView)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: AutoHeightScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.scrollView = scrollView
        guard let textView = scrollView.documentView as? IMETextView else { return }
        textView.onPasteImage = onPasteImage

        let effectiveLineSpacing = lineSpacing ?? AppFont.adaptiveLineSpacing(for: font)
        let currentSpacing = textView.defaultParagraphStyle?.lineSpacing ?? 0
        let spacingChanged = abs(currentSpacing - effectiveLineSpacing) > 0.1
        let fontChanged = textView.font != font

        if fontChanged || spacingChanged {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = effectiveLineSpacing
            textView.defaultParagraphStyle = paragraphStyle
            textView.typingAttributes[.font] = font
            textView.typingAttributes[.paragraphStyle] = paragraphStyle
            if fontChanged {
                textView.font = font
            }
            if let textStorage = textView.textStorage, textStorage.length > 0 {
                textStorage.addAttributes([
                    .font: font,
                    .paragraphStyle: paragraphStyle,
                ], range: NSRange(location: 0, length: textStorage.length))
            }
        }

        if textView.textColor != NSColor.labelColor {
            textView.textColor = .labelColor
        }

        if textView.hasMarkedText() {
            // Still refresh height from current layout; do not rewrite the string.
            context.coordinator.recomputeHeight()
            return
        }

        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            if let paragraphStyle = textView.defaultParagraphStyle,
               let textStorage = textView.textStorage,
               textStorage.length > 0
            {
                textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: textStorage.length))
            }
            let length = (text as NSString).length
            let location = min(selected.location, length)
            let maxLength = max(0, length - location)
            let restoredLength = min(selected.length, maxLength)
            textView.setSelectedRange(NSRange(location: location, length: restoredLength))
        }

        if becomeFirstResponder, !context.coordinator.didBecomeFirstResponder {
            context.coordinator.didBecomeFirstResponder = true
            DispatchQueue.main.async { [weak textView] in
                textView?.window?.makeFirstResponder(textView)
            }
        }

        context.coordinator.recomputeHeight()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IMESafeTextEditor
        weak var textView: NSTextView?
        weak var scrollView: AutoHeightScrollView?
        private var isRecomputingHeight = false
        var didBecomeFirstResponder = false
        private var lastHeightWidth: CGFloat = -1
        private var lastHeightTextHash: Int = 0
        private var lastHeightTextCount: Int = -1
        private var lastHeightMin: CGFloat = -1
        private var lastHeightMax: CGFloat = -1

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
            // Frame changes (initial layout / window resize) also affect wrap width.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipFrameDidChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: scrollView.contentView
            )
            scrollView.contentView.postsFrameChangedNotifications = true
            syncWidth(scrollView.contentView, textView: textView)
        }

        @objc private func clipBoundsDidChange(_ note: Notification) {
            guard let clipView = note.object as? NSClipView, let textView else { return }
            let widthChanged = syncWidth(clipView, textView: textView)
            if widthChanged {
                recomputeHeight()
            }
        }

        @objc private func clipFrameDidChange(_ note: Notification) {
            guard let clipView = note.object as? NSClipView, let textView else { return }
            let widthChanged = syncWidth(clipView, textView: textView)
            // Height-only frame changes are usually our own `setFrameSize`
            // from `recomputeHeight`; measuring again re-enters AppKit layout
            // (seen as a 79s hang on macOS 13).
            if widthChanged {
                recomputeHeight()
            }
        }

        @discardableResult
        private func syncWidth(_ clipView: NSClipView, textView: NSTextView) -> Bool {
            let width = clipView.bounds.width
            guard width > 0, abs(textView.frame.width - width) > 0.5 else { return false }
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
            textView.textContainer?.containerSize = NSSize(
                width: width,
                height: CGFloat.greatestFiniteMagnitude
            )
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newValue = textView.string
            if parent.text != newValue {
                parent.text = newValue
                parent.onChange?()
            }
            recomputeHeight()
        }

        func calculateHeight(for width: CGFloat) -> CGFloat {
            guard let textView else { return parent.minHeight }

            let effectiveWidth = max(width, 100)
            if abs(textView.frame.width - effectiveWidth) > 0.5 {
                textView.setFrameSize(NSSize(width: effectiveWidth, height: textView.frame.height))
            }
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(
                width: effectiveWidth,
                height: CGFloat.greatestFiniteMagnitude
            )

            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else {
                return parent.minHeight
            }

            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer)
            var usedHeight = used.height
            if layoutManager.extraLineFragmentRect.height > 0 {
                usedHeight = max(usedHeight, layoutManager.extraLineFragmentRect.maxY)
            }
            let raw = ceil(usedHeight + textView.textContainerInset.height * 2 + 4)

            let lineHeight: CGFloat = {
                if let font = textView.font {
                    let spacing = textView.defaultParagraphStyle?.lineSpacing ?? 0
                    return ceil(layoutManager.defaultLineHeight(for: font) + spacing)
                }
                return 18
            }()
            let contentHeight = max(raw, lineHeight + 4)
            let minH = parent.minHeight
            let uncapped = max(contentHeight, minH)

            if let maxH = parent.maxHeight, uncapped > maxH {
                return maxH
            }
            return uncapped
        }

        /// Measure laid-out text and push height into the scroll view's
        /// intrinsic size so SwiftUI reflows the card.
        func recomputeHeight() {
            guard !isRecomputingHeight else { return }
            guard let textView, let scrollView else { return }

            let width = scrollView.contentView.bounds.width
            // Width 0 yields a huge usedRect (one glyph per line). Leave the
            // min-height placeholder until the clip view has a real width.
            guard width > 1 else { return }

            let text = textView.string
            let maxH = parent.maxHeight ?? -1
            if abs(lastHeightWidth - width) < 0.5,
               lastHeightTextCount == text.count,
               lastHeightTextHash == text.hashValue,
               lastHeightMin == parent.minHeight,
               lastHeightMax == maxH
            {
                return
            }
            lastHeightWidth = width
            lastHeightTextCount = text.count
            lastHeightTextHash = text.hashValue
            lastHeightMin = parent.minHeight
            lastHeightMax = maxH

            isRecomputingHeight = true
            defer { isRecomputingHeight = false }

            let calculated = calculateHeight(for: width)

            if let maxH = parent.maxHeight, calculated >= maxH {
                scrollView.hasVerticalScroller = true
                scrollView.fittedHeight = maxH
                // Let the text view grow inside the scroll view when capped.
                let docHeight = max(calculated, maxH)
                if abs(textView.frame.height - docHeight) > 0.5 {
                    textView.setFrameSize(NSSize(width: width, height: docHeight))
                }
            } else {
                scrollView.hasVerticalScroller = false
                scrollView.fittedHeight = calculated
                // Match document height to the fitted viewport so nested
                // scrolling does not steal gestures from the timeline.
                if abs(textView.frame.height - calculated) > 0.5 {
                    textView.setFrameSize(NSSize(width: width, height: calculated))
                }
            }
        }
    }
}
