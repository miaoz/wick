import SwiftUI
import UIKit
import WickCalendarKit
import WickSync

/// UIKit-backed auto-height text view that disables internal scrolling
/// and expands to fit content height (clamped to `minHeight`...`maxHeight`).
final class AutoHeightUITextView: UITextView {
    var minHeight: CGFloat = 56
    var maxHeight: CGFloat? = nil

    override var intrinsicContentSize: CGSize {
        let targetWidth = bounds.width > 0 ? bounds.width : 320
        let size = sizeThatFits(CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
        let h = max(ceil(size.height), minHeight)
        if let maxH = maxHeight, h > maxH {
            return CGSize(width: UIView.noIntrinsicMetric, height: maxH)
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: h)
    }
}

/// UIKit-backed multi-line editor for iOS that preserves IME marked text
/// across SwiftUI redraws and auto-resizes to fit its content height without
/// an internal scrollbar.
@MainActor
struct PhoneTextEditor: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont = PhoneFont.paperUIFont(13.5)
    var lineSpacing: CGFloat? = nil
    /// Empty / short bodies get breathing room (default 56pt, ~2-3 lines).
    var minHeight: CGFloat = 56
    /// Optional cap; `nil` grows without limit so the outer day card scrolls continuously.
    var maxHeight: CGFloat? = nil
    var onChange: (() -> Void)?
    var becomeFirstResponder: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AutoHeightUITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? (uiView.bounds.width > 1 ? uiView.bounds.width : 320)
        let effectiveWidth = max(width, 50)
        let height = context.coordinator.calculateHeight(for: effectiveWidth, textView: uiView)
        return CGSize(width: proposal.width ?? UIView.noIntrinsicMetric, height: height)
    }

    func makeUIView(context: Context) -> AutoHeightUITextView {
        let textView = AutoHeightUITextView()
        textView.delegate = context.coordinator
        textView.minHeight = minHeight
        textView.maxHeight = maxHeight
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let effectiveLineSpacing = lineSpacing ?? PhoneFont.adaptiveLineSpacing(for: font)
        let textColor = resolvedTextColor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = effectiveLineSpacing

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: textColor,
        ]
        textView.typingAttributes = attrs
        textView.font = font
        textView.textColor = textColor

        if !text.isEmpty {
            textView.attributedText = NSAttributedString(string: text, attributes: attrs)
        }

        context.coordinator.textView = textView

        if becomeFirstResponder {
            context.coordinator.didBecomeFirstResponder = true
            DispatchQueue.main.async { [weak textView] in
                textView?.becomeFirstResponder()
            }
        }

        return textView
    }

    func updateUIView(_ uiView: AutoHeightUITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.textView = uiView
        uiView.minHeight = minHeight
        uiView.maxHeight = maxHeight

        let effectiveLineSpacing = lineSpacing ?? PhoneFont.adaptiveLineSpacing(for: font)
        let textColor = resolvedTextColor
        let fontChanged = uiView.font != font

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = effectiveLineSpacing
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: textColor,
        ]
        uiView.typingAttributes = attrs

        if fontChanged {
            uiView.font = font
        }
        uiView.textColor = textColor

        // Do not interrupt IME marked text composition
        if uiView.markedTextRange != nil {
            return
        }

        if uiView.text != text {
            let selectedRange = uiView.selectedRange
            uiView.attributedText = NSAttributedString(string: text, attributes: attrs)
            let newLength = (text as NSString).length
            let safeLocation = min(selectedRange.location, newLength)
            let safeLength = min(selectedRange.length, newLength - safeLocation)
            uiView.selectedRange = NSRange(location: safeLocation, length: safeLength)
            uiView.invalidateIntrinsicContentSize()
        }

        if becomeFirstResponder, !context.coordinator.didBecomeFirstResponder {
            context.coordinator.didBecomeFirstResponder = true
            DispatchQueue.main.async { [weak uiView] in
                uiView?.becomeFirstResponder()
            }
        }
    }

    private var resolvedTextColor: UIColor {
        UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return PhoneTheme.current(for: scheme).textPrimary.uiColor
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PhoneTextEditor
        weak var textView: UITextView?
        var didBecomeFirstResponder = false

        init(_ parent: PhoneTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            if parent.text != newText {
                parent.text = newText
                parent.onChange?()
            }
            textView.invalidateIntrinsicContentSize()
        }

        func calculateHeight(for width: CGFloat, textView: UITextView) -> CGFloat {
            let targetSize = CGSize(width: width, height: .greatestFiniteMagnitude)
            let fittingSize = textView.sizeThatFits(targetSize)
            let contentHeight = ceil(fittingSize.height)
            let minH = parent.minHeight
            let uncapped = max(contentHeight, minH)
            if let maxH = parent.maxHeight, uncapped > maxH {
                return maxH
            }
            return uncapped
        }
    }
}
