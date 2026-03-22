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
        guard totalHeight > visibleRect.height else { return }
        let midY = visibleRect.minY + visibleRect.height / 2
        document.scrollRatio = max(0, min(1, Double(midY / totalHeight)))
    }

    func scrollToRatio(_ ratio: Double) {
        guard let tv = textView,
              let scrollView = tv.enclosingScrollView else { return }
        let totalHeight = tv.bounds.height
        let visibleHeight = scrollView.contentView.bounds.height
        let targetMidY = CGFloat(ratio) * totalHeight
        let targetY = targetMidY - visibleHeight / 2
        let clampedY = max(0, min(totalHeight - visibleHeight, targetY))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
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
        tv.scrollRangeToVisible(lineRange)
        tv.setSelectedRange(NSRange(location: charOffset, length: 0))
        // Flash the native find indicator (pulsing yellow highlight) on the heading line
        tv.showFindIndicator(for: lineRange)
    }
}
