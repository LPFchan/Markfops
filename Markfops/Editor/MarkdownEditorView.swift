import AppKit
import SwiftUI

// MARK: - NSTextView subclass

final class MarkdownNSTextView: NSTextView {
    var configuration: EditorConfiguration = .default {
        didSet { applyConfiguration() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyConfiguration()
    }

    private func applyConfiguration() {
        font = configuration.font
        backgroundColor = configuration.backgroundColor
        textColor = configuration.textColor
        textContainerInset = NSSize(
            width: configuration.editorInsets.left,
            height: configuration.editorInsets.top
        )
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = configuration.lineHeightMultiple
        defaultParagraphStyle = style
        typingAttributes = [
            .font: configuration.font,
            .foregroundColor: configuration.textColor,
            .paragraphStyle: style
        ]
    }

    // Cmd+B / Cmd+I formatting shortcuts
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "b": wrapSelection(prefix: "**", suffix: "**"); return true
        case "i": wrapSelection(prefix: "_", suffix: "_"); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    func wrapSelection(prefix: String, suffix: String) {
        let sel = selectedRange()
        guard sel.location != NSNotFound else { return }
        let selected = (string as NSString).substring(with: sel)
        let replacement = prefix + selected + suffix
        if shouldChangeText(in: sel, replacementString: replacement) {
            replaceCharacters(in: sel, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: sel.location + prefix.count, length: selected.count))
        }
    }
}

// MARK: - SwiftUI NSViewRepresentable

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var document: Document
    var configuration: EditorConfiguration
    var scrollToLine: Int?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = MarkdownNSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.configuration = configuration
        textView.string = text

        // Wire syntax highlighter
        context.coordinator.highlighter.configuration = configuration
        textView.textStorage?.delegate = context.coordinator.highlighter
        context.coordinator.textView = textView

        scrollView.documentView = textView

        // Initial highlight
        if let storage = textView.textStorage, !text.isEmpty {
            context.coordinator.highlighter.highlightAll(in: storage)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownNSTextView else { return }
        context.coordinator.document = document
        context.coordinator.highlighter.configuration = configuration
        textView.configuration = configuration

        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            if let storage = textView.textStorage, !text.isEmpty {
                context.coordinator.highlighter.highlightAll(in: storage)
            }
            let safe = NSRange(location: min(sel.location, textView.string.count), length: 0)
            textView.setSelectedRange(safe)
        }

        // Scroll to specific line if requested
        if let line = scrollToLine {
            context.coordinator.scrollToLine(line)
        }
    }

    func makeCoordinator() -> TextViewCoordinator {
        TextViewCoordinator(document: document)
    }
}
