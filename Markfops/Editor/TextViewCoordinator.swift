import AppKit
import SwiftUI

final class TextViewCoordinator: NSObject, NSTextViewDelegate {
    var document: Document
    var textView: MarkdownNSTextView?
    let highlighter = MarkdownSyntaxHighlighter()
    private var headingDebounceItem: DispatchWorkItem?
    private var scrollAnimationTimer: Timer?
    private var scrollAnimationStartY: CGFloat?
    private var scrollAnimationTargetY: CGFloat?
    private var scrollAnimationDuration: CFTimeInterval = 0
    private var scrollAnimationStartTime: CFTimeInterval?
    private var scrollAnimationLastStep: CFTimeInterval?

    private static let headingScrollSettlingDistance: CGFloat = 0.2

    init(document: Document) {
        self.document = document
    }

    @discardableResult
    func focusTextView() -> Bool {
        guard let textView else { return false }
        textView.window?.makeFirstResponder(textView)
        return textView.window?.firstResponder === textView
    }

    func selectedText() -> String? {
        guard let textView else { return nil }
        let selection = textView.selectedRange()
        guard selection.location != NSNotFound, selection.length > 0 else { return nil }
        return (textView.string as NSString).substring(with: selection)
    }

    func find(_ query: String, forward: Bool) -> Bool {
        guard let textView, !query.isEmpty else { return false }

        let content = textView.string as NSString
        let currentSelection = textView.selectedRange()
        let options: NSString.CompareOptions = forward ? [.caseInsensitive] : [.caseInsensitive, .backwards]

        let searchRange: NSRange
        let wrappedRange: NSRange

        if forward {
            let start = min(currentSelection.location + currentSelection.length, content.length)
            searchRange = NSRange(location: start, length: content.length - start)
            wrappedRange = NSRange(location: 0, length: start)
        } else {
            let end = max(currentSelection.location, 0)
            searchRange = NSRange(location: 0, length: end)
            wrappedRange = NSRange(location: end, length: content.length - end)
        }

        let primary = content.range(of: query, options: options, range: searchRange)
        let match = primary.location != NSNotFound
            ? primary
            : content.range(of: query, options: options, range: wrappedRange)

        guard match.location != NSNotFound else { return false }
        textView.setSelectedRange(match)
        textView.scrollRangeToVisible(match)
        flashFindMatch(in: match)
        return true
    }

    func replaceCurrentMatch(find query: String, replace replacement: String) -> Bool {
        guard let textView, !query.isEmpty else { return false }

        let selection = textView.selectedRange()
        let string = textView.string as NSString
        let selected = selection.location != NSNotFound && selection.length > 0
            ? string.substring(with: selection)
            : ""

        let hasCurrentMatch = selected.compare(query, options: .caseInsensitive) == .orderedSame
        if !hasCurrentMatch && !find(query, forward: true) {
            return false
        }

        let targetRange = textView.selectedRange()
        guard textView.shouldChangeText(in: targetRange, replacementString: replacement) else {
            return false
        }

        textView.replaceCharacters(in: targetRange, with: replacement)
        textView.didChangeText()
        let replacementRange = NSRange(location: targetRange.location, length: (replacement as NSString).length)
        textView.setSelectedRange(replacementRange)
        textView.scrollRangeToVisible(replacementRange)
        flashFindMatch(in: replacementRange)
        return true
    }

    func replaceAll(find query: String, replace replacement: String) -> Int {
        guard let textView, !query.isEmpty else { return 0 }
        _ = focusTextView()

        let source = textView.string as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: source.length)

        while searchRange.length > 0 {
            let found = source.range(of: query, options: [.caseInsensitive], range: searchRange)
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            let nextLocation = found.location + found.length
            searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
        }

        guard !ranges.isEmpty else { return 0 }

        let replaced = source.mutableCopy() as! NSMutableString
        for range in ranges.reversed() {
            replaced.replaceCharacters(in: range, with: replacement)
        }

        let fullRange = NSRange(location: 0, length: source.length)
        guard textView.shouldChangeText(in: fullRange, replacementString: replaced as String) else {
            return 0
        }

        textView.string = replaced as String
        textView.didChangeText()
        let endLocation = min(source.length, replaced.length)
        textView.setSelectedRange(NSRange(location: endLocation, length: 0))
        return ranges.count
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        let newText = textView.string

        document.rawText = newText
        document.updateTextMetrics()
        document.isDirty = newText != document.savedText

        // Debounced heading refresh (500ms)
        headingDebounceItem?.cancel()
        let headingItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let headings = HeadingParser.parseHeadings(in: newText)
            DispatchQueue.main.async {
                self.document.headings = headings
                self.document.reconcileActiveHeadingWithCurrentContent()
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
        document.syncActiveHeadingToScrollPosition()
    }

    func scrollToRatio(_ ratio: Double) {
        guard let tv = textView,
              let scrollView = tv.enclosingScrollView else { return }
        stopScrollAnimation()
        let totalHeight = tv.bounds.height
        let visibleHeight = scrollView.contentView.bounds.height
        let scrollableHeight = totalHeight - visibleHeight
        // ratio * totalHeight gives the absolute Y of the center of what was visible;
        // subtract half the viewport height to position it at the center.
        let centerY = CGFloat(ratio) * totalHeight
        let targetY = max(0, min(scrollableHeight, centerY - visibleHeight / 2))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        document.syncActiveHeadingToScrollPosition()
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
            animateScroll(in: scrollView, to: targetY)
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

    private func animateScroll(in scrollView: NSScrollView, to targetY: CGFloat) {
        let currentY = scrollView.contentView.bounds.origin.y
        scrollAnimationStartY = currentY
        scrollAnimationTargetY = targetY
        let distance = abs(targetY - currentY)
        scrollAnimationDuration = min(0.78, max(0.34, CFTimeInterval(distance * 0.0018)))

        guard scrollAnimationTimer == nil else { return }

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self, weak scrollView] _ in
            guard let self, let scrollView else {
                self?.stopScrollAnimation()
                return
            }
            self.stepScrollAnimation(in: scrollView)
        }
        timer.tolerance = 1.0 / 240.0
        RunLoop.main.add(timer, forMode: .common)
        scrollAnimationTimer = timer
        let now = CACurrentMediaTime()
        scrollAnimationStartTime = now
        scrollAnimationLastStep = now
    }

    private func stepScrollAnimation(in scrollView: NSScrollView) {
        guard let targetY = scrollAnimationTargetY,
              let startY = scrollAnimationStartY,
              let startTime = scrollAnimationStartTime else {
            stopScrollAnimation()
            return
        }

        let now = CACurrentMediaTime()
        scrollAnimationLastStep = now
        let clipView = scrollView.contentView

        let elapsed = now - startTime
        let progress = min(1, max(0, elapsed / max(scrollAnimationDuration, 0.0001)))
        let eased = 1 - pow(1 - progress, 3)
        let nextY = startY + (targetY - startY) * CGFloat(eased)

        clipView.scroll(to: NSPoint(x: 0, y: nextY))
        scrollView.reflectScrolledClipView(clipView)
        document.syncActiveHeadingToScrollPosition()

        if progress >= 1 || abs(targetY - nextY) < Self.headingScrollSettlingDistance {
            clipView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(clipView)
            document.syncActiveHeadingToScrollPosition()
            stopScrollAnimation()
        }
    }

    private func stopScrollAnimation() {
        scrollAnimationTimer?.invalidate()
        scrollAnimationTimer = nil
        scrollAnimationStartY = nil
        scrollAnimationTargetY = nil
        scrollAnimationDuration = 0
        scrollAnimationStartTime = nil
        scrollAnimationLastStep = nil
    }

    private func flashFindMatch(in range: NSRange) {
        textView?.flashFindHighlight(for: range)
    }
}
