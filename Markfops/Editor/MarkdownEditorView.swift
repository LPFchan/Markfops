import AppKit
import SwiftUI

// MARK: - EditorBridge

/// Lets EditorContainerView call into the TextViewCoordinator after the NSViewRepresentable is set up.
final class EditorBridge {
    weak var coordinator: TextViewCoordinator?

    /// Releases a slide-time text-wrap freeze immediately (re-wraps at the final width).
    func releaseWrapFreeze() { coordinator?.textView?.releaseWrapFreeze() }

    func morphTextView() -> MarkdownNSTextView? {
        coordinator?.textView
    }

    func morphScrollView() -> NSScrollView? {
        coordinator?.textView?.enclosingScrollView
    }

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

    /// The editor's text cursor as a source offset; a range selection collapses
    /// to its start.
    func currentSourceCursor() -> Int? {
        guard let textView = coordinator?.textView else { return nil }
        let selection = textView.selectedRange()
        guard selection.location != NSNotFound else { return nil }
        return selection.location
    }

    /// Places a collapsed cursor at a source offset without scrolling: the
    /// viewport anchor decides what is visible after a mode switch.
    func setSourceCursor(_ sourceCursor: Int) {
        guard let textView = coordinator?.textView else { return }
        let bounded = max(0, min(sourceCursor, (textView.string as NSString).length))
        textView.setSelectedRange(NSRange(location: bounded, length: 0))
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

    /// Applies a source edit produced by formatted mode through the mounted
    /// editor text view, the one path that registers undo with the document's
    /// undo manager, keeps syntax highlighting current, and syncs `rawText`.
    /// Returns false when no editor is mounted or the range is out of bounds.
    @discardableResult
    func applySourceEdit(in range: NSRange, with replacement: String) -> Bool {
        coordinator?.textView?.applySourceEdit(in: range, with: replacement) ?? false
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
            .paragraphStyle: style,
            .ligature: 0,
        ]
    }

    // Cmd+B / Cmd+I formatting shortcuts
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "b": wrapSelection(prefix: "**", suffix: "**"); return true
        case "i": wrapSelection(prefix: "*", suffix: "*"); return true
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

    /// Wraps the selection in Markdown delimiters, or removes them when the
    /// selection already sits inside a construct made by those delimiters.
    func wrapSelection(prefix: String, suffix: String) {
        let sel = selectedRange()
        guard sel.location != NSNotFound else { return }
        let edit = MarkdownWrapToggle.edit(
            in: string as NSString,
            sourceMap: MarkdownSourceMap.parse(string),
            selection: sel,
            prefix: prefix,
            suffix: suffix
        )
        if shouldChangeText(in: edit.range, replacementString: edit.replacement) {
            replaceCharacters(in: edit.range, with: edit.replacement)
            didChangeText()
            setSelectedRange(edit.selection)
        }
    }

    /// Makes the selected lines headings of `level` (0 for plain paragraphs)
    /// and selects their content. Replaces only the changed lines, so undo
    /// restores them in one step.
    func applyHeading(level: Int) {
        let sel = selectedRange()
        let text = string as NSString
        guard sel.location != NSNotFound,
              let edit = MarkdownHeadingEdit.edit(in: text, selection: sel, level: level) else {
            return
        }
        if text.substring(with: edit.range) != edit.replacement {
            guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
            replaceCharacters(in: edit.range, with: edit.replacement)
            didChangeText()
        }
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
    }

    @discardableResult
    func applySourceEdit(in range: NSRange, with replacement: String) -> Bool {
        guard range.location != NSNotFound,
              range.location >= 0,
              NSMaxRange(range) <= (string as NSString).length,
              shouldChangeText(in: range, replacementString: replacement) else { return false }
        replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(NSRange(
            location: range.location + (replacement as NSString).length,
            length: 0
        ))
        return true
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

// MARK: - SwiftUI NSViewRepresentable

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var document: Document
    var configuration: EditorConfiguration
    var scrollToLine: Int?
    var editorBridge: EditorBridge?
    var isActive = true
    var isVisible: Bool? = nil

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
        scrollView.isHidden = !(isVisible ?? isActive)
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
        scrollView.drawsBackground = true
        scrollView.backgroundColor = configuration.backgroundColor

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
        scrollView.isHidden = !(isVisible ?? isActive)
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
        scrollView.drawsBackground = true
        scrollView.backgroundColor = textView.backgroundColor
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
