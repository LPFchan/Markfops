import AppKit
import SwiftUI

struct MarkdownHeadingMutation {
    let text: String
    let selection: NSRange
}

enum MarkdownHeadingFormatter {
    static func applyHeading(level: Int, to text: String, selection: NSRange) -> MarkdownHeadingMutation? {
        guard (1...6).contains(level) else { return nil }

        let originalLines = text.components(separatedBy: "\n")
        guard !originalLines.isEmpty else { return nil }

        let lineInfos = buildLineInfos(from: originalLines)
        guard !lineInfos.isEmpty else { return nil }

        let textLength = (text as NSString).length
        let safeLocation = min(max(selection.location, 0), textLength)
        let endLocation: Int
        if selection.length > 0 {
            endLocation = min(max(textLength - 1, 0), selection.location + selection.length - 1)
        } else {
            endLocation = safeLocation
        }

        let startLineIndex = lineIndex(for: safeLocation, in: lineInfos)
        let endLineIndex = lineIndex(for: endLocation, in: lineInfos)
        return applyHeading(level: level, to: text, lineRange: startLineIndex...endLineIndex)
    }

    static func applyHeading(level: Int, to text: String, sourceLine: Int) -> String? {
        guard let mutation = applyHeading(level: level, to: text, lineRange: sourceLine...sourceLine) else {
            return nil
        }
        return mutation.text
    }

    private static func applyHeading(level: Int, to text: String, lineRange: ClosedRange<Int>) -> MarkdownHeadingMutation? {
        guard (1...6).contains(level) else { return nil }

        var lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else { return nil }

        let lowerBound = max(0, min(lineRange.lowerBound, lines.count - 1))
        let upperBound = max(0, min(lineRange.upperBound, lines.count - 1))
        guard lowerBound <= upperBound else { return nil }

        var changedLineIndices: [Int] = []

        for lineIndex in lowerBound...upperBound {
            let originalLine = lines[lineIndex]
            guard let updatedLine = normalizedHeadingLine(from: originalLine, level: level) else {
                continue
            }
            if updatedLine != originalLine {
                lines[lineIndex] = updatedLine
            }
            changedLineIndices.append(lineIndex)
        }

        guard let firstChangedLine = changedLineIndices.first,
              let lastChangedLine = changedLineIndices.last else {
            return nil
        }

        let updatedText = lines.joined(separator: "\n")
        let updatedInfos = buildLineInfos(from: lines)
        let selectionStart = updatedInfos[firstChangedLine].start
        let selectionEnd = updatedInfos[lastChangedLine].start + updatedInfos[lastChangedLine].content.count
        let selection = NSRange(location: selectionStart, length: max(0, selectionEnd - selectionStart))

        return MarkdownHeadingMutation(text: updatedText, selection: selection)
    }

    private static func normalizedHeadingLine(from line: String, level: Int) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let content: String
        if let prefixRange = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
            content = String(trimmed[prefixRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            content = trimmed
        }

        guard !content.isEmpty else { return nil }
        return String(repeating: "#", count: level) + " " + content
    }

    private static func buildLineInfos(from lines: [String]) -> [(start: Int, content: String)] {
        var infos: [(start: Int, content: String)] = []
        infos.reserveCapacity(lines.count)

        var offset = 0
        for (index, line) in lines.enumerated() {
            infos.append((start: offset, content: line))
            offset += line.count
            if index < lines.count - 1 {
                offset += 1
            }
        }

        return infos
    }

    private static func lineIndex(for location: Int, in infos: [(start: Int, content: String)]) -> Int {
        for (index, info) in infos.enumerated().reversed() {
            if location >= info.start {
                return index
            }
        }
        return 0
    }
}

// MARK: - EditorBridge

/// Lets EditorContainerView call into the TextViewCoordinator after the NSViewRepresentable is set up.
final class EditorBridge {
    weak var coordinator: TextViewCoordinator?

    /// Releases a slide-time text-wrap freeze immediately (re-wraps at the final width).
    func releaseWrapFreeze() { coordinator?.textView?.releaseWrapFreeze() }

    func currentSourceLineAtViewportCenter() -> Int? {
        coordinator?.currentSourceLineAtViewportCenter()
    }

    func currentScrollRatio() -> Double? {
        coordinator?.currentScrollRatio()
    }

    @discardableResult
    func scrollToSourceLineCentered(_ sourceLine: Int) -> Bool {
        coordinator?.scrollToSourceLineCentered(sourceLine) ?? false
    }

    func scrollToRatio(_ ratio: Double) {
        coordinator?.scrollToRatio(ratio)
    }

    func selectedText() -> String? {
        coordinator?.selectedText()
    }

    func find(_ query: String, forward: Bool) -> Bool {
        coordinator?.find(query, forward: forward) ?? false
    }

    func replaceCurrentMatch(find query: String, replace replacement: String) -> Bool {
        coordinator?.replaceCurrentMatch(find: query, replace: replacement) ?? false
    }

    func replaceAll(find query: String, replace replacement: String) -> Int {
        coordinator?.replaceAll(find: query, replace: replacement) ?? 0
    }
}

// MARK: - NSTextView subclass

final class MarkdownNSTextView: NSTextView {
    var onWindowAttachment: (() -> Void)?
    weak var syntaxHighlighter: MarkdownSyntaxHighlighter?
    private(set) var isUpdatingMarkedText = false

    var isComposingText: Bool {
        isUpdatingMarkedText || hasMarkedText()
    }

    var isDocumentActive = true {
        didSet {
            guard !isDocumentActive,
                  let window,
                  let responderView = window.firstResponder as? NSView,
                  responderView === self || responderView.isDescendant(of: self) else { return }
            window.makeFirstResponder(nil)
        }
    }

    override var acceptsFirstResponder: Bool {
        isDocumentActive && super.acceptsFirstResponder
    }

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        isUpdatingMarkedText = true
        defer { isUpdatingMarkedText = false }
        super.setMarkedText(
            string,
            selectedRange: selectedRange,
            replacementRange: replacementRange
        )
    }

    override func unmarkText() {
        let wasComposing = isComposingText
        super.unmarkText()
        if wasComposing {
            scheduleDeferredHighlightFlush()
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let wasComposing = isComposingText
        super.insertText(insertString, replacementRange: replacementRange)
        if wasComposing {
            scheduleDeferredHighlightFlush()
        }
    }

    private func scheduleDeferredHighlightFlush() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  !self.isComposingText,
                  let storage = self.textStorage,
                  self.syntaxHighlighter?.needsDeferredHighlight == true else { return }
            self.syntaxHighlighter?.flushDeferredHighlight(in: storage)
        }
    }

    /// Immediately re-wraps the text at the current frame width after a slide freeze.
    /// Without this the container stays pinned at the pre-slide width until AppKit
    /// happens to deliver another resize (~540ms later) — the end-of-slide stall.
    func releaseWrapFreeze() {
        guard let container = textContainer,
              let layoutManager,
              let scrollView = enclosingScrollView,
              container.containerSize.width > 0,
              abs(container.containerSize.width - frame.size.width) > 1 else { return }
        container.containerSize = NSSize(width: frame.size.width, height: container.containerSize.height)
        // Lay out ONLY the visible region (plus a margin), not the whole document.
        // ensureLayout(for:) forces a synchronous layout of every glyph (~127ms on a
        // long doc) — the residual freeze. Bounding to the viewport makes the re-wrap
        // ~1ms; the rest lays out lazily as the user scrolls.
        let visible = scrollView.contentView.documentVisibleRect
        let margin = visible.height
        let targetRect = visible.insetBy(dx: 0, dy: -margin)
        layoutManager.ensureLayout(forBoundingRect: targetRect, in: container)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.size.width
        // While the sidebar slides, pin the text container width so the document does
        // not re-wrap on every animation frame (the sluggish drag the user feels). The
        // single re-wrap happens when the slide ends and isSliding clears.
        if let container = textContainer, abs(newSize.width - oldWidth) > 1 {
            if SidebarSlideState.isSliding, container.containerSize.width > 0 {
                // Freeze the wrap width mid-slide; re-wrap once when it ends.
                let frozen = container.containerSize.width
                super.setFrameSize(newSize)
                container.containerSize = NSSize(width: frozen, height: container.containerSize.height)
                return
            }
            // Slide over (or not sliding): resync the container to the real width once.
            super.setFrameSize(newSize)
            if container.containerSize.width != newSize.width {
                container.containerSize = NSSize(width: newSize.width, height: container.containerSize.height)
            }
            return
        }
        super.setFrameSize(newSize)
    }
    convenience init(textStorage: NSTextStorage) {
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        layoutManager.addTextContainer(textContainer)
        self.init(frame: .zero, textContainer: textContainer)
    }

    var configuration: EditorConfiguration = .default {
        didSet {
            guard !configuration.isEquivalent(to: oldValue) else { return }
            applyConfiguration()
        }
    }
    private var findHighlightOverlays: [NSView] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyConfiguration()
        if window != nil {
            onWindowAttachment?()
        }
    }

    private func applyConfiguration() {
        backgroundColor = configuration.backgroundColor
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

    override func printView(_ sender: Any?) {
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.horizontalPagination = .fit
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        let op = NSPrintOperation(view: self, printInfo: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        if let win = window {
            op.runModal(for: win, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
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

    func applyHeading(level: Int) {
        let sel = selectedRange()
        guard sel.location != NSNotFound,
              let mutation = MarkdownHeadingFormatter.applyHeading(level: level, to: string, selection: sel) else {
            return
        }

        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        guard shouldChangeText(in: fullRange, replacementString: mutation.text) else { return }

        replaceCharacters(in: fullRange, with: mutation.text)
        didChangeText()
        setSelectedRange(mutation.selection)
        scrollRangeToVisible(mutation.selection)
    }

    func setPlainTextWithoutUndo(_ newText: String) {
        undoManager?.disableUndoRegistration()
        string = newText
        undoManager?.enableUndoRegistration()
    }

    func flashFindHighlight(for range: NSRange) {
        guard let layoutManager,
              let textContainer else { return }

        clearFindHighlightOverlays()

        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let origin = textContainerOrigin

        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: textContainer
        ) { [weak self] rect, _ in
            guard let self, rect.width > 0, rect.height > 0 else { return }

            let overlay = NSView(frame: rect.offsetBy(dx: origin.x - 4, dy: origin.y - 2).insetBy(dx: -4, dy: -3))
            overlay.wantsLayer = true
            overlay.layer?.cornerRadius = 8
            overlay.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.40).cgColor
            overlay.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.95).cgColor
            overlay.layer?.borderWidth = 1.2
            overlay.layer?.shadowColor = NSColor.systemYellow.withAlphaComponent(0.55).cgColor
            overlay.layer?.shadowOpacity = 1
            overlay.layer?.shadowRadius = 12
            overlay.layer?.shadowOffset = CGSize(width: 0, height: 6)
            overlay.alphaValue = 0

            addSubview(overlay)
            findHighlightOverlays.append(overlay)

            overlay.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.94, y: 0.94))

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                overlay.animator().alphaValue = 1
                overlay.layer?.animateScale(to: 1.0, duration: context.duration)
            }

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.42
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.completionHandler = { [weak self, weak overlay] in
                    overlay?.removeFromSuperview()
                    self?.findHighlightOverlays.removeAll { $0 === overlay }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                    overlay.animator().alphaValue = 0
                    overlay.layer?.animateScale(to: 1.04, duration: context.duration)
                }
            }, completionHandler: {})
        }
    }

    private func clearFindHighlightOverlays() {
        findHighlightOverlays.forEach { $0.removeFromSuperview() }
        findHighlightOverlays.removeAll()
    }
}

private extension CALayer {
    func animateScale(to value: CGFloat, duration: TimeInterval) {
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = presentation()?.value(forKeyPath: "transform.scale") ?? value
        animation.toValue = value
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        transform = CATransform3DMakeScale(value, value, 1)
        add(animation, forKey: "markfops.scale")
    }
}

extension NSTextView {
    @objc func applyHeading1() {
        (self as? MarkdownNSTextView)?.applyHeading(level: 1)
    }

    @objc func applyHeading2() {
        (self as? MarkdownNSTextView)?.applyHeading(level: 2)
    }

    @objc func applyHeading3() {
        (self as? MarkdownNSTextView)?.applyHeading(level: 3)
    }
}

// MARK: - SwiftUI NSViewRepresentable

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var document: Document
    var configuration: EditorConfiguration
    var scrollToLine: Int?
    var editorBridge: EditorBridge?
    var isActive = true

    func makeNSView(context: Context) -> NSScrollView {
        let signpostID = TabSwitchProfiler.beginInterval(
            "Editor Make",
            document: document,
            active: isActive
        )
        defer {
            TabSwitchProfiler.endInterval("Editor Make", signpostID: signpostID)
            if isActive {
                TabSwitchProfiler.finishSwitch(documentID: document.id, surface: "editor")
            }
        }
        let scrollView = NSScrollView()
        scrollView.isHidden = !isActive
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = MarkdownNSTextView(textStorage: document.textStorage)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.configuration = configuration

        // Wire syntax highlighter
        context.coordinator.highlighter.updateConfiguration(configuration)
        context.coordinator.highlighter.isEnabled = isActive
        context.coordinator.highlighter.textView = textView
        textView.syntaxHighlighter = context.coordinator.highlighter
        context.coordinator.isActive = isActive
        textView.isDocumentActive = isActive
        textView.textStorage?.delegate = context.coordinator.highlighter
        context.coordinator.textView = textView
        context.coordinator.attach(scrollView: scrollView)
        textView.onWindowAttachment = { [weak coordinator = context.coordinator] in
            coordinator?.scheduleFocusIfAppropriate()
        }
        editorBridge?.coordinator = context.coordinator

        scrollView.documentView = textView

        // Initial highlight
        if isActive, let storage = textView.textStorage, !text.isEmpty {
            let highlightSignpost = TabSwitchProfiler.beginInterval(
                "Syntax Highlight",
                document: document,
                active: true
            )
            context.coordinator.highlighter.highlightAll(in: storage)
            TabSwitchProfiler.endInterval(
                "Syntax Highlight",
                signpostID: highlightSignpost
            )
        }

        context.coordinator.scheduleScrollRestoration(to: document.scrollRatio)
        // Track scroll position for mode-switch sync
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(TextViewCoordinator.scrollViewDidLiveScroll(_:)),
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(TextViewCoordinator.scrollViewDidEndLiveScroll(_:)),
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let signpostID = TabSwitchProfiler.beginInterval(
            "Editor Update",
            document: document,
            active: isActive
        )
        defer {
            TabSwitchProfiler.endInterval("Editor Update", signpostID: signpostID)
            if isActive {
                TabSwitchProfiler.finishSwitch(documentID: document.id, surface: "editor")
            }
        }
        guard let textView = scrollView.documentView as? MarkdownNSTextView else { return }
        scrollView.isHidden = !isActive
        let becameActive = isActive && !context.coordinator.isActive
        if context.coordinator.document.id != document.id {
            guard context.coordinator.prepareForDocumentSwitch(to: document, textView: textView) else {
                return
            }
        } else {
            context.coordinator.document = document
        }
        context.coordinator.highlighter.isEnabled = isActive
        context.coordinator.isActive = isActive
        textView.isDocumentActive = isActive
        if becameActive {
            context.coordinator.scheduleFocusIfAppropriate()
        }
        let highlightingConfigurationChanged = context.coordinator.highlighter.updateConfiguration(configuration)
        let configurationSignpost = TabSwitchProfiler.beginInterval(
            "Editor Configuration",
            document: document,
            active: isActive
        )
        textView.configuration = configuration
        TabSwitchProfiler.endInterval(
            "Editor Configuration",
            signpostID: configurationSignpost
        )

        if context.coordinator.lastAppliedTextRevision != document.textRevision {
            // Document.rawText keeps the shared NSTextStorage synchronized. The revision is
            // therefore enough to acknowledge the new content without bridging and comparing
            // the full Swift string on every unrelated SwiftUI update.
            context.coordinator.lastAppliedTextRevision = document.textRevision
        }

        if isActive && (context.coordinator.highlighter.needsDeferredHighlight || highlightingConfigurationChanged),
                  let storage = textView.textStorage,
                  storage.length > 0 {
            let highlightSignpost = TabSwitchProfiler.beginInterval(
                "Syntax Highlight",
                document: document,
                active: true
            )
            if highlightingConfigurationChanged {
                context.coordinator.highlighter.highlightAll(in: storage)
            } else {
                context.coordinator.highlighter.flushDeferredHighlight(in: storage)
            }
            TabSwitchProfiler.endInterval(
                "Syntax Highlight",
                signpostID: highlightSignpost
            )
        }

        // Scroll to specific line if requested
        if let line = scrollToLine {
            context.coordinator.scrollToLine(line)
        }
    }

    func makeCoordinator() -> TextViewCoordinator {
        TextViewCoordinator(document: document)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: TextViewCoordinator) {
        coordinator.teardown()

        if let textView = scrollView.documentView as? MarkdownNSTextView {
            textView.onWindowAttachment = nil
            textView.syntaxHighlighter = nil
            coordinator.highlighter.textView = nil
            if textView.textStorage?.delegate === coordinator.highlighter {
                textView.textStorage?.delegate = nil
            }
        }
    }
}
