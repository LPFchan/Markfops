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
        document.isDirty = true

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

    func scrollToLine(_ lineNumber: Int) {
        guard let tv = textView else { return }
        let lines = tv.string.components(separatedBy: "\n")
        guard lineNumber < lines.count else { return }

        var charOffset = 0
        for i in 0..<lineNumber {
            charOffset += lines[i].count + 1
        }
        let range = NSRange(location: charOffset, length: 0)
        tv.scrollRangeToVisible(range)
        tv.setSelectedRange(range)
    }
}
