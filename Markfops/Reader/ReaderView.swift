import AppKit
import Observation
import os
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

    /// Composition (Korean and other input methods) is the one case where text
    /// lives in the reader storage before the source has it. The coordinator
    /// decides whether it may start, and receives the final string on commit.
    var onCompositionStart: ((NSRange) -> Bool)?
    var onCompositionCommit: ((String, NSRange) -> Void)?
    var onCompositionEnd: (() -> Void)?
    /// Enter is decided by the coordinator: a paragraph break in prose, a
    /// single newline inside code, lists, quotes, and other line-based blocks.
    var onInsertNewline: (() -> Void)?
    private(set) var isUpdatingMarkedText = false
    private var isCommittingComposition = false

    /// `allowsUndo` stays off (the reader never registers its own undo), which
    /// makes NSTextView report no undo manager. Undo in formatted mode must
    /// reach the document's history, the one the routed source edits write to.
    override var undoManager: UndoManager? {
        delegate?.undoManager?(for: self) ?? super.undoManager
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

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        // NSTextView's unmarkText clears its state through this method too;
        // during a commit that is bookkeeping, not a composition ending.
        guard !isCommittingComposition else {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            return
        }
        if !hasMarkedText(), let onCompositionStart {
            let target = replacementRange.location == NSNotFound
                ? self.selectedRange()
                : replacementRange
            guard onCompositionStart(target) else { return }
        }
        isUpdatingMarkedText = true
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        isUpdatingMarkedText = false
        if !hasMarkedText() {
            onCompositionEnd?()
        }
    }

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), let onInsertNewline else {
            super.insertNewline(sender)
            return
        }
        onInsertNewline()
    }

    /// An input method commits its composition through `insertText`. The
    /// committed string never enters the reader storage directly; it is routed
    /// to the source once and the reader is rebuilt from there.
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        // NSTextView's unmarkText re-inserts the marked text through this
        // method; while a commit is in flight that re-insert is dropped.
        guard !isCommittingComposition else { return }
        guard hasMarkedText(), let onCompositionCommit else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        let committed = (insertString as? NSAttributedString)?.string
            ?? (insertString as? String)
            ?? ""
        let composedRange = markedRange()
        clearMarkedText()
        onCompositionCommit(committed, composedRange)
    }

    /// AppKit unmarks without inserting when focus moves away mid-composition.
    /// The editor keeps the composed syllable as regular text in that case, so
    /// the reader commits it to the source the same way.
    override func unmarkText() {
        guard hasMarkedText(), !isUpdatingMarkedText, let onCompositionCommit else {
            super.unmarkText()
            return
        }
        let composedRange = markedRange()
        let composed = (string as NSString).substring(with: composedRange)
        clearMarkedText()
        onCompositionCommit(composed, composedRange)
    }

    private func clearMarkedText() {
        isCommittingComposition = true
        isUpdatingMarkedText = true
        super.unmarkText()
        isUpdatingMarkedText = false
        isCommittingComposition = false
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
        textView.delegate = context.coordinator
        // Editable so it takes keyboard input; every change is refused by the
        // delegate and routed to the Markdown source instead.
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.usesFindBar = false
        textView.isIncrementalSearchingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
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
        textView.onCompositionStart = { [weak coordinator = context.coordinator] readerRange in
            coordinator?.compositionWillStart(readerRange: readerRange) ?? false
        }
        textView.onCompositionCommit = { [weak coordinator = context.coordinator] string, readerRange in
            coordinator?.commitComposition(string, readerRange: readerRange)
        }
        textView.onCompositionEnd = { [weak coordinator = context.coordinator] in
            coordinator?.compositionDidEnd()
        }
        textView.onInsertNewline = { [weak coordinator = context.coordinator] in
            coordinator?.insertNewline()
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
        context.coordinator.observeSourceChanges()

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
        if let textView = scrollView.documentView as? ReaderNSTextView {
            textView.onWindowAttachment = nil
            textView.onCompositionStart = nil
            textView.onCompositionCommit = nil
            textView.onCompositionEnd = nil
            textView.onInsertNewline = nil
            if textView.delegate === coordinator {
                textView.delegate = nil
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private static let log = Logger(subsystem: "plus.lost.Markfops", category: "formatted-editing")

        weak var textView: ReaderNSTextView?
        weak var scrollView: NSScrollView?
        var document: Document
        var theme: ReaderTheme
        var isActive = false
        var presentation: ReaderPresentation?
        private(set) var sourceMap: MarkdownSourceMap?
        var lastDocumentID: UUID?
        var lastTextRevision: UInt64?
        var lastThemeKey: String?
        /// Source range whose syntax the current build shows in place.
        private(set) var revealedSourceRange: NSRange?
        var lastRevealedSourceRange: NSRange?
        var pendingViewportSourceLine: Int?
        var pendingScrollRatio: Double?
        var pendingHeading: HeadingNode?
        /// Tests silence the refusal beep; the operator hears it in the app.
        var playsRefusalSound = true
        /// Count of edits refused because the map could not route them.
        private(set) var refusedEditCount = 0

        private var userScrollGesture = UserScrollGestureState()
        private var userScrollIdleResetItem: DispatchWorkItem?
        private var userScrollIdleResetGeneration = 0
        private var isApplyingPresentation = false
        private var isRoutingEdit = false
        private var compositionSourceRange: NSRange?
        private var isObservingSource = false
        private var isTornDown = false

        init(document: Document, theme: ReaderTheme) {
            self.document = document
            self.theme = theme
        }

        deinit {
            teardown()
        }

        func teardown() {
            isTornDown = true
            userScrollIdleResetItem?.cancel()
            userScrollIdleResetItem = nil
            NotificationCenter.default.removeObserver(self)
            textView = nil
            scrollView = nil
            userScrollGesture.end()
        }

        // MARK: - Building

        func rebuildIfNeeded(themeKey: String) {
            guard isActive else { return }
            let documentChanged = lastDocumentID != document.id
            let textChanged = lastTextRevision != document.textRevision
            if documentChanged || textChanged {
                // A fresh text invalidates the reveal; the next caret move restores it.
                revealedSourceRange = nil
            }
            let needsBuild = documentChanged
                || textChanged
                || lastThemeKey != themeKey
                || lastRevealedSourceRange != revealedSourceRange
                || presentation == nil
            guard needsBuild else {
                applyPendingViewportIfReady()
                return
            }

            let needsRatioScroll = documentChanged || presentation == nil
            performRebuild(themeKey: themeKey, sourceCursor: nil)

            guard needsRatioScroll else { return }
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

        /// Parses the source, builds the presentation with the reveal for
        /// `sourceCursor` (or the current reveal when nil), applies it to the
        /// storage as a minimal replacement, and places the caret at the cursor.
        private func performRebuild(themeKey: String, sourceCursor: Int?) {
            let textUnchanged = lastDocumentID == document.id
                && lastTextRevision == document.textRevision
            let map = textUnchanged && sourceMap != nil
                ? sourceMap!
                : MarkdownSourceMap.parse(document.rawText)
            if let sourceCursor {
                revealedSourceRange = ReaderReveal.range(in: map, sourceCursor: sourceCursor)
            }
            let built = ReaderPresentation.build(
                text: document.rawText,
                sourceMap: map,
                theme: theme,
                baseURL: document.fileURL?.deletingLastPathComponent(),
                revealedSourceRange: revealedSourceRange
            )
            sourceMap = map
            presentation = built
            lastDocumentID = document.id
            lastTextRevision = document.textRevision
            lastThemeKey = themeKey
            lastRevealedSourceRange = revealedSourceRange
            compositionSourceRange = nil

            applyPresentation(built)
            if let sourceCursor, let textView {
                let readerOffset = built.offsetMap.readerOffset(forSourceOffset: sourceCursor)
                isApplyingPresentation = true
                textView.setSelectedRange(NSRange(location: readerOffset, length: 0))
                isApplyingPresentation = false
            }
        }

        /// Replaces only the part of the storage that differs from the new
        /// presentation: the text between the common prefix and suffix, then
        /// any attribute runs in the untouched prefix and suffix that changed
        /// (a reveal or a construct change restyles text without changing it).
        private func applyPresentation(_ built: ReaderPresentation) {
            guard let textView, let storage = textView.textStorage else { return }
            isApplyingPresentation = true
            defer { isApplyingPresentation = false }

            let fixed = NSMutableAttributedString(attributedString: built.attributedString)
            if fixed.length > 0 {
                fixed.fixAttributes(in: NSRange(location: 0, length: fixed.length))
            }
            let old = storage.string as NSString
            let new = fixed.string as NSString
            let (prefix, suffix) = Self.commonAffixes(old, new)
            let oldMiddle = NSRange(location: prefix, length: old.length - prefix - suffix)
            let newMiddle = NSRange(location: prefix, length: new.length - prefix - suffix)

            storage.beginEditing()
            if oldMiddle.length > 0 || newMiddle.length > 0 {
                storage.replaceCharacters(in: oldMiddle, with: fixed.attributedSubstring(from: newMiddle))
            }
            Self.applyAttributeDifferences(
                from: fixed,
                to: storage,
                in: NSRange(location: 0, length: prefix)
            )
            Self.applyAttributeDifferences(
                from: fixed,
                to: storage,
                in: NSRange(location: NSMaxRange(newMiddle), length: suffix)
            )
            storage.endEditing()
            textView.updateReaderLayoutMetrics()
        }

        /// UTF-16 lengths of the common prefix and suffix, never splitting a
        /// surrogate pair.
        static func commonAffixes(_ old: NSString, _ new: NSString) -> (prefix: Int, suffix: Int) {
            let limit = min(old.length, new.length)
            var prefix = 0
            while prefix < limit, old.character(at: prefix) == new.character(at: prefix) {
                prefix += 1
            }
            if prefix > 0, prefix < limit, UTF16.isLeadSurrogate(old.character(at: prefix - 1)) {
                prefix -= 1
            }
            var suffix = 0
            while suffix < limit - prefix,
                  old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) {
                suffix += 1
            }
            if suffix > 0, suffix < limit - prefix,
               UTF16.isTrailSurrogate(old.character(at: old.length - suffix)) {
                suffix -= 1
            }
            return (prefix, suffix)
        }

        private static func applyAttributeDifferences(
            from new: NSAttributedString,
            to storage: NSTextStorage,
            in range: NSRange
        ) {
            var location = range.location
            let end = NSMaxRange(range)
            while location < end {
                var newRun = NSRange()
                let newAttributes = new.attributes(at: location, longestEffectiveRange: &newRun, in: range)
                var oldRun = NSRange()
                let oldAttributes = storage.attributes(at: location, longestEffectiveRange: &oldRun, in: range)
                let runEnd = min(NSMaxRange(newRun), NSMaxRange(oldRun))
                if !attributesMatch(newAttributes, oldAttributes) {
                    storage.setAttributes(newAttributes, range: NSRange(location: location, length: runEnd - location))
                }
                location = runEnd
            }
        }

        /// Attachments are fresh objects on every build; their identity must
        /// not count as a difference or an image would relayout per keystroke.
        private static func attributesMatch(
            _ lhs: [NSAttributedString.Key: Any],
            _ rhs: [NSAttributedString.Key: Any]
        ) -> Bool {
            var left = lhs
            var right = rhs
            left[.attachment] = nil
            right[.attachment] = nil
            return (left as NSDictionary).isEqual(to: right)
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

        // MARK: - Source changes made elsewhere (undo, redo, reload)

        /// Nothing in the SwiftUI tree reads `rawText` on the reader's behalf,
        /// so an undo performed while formatted mode is showing would leave the
        /// reader stale. Observe the source directly and rebuild on the next turn.
        func observeSourceChanges() {
            guard !isObservingSource, !isTornDown else { return }
            isObservingSource = true
            withObservationTracking {
                _ = document.rawText
            } onChange: { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isObservingSource = false
                    self.rebuildForExternalSourceChange()
                    self.observeSourceChanges()
                }
            }
        }

        private func rebuildForExternalSourceChange() {
            guard isActive,
                  !isRoutingEdit,
                  let themeKey = lastThemeKey,
                  lastDocumentID == document.id,
                  lastTextRevision != document.textRevision,
                  let textView else { return }
            let editorCursor = document.sharedEditorBridge.morphTextView()?.selectedRange().location
            let sourceLength = (document.rawText as NSString).length
            let cursor = min(max(0, editorCursor ?? sourceLength), sourceLength)
            performRebuild(themeKey: themeKey, sourceCursor: cursor)
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        // MARK: - Routing edits to the source

        func undoManager(for view: NSTextView) -> UndoManager? {
            document.undoManager
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let readerTextView = self.textView, textView === readerTextView else { return false }
            if readerTextView.isUpdatingMarkedText || readerTextView.hasMarkedText() {
                return true
            }
            guard let replacementString else {
                // Attribute-only change (font panel, ruler): nothing to route.
                return false
            }
            routeEdit(readerRange: affectedCharRange, replacement: replacementString)
            return false
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextInRanges affectedRanges: [NSValue],
            replacementStrings: [String]?
        ) -> Bool {
            guard affectedRanges.count == 1 else {
                refuse("multiple ranges")
                return false
            }
            return self.textView(
                textView,
                shouldChangeTextIn: affectedRanges[0].rangeValue,
                replacementString: replacementStrings?.first
            )
        }

        /// Translates a reader edit into the exact source edit and applies it.
        @discardableResult
        func routeEdit(readerRange: NSRange, replacement: String) -> Bool {
            guard let presentation else {
                refuse("no presentation")
                return false
            }
            guard let sourceRange = presentation.offsetMap.sourceRange(forReaderRange: readerRange) else {
                refuse("reader \(readerRange) is not routable")
                return false
            }
            return routeSourceEdit(sourceRange: sourceRange, replacement: replacement, readerRange: readerRange)
        }

        @discardableResult
        private func routeSourceEdit(sourceRange: NSRange, replacement: String, readerRange: NSRange) -> Bool {
            guard let textView, let themeKey = lastThemeKey else {
                refuse("reader not built")
                return false
            }
            isRoutingEdit = true
            defer { isRoutingEdit = false }
            guard document.sharedEditorBridge.applySourceEdit(in: sourceRange, with: replacement) else {
                refuse("editor unavailable for source \(sourceRange)")
                return false
            }
            let cursor = sourceRange.location + (replacement as NSString).length
            performRebuild(themeKey: themeKey, sourceCursor: cursor)
            textView.scrollRangeToVisible(textView.selectedRange())
            Self.log.debug(
                "routed reader \(readerRange.location, privacy: .public)+\(readerRange.length, privacy: .public) to source \(sourceRange.location, privacy: .public)+\(sourceRange.length, privacy: .public) replacement=\((replacement as NSString).length, privacy: .public)"
            )
            return true
        }

        /// Enter replaces the selection with a paragraph break in prose or a
        /// single newline in line-based blocks, then routes like any other edit.
        func insertNewline() {
            guard let textView, let presentation, let sourceMap else {
                refuse("no presentation for newline")
                return
            }
            let readerRange = textView.selectedRange()
            guard let sourceRange = presentation.offsetMap.sourceRange(forReaderRange: readerRange) else {
                refuse("reader \(readerRange) is not routable")
                return
            }
            let replacement = ReaderNewline.replacement(in: sourceMap, sourceOffset: sourceRange.location)
            routeSourceEdit(sourceRange: sourceRange, replacement: replacement, readerRange: readerRange)
        }

        private func refuse(_ reason: String) {
            refusedEditCount += 1
            Self.log.notice("refused edit: \(reason, privacy: .public)")
            if playsRefusalSound {
                NSSound.beep()
            }
        }

        // MARK: - Reveal tracking

        func textViewDidChangeSelection(_ notification: Notification) {
            guard isActive,
                  !isApplyingPresentation,
                  !isRoutingEdit,
                  let textView,
                  notification.object as? NSTextView === textView,
                  !textView.hasMarkedText(),
                  !textView.isUpdatingMarkedText else { return }
            let selection = textView.selectedRange()
            // A range selection keeps the current reveal: rebuilding the storage
            // under a mouse drag would shift the drag anchor.
            guard selection.length == 0 else { return }
            updateReveal(forReaderCaret: selection.location)
        }

        func updateReveal(forReaderCaret caret: Int) {
            guard let presentation, let sourceMap, let themeKey = lastThemeKey else { return }
            let sourceCursor = presentation.offsetMap.sourceInsertionOffset(forReaderOffset: caret)
            let reveal = ReaderReveal.range(in: sourceMap, sourceCursor: sourceCursor)
            guard reveal != revealedSourceRange else { return }
            performRebuild(themeKey: themeKey, sourceCursor: sourceCursor)
        }

        // MARK: - Composition

        func compositionWillStart(readerRange: NSRange) -> Bool {
            guard let presentation,
                  let sourceRange = presentation.offsetMap.sourceRange(forReaderRange: readerRange) else {
                refuse("composition at reader \(readerRange) is not routable")
                return false
            }
            compositionSourceRange = sourceRange
            return true
        }

        func commitComposition(_ string: String, readerRange: NSRange) {
            guard let sourceRange = compositionSourceRange else {
                compositionDidEnd()
                return
            }
            compositionSourceRange = nil
            if !routeSourceEdit(sourceRange: sourceRange, replacement: string, readerRange: readerRange) {
                compositionDidEnd()
            }
        }

        /// Composition ended without a commit: put the storage back to the
        /// presentation so no marked text lingers.
        func compositionDidEnd() {
            compositionSourceRange = nil
            guard let presentation else { return }
            applyPresentation(presentation)
        }

        // MARK: - Viewport

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
