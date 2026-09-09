import AppKit
import SwiftUI

final class ReaderBridge {
    weak var coordinator: ReaderView.Coordinator? {
        didSet {
            guard let coordinator else { return }
            if let request = bufferedViewportRestore {
                coordinator.setPendingViewportRestore(
                    sourceLine: request.sourceLine,
                    ratio: request.ratio,
                    applyImmediately: request.applyImmediately
                )
                bufferedViewportRestore = nil
            }
            if let heading = bufferedHeading {
                coordinator.pendingHeading = heading
                coordinator.scrollToHeading(heading)
                bufferedHeading = nil
            }
        }
    }

    private var bufferedViewportRestore: (
        sourceLine: Int?, ratio: Double, applyImmediately: Bool
    )?
    private var bufferedHeading: HeadingNode?

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

    func scrollToHeading(_ heading: HeadingNode) {
        bufferedHeading = heading
        coordinator?.pendingHeading = heading
        coordinator?.scrollToHeading(heading)
    }

    func setPendingViewportRestore(
        sourceLine: Int?,
        ratio: Double,
        applyImmediately: Bool = true
    ) {
        guard let coordinator else {
            bufferedViewportRestore = (sourceLine, ratio, applyImmediately)
            return
        }
        bufferedViewportRestore = nil
        coordinator.setPendingViewportRestore(
            sourceLine: sourceLine,
            ratio: ratio,
            applyImmediately: applyImmediately
        )
    }

    func prepareForMorph(themeKey: String) {
        coordinator?.prepareForMorph(themeKey: themeKey)
    }

    func morphTextView() -> ReaderNSTextView? {
        coordinator?.textView
    }

    func morphScrollView() -> NSScrollView? {
        coordinator?.scrollView
    }

    func morphPresentation() -> ReaderPresentation? {
        coordinator?.presentation
    }
}

final class ReaderNSTextView: NSTextView {
    var onWindowAttachment: (() -> Void)?
    var readerTheme = ReaderTheme.default {
        didSet {
            updateReaderLayoutMetrics()
        }
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            onWindowAttachment?()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged {
            updateReaderLayoutMetrics()
        }
    }

    /// Centers a column of at most maxContentWidth by widening the side insets.
    /// Only writes when the value changed: every write invalidates TextKit layout.
    func updateReaderLayoutMetrics() {
        let availableWidth = max(0, frame.width)
        let sideInset = max(
            max(readerTheme.contentInsets.left, readerTheme.contentInsets.right),
            (availableWidth - readerTheme.maxContentWidth) / 2
        )
        let inset = NSSize(width: sideInset, height: readerTheme.contentInsets.top)
        if textContainerInset != inset {
            textContainerInset = inset
        }
    }
}

struct ReaderView: NSViewRepresentable {
    let document: Document
    let theme: ReaderTheme
    let themeKey: String
    let readerBridge: ReaderBridge
    var isActive = true
    var isVisible: Bool? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.isHidden = !(isVisible ?? isActive)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textStorage = NSTextStorage()
        let layoutManager = ReaderLayoutManager()
        layoutManager.theme = theme
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        // Set once, before the container is attached: changing it on a live
        // text view inside a scroll view shifts the document frame origin.
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = ReaderNSTextView(frame: .zero, textContainer: textContainer)
        textView.readerTheme = theme
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.usesFindBar = false
        textView.isIncrementalSearchingEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = theme.backgroundColor
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.backgroundColor
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
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.updateReaderLayoutMetrics()
        textView.isDocumentActive = isActive

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.document = document
        context.coordinator.isActive = isActive
        context.coordinator.theme = theme
        textView.onWindowAttachment = { [weak coordinator = context.coordinator] in
            coordinator?.scheduleFocusIfAppropriate()
        }
        readerBridge.coordinator = context.coordinator
        scrollView.documentView = textView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidLiveScroll(_:)),
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidEndLiveScroll(_:)),
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )

        if isActive {
            context.coordinator.rebuildIfNeeded(themeKey: themeKey)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ReaderNSTextView else { return }
        let becameActive = isActive && !context.coordinator.isActive

        scrollView.isHidden = !(isVisible ?? isActive)
        context.coordinator.document = document
        context.coordinator.isActive = isActive
        context.coordinator.theme = theme
        textView.isDocumentActive = isActive
        textView.readerTheme = theme
        (textView.layoutManager as? ReaderLayoutManager)?.theme = theme
        textView.backgroundColor = theme.backgroundColor
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.backgroundColor
        textView.updateReaderLayoutMetrics()

        if isActive {
            context.coordinator.rebuildIfNeeded(themeKey: themeKey)
            if becameActive {
                context.coordinator.scheduleFocusIfAppropriate()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, theme: theme)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.teardown()
        (scrollView.documentView as? ReaderNSTextView)?.onWindowAttachment = nil
    }

    final class Coordinator: NSObject {
        weak var textView: ReaderNSTextView?
        weak var scrollView: NSScrollView?
        var document: Document
        var theme: ReaderTheme
        var isActive = false
        var presentation: ReaderPresentation?
        var lastDocumentID: UUID?
        var lastTextRevision: UInt64?
        var lastThemeKey: String?
        var pendingViewportSourceLine: Int?
        var pendingScrollRatio: Double?
        var pendingHeading: HeadingNode?

        private var userScrollGesture = UserScrollGestureState()
        private var userScrollIdleResetItem: DispatchWorkItem?
        private var userScrollIdleResetGeneration = 0

        init(document: Document, theme: ReaderTheme) {
            self.document = document
            self.theme = theme
        }

        deinit {
            teardown()
        }

        func teardown() {
            userScrollIdleResetItem?.cancel()
            userScrollIdleResetItem = nil
            NotificationCenter.default.removeObserver(self)
            textView = nil
            scrollView = nil
            userScrollGesture.end()
        }

        func rebuildIfNeeded(themeKey: String) {
            guard isActive else { return }
            let needsBuild = lastDocumentID != document.id
                || lastTextRevision != document.textRevision
                || lastThemeKey != themeKey
                || presentation == nil
            guard needsBuild else {
                applyPendingViewportIfReady()
                return
            }

            let sourceMap = MarkdownSourceMap.parse(document.rawText)
            let built = ReaderPresentation.build(
                text: document.rawText,
                sourceMap: sourceMap,
                theme: theme,
                baseURL: document.fileURL?.deletingLastPathComponent()
            )
            presentation = built
            lastDocumentID = document.id
            lastTextRevision = document.textRevision
            lastThemeKey = themeKey

            guard let textView,
                  let storage = textView.textStorage else { return }
            storage.setAttributedString(built.attributedString)
            if storage.length > 0 {
                storage.fixAttributes(in: NSRange(location: 0, length: storage.length))
            }
            textView.updateReaderLayoutMetrics()

            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive else { return }
                self.scrollView?.layoutSubtreeIfNeeded()
                if self.pendingViewportSourceLine == nil,
                   self.pendingScrollRatio == nil {
                    self.scrollToRatio(self.document.scrollRatio)
                }
                self.applyPendingViewportIfReady()
            }
        }

        /// Builds the native reader synchronously when a mode morph needs the
        /// incoming text and offset map before SwiftUI's next update settles.
        func prepareForMorph(themeKey: String) {
            let wasActive = isActive
            isActive = true
            rebuildIfNeeded(themeKey: themeKey)
            applyPendingViewportIfReady()
            isActive = wasActive
        }

        func setPendingViewportRestore(
            sourceLine: Int?,
            ratio: Double,
            applyImmediately: Bool
        ) {
            pendingViewportSourceLine = sourceLine
            pendingScrollRatio = max(0, min(1, ratio))
            if applyImmediately {
                applyPendingViewportIfReady()
            }
        }

        func scheduleFocusIfAppropriate() {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.isActive,
                      let textView = self.textView,
                      textView.isDocumentActive,
                      let window = textView.window else { return }

                if let fieldEditor = window.firstResponder as? NSTextView,
                   !(fieldEditor is MarkdownNSTextView),
                   !(fieldEditor is ReaderNSTextView) {
                    return
                }
                _ = self.focusTextView()
            }
        }

        @discardableResult
        func focusTextView() -> Bool {
            guard isActive,
                  let textView,
                  textView.isDocumentActive else { return false }
            textView.window?.makeFirstResponder(textView)
            return textView.window?.firstResponder === textView
        }

        func currentSourceLineAtViewportCenter() -> Int? {
            guard let textView,
                  let scrollView,
                  let presentation else { return nil }
            let visibleRect = scrollView.contentView.documentVisibleRect
            let point = NSPoint(
                x: textView.textContainerOrigin.x + 1,
                y: visibleRect.midY
            )
            let readerOffset = min(
                max(0, textView.characterIndexForInsertion(at: point)),
                textView.string.utf16.count
            )
            let sourceOffset = presentation.offsetMap.sourceOffset(forReaderOffset: readerOffset)
            return document.sourceLine(containingUTF16Offset: sourceOffset)
        }

        func currentScrollRatio() -> Double? {
            guard let textView, let scrollView else { return nil }
            let totalHeight = textView.bounds.height
            guard totalHeight > 0 else { return nil }
            let visibleRect = scrollView.contentView.documentVisibleRect
            let centerY = visibleRect.minY + visibleRect.height / 2
            return max(0, min(1, Double(centerY / totalHeight)))
        }

        func scrollToRatio(_ ratio: Double) {
            guard let textView, let scrollView else { return }
            let totalHeight = textView.bounds.height
            let visibleHeight = scrollView.contentView.bounds.height
            let scrollableHeight = max(0, totalHeight - visibleHeight)
            let centerY = CGFloat(ratio) * totalHeight
            let targetY = max(0, min(scrollableHeight, centerY - visibleHeight / 2))
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            syncActiveHeading()
        }

        @discardableResult
        func scrollToSourceLineCentered(_ sourceLine: Int) -> Bool {
            guard let presentation,
                  let range = presentation.offsetMap.readerRange(forSourceLine: sourceLine) else {
                return false
            }
            return scrollToReaderRangeCentered(range)
        }

        func scrollToHeading(_ heading: HeadingNode) {
            pendingHeading = heading
            guard isActive else { return }
            if scrollToSourceLineCentered(heading.lineNumber) {
                pendingHeading = nil
            }
        }

        @objc func scrollViewDidLiveScroll(_ notification: Notification) {
            guard isActive,
                  let scrollView,
                  notification.object as? NSScrollView === scrollView else { return }
            if userScrollGesture.begin() {
                document.registerUserContentScroll()
            }
            scheduleUserScrollIdleReset()
            document.scrollRatio = currentScrollRatio() ?? 0
            document.syncActiveHeadingToScrollPosition()
        }

        @objc func scrollViewDidEndLiveScroll(_ notification: Notification) {
            guard notification.object as? NSScrollView === scrollView else { return }
            userScrollIdleResetItem?.cancel()
            userScrollIdleResetItem = nil
            userScrollGesture.end()
        }

        private func applyPendingViewportIfReady() {
            guard isActive, presentation != nil else { return }

            if let sourceLine = pendingViewportSourceLine {
                let fallbackRatio = pendingScrollRatio
                pendingViewportSourceLine = nil
                pendingScrollRatio = nil
                if !scrollToSourceLineCentered(sourceLine), let ratio = fallbackRatio {
                    scrollToRatio(ratio)
                }
            } else if let ratio = pendingScrollRatio {
                pendingScrollRatio = nil
                scrollToRatio(ratio)
            }

            if let pendingHeading, scrollToSourceLineCentered(pendingHeading.lineNumber) {
                self.pendingHeading = nil
            }
        }

        private func scrollToReaderRangeCentered(_ range: NSRange) -> Bool {
            guard let textView,
                  let scrollView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return false }

            let boundedLocation = max(0, min(range.location, textView.string.utf16.count))
            let boundedLength = max(
                0,
                min(range.length, textView.string.utf16.count - boundedLocation)
            )
            let boundedRange = NSRange(location: boundedLocation, length: boundedLength)
            let targetEnd = min(
                textView.string.utf16.count,
                max(boundedLocation + max(boundedLength, 1), boundedLocation + 1)
            )
            let glyphEnd = layoutManager.glyphIndexForCharacter(at: targetEnd)
            layoutManager.ensureLayout(forGlyphRange: NSRange(location: 0, length: glyphEnd))

            var glyphRange = layoutManager.glyphRange(
                forCharacterRange: boundedRange,
                actualCharacterRange: nil
            )
            if glyphRange.length == 0, glyphEnd > 0 {
                glyphRange = NSRange(location: max(0, glyphEnd - 1), length: 1)
            }
            guard glyphRange.length > 0 else { return false }

            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y

            let visibleHeight = scrollView.contentView.bounds.height
            let contentHeight = max(
                layoutManager.usedRect(for: textContainer).height,
                textView.bounds.height
            )
            let scrollableHeight = max(0, contentHeight - visibleHeight)
            let targetY = max(0, min(scrollableHeight, rect.midY - visibleHeight / 2))
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            document.scrollRatio = currentScrollRatio() ?? document.scrollRatio
            syncActiveHeading()
            return true
        }

        private func syncActiveHeading() {
            guard let sourceLine = currentSourceLineAtViewportCenter() else { return }
            document.syncActiveHeading(toSourceLine: sourceLine)
        }

        private func scheduleUserScrollIdleReset() {
            userScrollIdleResetItem?.cancel()
            let generation = userScrollIdleResetGeneration
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.userScrollIdleResetGeneration == generation else { return }
                self.userScrollGesture.end()
                self.userScrollIdleResetItem = nil
            }
            userScrollIdleResetItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }
    }
}
