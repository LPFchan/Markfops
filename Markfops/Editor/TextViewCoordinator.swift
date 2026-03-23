import AppKit
import SwiftUI

final class TextViewCoordinator: NSObject, NSTextViewDelegate {
    var document: Document
    var textView: MarkdownNSTextView?
    let highlighter = MarkdownSyntaxHighlighter()
    private var headingDebounceItem: DispatchWorkItem?

    init(document: Document) {
        self.document = document
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        let newText = textView.string

        document.rawText = newText
        document.isDirty = newText != document.savedText

        // Debounced heading refresh (500ms)
        headingDebounceItem?.cancel()
        let headingItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let headings = HeadingParser.parseHeadings(in: newText)
            DispatchQueue.main.async {
                self.document.headings = headings
            }
        }
        headingDebounceItem = headingItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5, execute: headingItem)
    }

    @objc func scrollViewDidLiveScroll(_ notification: Notification) {
        guard let scrollView = notification.object as? NSScrollView,
              let docView = scrollView.documentView else { return }
        let visibleRect = scrollView.contentView.documentVisibleRect
        let totalHeight = docView.bounds.height
        guard totalHeight > 0 else { document.scrollRatio = 0; return }
        // Capture the center of the visible viewport (not the top edge) so the
        // same content stays centered when switching between edit and preview modes.
        let centerY = visibleRect.minY + visibleRect.height / 2
        document.scrollRatio = max(0, min(1, Double(centerY / totalHeight)))
    }

    func scrollToRatio(_ ratio: Double) {
        guard let tv = textView,
              let scrollView = tv.enclosingScrollView else { return }
        let totalHeight = tv.bounds.height
        let visibleHeight = scrollView.contentView.bounds.height
        let scrollableHeight = totalHeight - visibleHeight
        // ratio * totalHeight gives the absolute Y of the center of what was visible;
        // subtract half the viewport height to position it at the center.
        let centerY = CGFloat(ratio) * totalHeight
        let targetY = max(0, min(scrollableHeight, centerY - visibleHeight / 2))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func scrollToLine(_ lineNumber: Int) {
        guard let tv = textView else { return }
        let lines = tv.string.components(separatedBy: "\n")
        guard lineNumber < lines.count else { return }

        var charOffset = 0
        for i in 0..<lineNumber {
            charOffset += lines[i].count + 1
        }
        let lineRange = NSRange(location: charOffset, length: lines[lineNumber].count)

        // Scroll so the heading sits at the top of the visible area
        if let layoutManager = tv.layoutManager,
           let textContainer = tv.textContainer,
           let scrollView = tv.enclosingScrollView {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: lineRange, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += tv.textContainerInset.width
            rect.origin.y += tv.textContainerInset.height
            let targetY = max(0, min(rect.minY, tv.bounds.height - scrollView.contentView.bounds.height))
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        tv.setSelectedRange(NSRange(location: charOffset, length: 0))
        // Animated highlight: hold yellow for 0.6 s then fade out over 1.4 s
        guard let lm = tv.layoutManager else { return }
        let hlColor = NSColor.systemYellow
        lm.addTemporaryAttributes([.backgroundColor: hlColor.withAlphaComponent(0.45)],
                                  forCharacterRange: lineRange)
        let steps = 12
        for i in 1...steps {
            let delay = 0.6 + 1.4 * Double(i) / Double(steps)
            let alpha  = 0.45 * (1.0 - Double(i) / Double(steps))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if alpha <= 0 {
                    lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: lineRange)
                } else {
                    lm.addTemporaryAttributes(
                        [.backgroundColor: hlColor.withAlphaComponent(CGFloat(alpha))],
                        forCharacterRange: lineRange)
                }
            }
        }
    }
}
