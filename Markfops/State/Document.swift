import Foundation
import AppKit
import Observation
import QuartzCore

@Observable
final class Document: Identifiable {
    let id: UUID
    var fileURL: URL? {
        didSet {
            lastKnownFileSignature = fileURL.flatMap(Self.fileSignature(for:))
            refreshPresentationMetadata()
            notifyStateChange()
        }
    }
    var rawText: String {
        didSet {
            if textStorage.string != rawText {
                undoManager.disableUndoRegistration()
                textStorage.replaceCharacters(
                    in: NSRange(location: 0, length: textStorage.length),
                    with: rawText
                )
                undoManager.enableUndoRegistration()
            }
            notifyStateChange()
        }
    }
    @ObservationIgnored private(set) var lineCount: Int
    @ObservationIgnored private var lineStartOffsets: [Int]
    var isDirty: Bool {
        didSet { notifyStateChange() }
    }
    /// Text as of the last save or open — used to detect whether undo restored the clean state.
    var savedText: String {
        didSet { notifyStateChange() }
    }
    var mode: EditMode
    /// Scroll position as a ratio [0,1] of the document height. @ObservationIgnored
    /// to avoid re-rendering the entire view hierarchy on every scroll event.
    @ObservationIgnored var scrollRatio: Double
    var headings: [HeadingNode] {
        didSet {
            cachedH1Title = headings.first(where: { $0.level == 1 })?.title
            refreshPresentationMetadata()
            notifyStateChange()
        }
    }
    private(set) var displayTitle: String
    private(set) var sidebarDisplayTitle: String
    private(set) var faviconLetter: String
    private(set) var hasH1: Bool
    var activeHeadingID: String?
    var isTOCExpanded: Bool
    /// IDs of TOC headings the user has collapsed (hides their descendant headings).
    var collapsedHeadingIDs: Set<String> = []

    @ObservationIgnored private var fileWatchSource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var pendingFocusedHeading: HeadingNode?
    @ObservationIgnored private var pendingFocusedHeadingExpiry: CFTimeInterval = 0
    @ObservationIgnored private var cachedH1Title: String?
    @ObservationIgnored private var lastKnownFileSignature: FileSignature?
    @ObservationIgnored var onStateChange: ((Document) -> Void)?
    /// Undo history belongs to the document, rather than to whichever editor view is currently
    /// presenting it. This lets the history follow a document across tabs and windows.
    @ObservationIgnored let undoManager = UndoManager()
    /// The text storage is shared by editor views created for this document so native undo
    /// registrations continue to address the same storage across view recreation.
    @ObservationIgnored let textStorage: NSTextStorage

    init(id: UUID = UUID(), fileURL: URL? = nil, rawText: String = "") {
        let initialH1Title = HeadingParser.firstH1Title(in: rawText)
        let presentationMetadata = Self.presentationMetadata(
            h1Title: initialH1Title,
            fileURL: fileURL
        )
        self.id = id
        self.fileURL = fileURL
        self.rawText = rawText
        self.textStorage = NSTextStorage(string: rawText)
        let textMetrics = Self.textMetrics(for: rawText)
        self.lineCount = textMetrics.lineCount
        self.lineStartOffsets = textMetrics.lineStartOffsets
        self.savedText = rawText
        self.isDirty = false
        self.mode = .edit
        self.scrollRatio = 0
        self.headings = []
        self.displayTitle = presentationMetadata.displayTitle
        self.sidebarDisplayTitle = presentationMetadata.sidebarDisplayTitle
        self.faviconLetter = presentationMetadata.faviconLetter
        self.hasH1 = presentationMetadata.hasH1
        self.activeHeadingID = nil
        self.isTOCExpanded = true
        self.cachedH1Title = initialH1Title
        self.lastKnownFileSignature = fileURL.flatMap(Self.fileSignature(for:))
    }

    static func lineCount(for text: String) -> Int {
        textMetrics(for: text).lineCount
    }

    var tocHeadings: [HeadingNode] {
        headings.filter { $0.level > 1 }
    }

    func updateTextMetrics() {
        let textMetrics = Self.textMetrics(for: rawText)
        lineCount = textMetrics.lineCount
        lineStartOffsets = textMetrics.lineStartOffsets
    }

    func sourceLine(containingUTF16Offset offset: Int) -> Int {
        let boundedOffset = max(0, min(offset, (rawText as NSString).length))
        var lowerBound = 0
        var upperBound = lineStartOffsets.count

        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if lineStartOffsets[middle] <= boundedOffset {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        return max(0, lowerBound - 1)
    }

    /// Drops edits that predate a newly adopted source baseline, such as an external reload or
    /// an explicit revert to the saved file.
    func clearUndoHistory() {
        undoManager.removeAllActions()
    }

    func setActiveHeading(_ heading: HeadingNode?) {
        setActiveHeadingID(heading?.id)
    }

    func focusHeading(_ heading: HeadingNode, lockDuration: CFTimeInterval = 1.4) {
        pendingFocusedHeading = heading
        pendingFocusedHeadingExpiry = CACurrentMediaTime() + lockDuration
        setActiveHeadingID(heading.id)
    }

    func reconcileActiveHeadingWithCurrentContent() {
        guard !tocHeadings.isEmpty else {
            setActiveHeadingID(nil)
            return
        }
        guard let activeHeadingID,
              tocHeadings.contains(where: { $0.id == activeHeadingID }) else {
            syncActiveHeadingToScrollPosition()
            return
        }
    }

    func syncActiveHeadingToScrollPosition() {
        let probeLine = Int((Double(max(lineCount - 1, 0)) * scrollRatio).rounded())
        syncActiveHeading(toSourceLine: probeLine)
    }

    func syncActiveHeading(toSourceLine probeLine: Int) {
        guard !tocHeadings.isEmpty else {
            clearPendingFocusedHeading()
            setActiveHeadingID(nil)
            return
        }

        if let pendingFocusedHeading {
            let now = CACurrentMediaTime()
            let isNearTarget = abs(probeLine - pendingFocusedHeading.lineNumber) <= 1
            if now < pendingFocusedHeadingExpiry, !isNearTarget {
                setActiveHeadingID(pendingFocusedHeading.id)
                return
            }
            clearPendingFocusedHeading()
        }

        let newID = tocHeadings.last(where: { $0.lineNumber <= probeLine })?.id
        setActiveHeadingID(newID)
    }

    private static func textMetrics(for text: String) -> (lineCount: Int, lineStartOffsets: [Int]) {
        let utf16 = text.utf16
        var offsets = [0]
        offsets.reserveCapacity(max(1, text.count / 40))

        var offset = 0
        for codeUnit in utf16 {
            offset += 1
            if codeUnit == 0x0A {
                offsets.append(offset)
            }
        }

        return (offsets.count, offsets)
    }

    private func clearPendingFocusedHeading() {
        pendingFocusedHeading = nil
        pendingFocusedHeadingExpiry = 0
    }

    private func setActiveHeadingID(_ newID: String?) {
        guard activeHeadingID != newID else { return }
        activeHeadingID = newID
    }

    // MARK: - File watching

    /// Starts watching the file at `fileURL` for external changes using kqueue (event-driven,
    /// not polling — energy-efficient). Reloads content when another process writes the file,
    /// but only if the document has no unsaved edits.
    func startWatching() {
        stopWatching()
        guard let url = fileURL else { return }
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            // .rename means the file was moved/deleted — stop watching the stale fd.
            if source.data.contains(.rename) {
                self.stopWatching()
                return
            }
            self.reloadFromDiskIfClean()
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        fileWatchSource = source
        lastKnownFileSignature = Self.fileSignature(for: url)
    }

    /// Checks inexpensive file metadata before reading a document during tab selection.
    /// The watcher handles normal writes; this also recovers from atomic replacements.
    func reloadFromDiskIfChanged() {
        guard !isDirty, let url = fileURL else { return }
        guard let currentSignature = Self.fileSignature(for: url) else {
            reloadFromDiskIfClean(restartWatching: fileWatchSource == nil)
            return
        }

        if currentSignature != lastKnownFileSignature {
            reloadFromDiskIfClean(restartWatching: fileWatchSource == nil)
        } else if fileWatchSource == nil {
            startWatching()
        }
    }

    /// Re-reads the backing file when the document has no unsaved edits.
    /// Optionally reattaches the file watcher to recover from atomic-save replacements.
    func reloadFromDiskIfClean(restartWatching: Bool = false) {
        guard !isDirty, let url = fileURL else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            if restartWatching { startWatching() }
            return
        }
        if text != rawText {
            rawText = text
            updateTextMetrics()
            savedText = text
            clearUndoHistory()
            headings = HeadingParser.parseHeadings(in: text)
            reconcileActiveHeadingWithCurrentContent()
        }
        lastKnownFileSignature = Self.fileSignature(for: url)
        if restartWatching { startWatching() }
    }

    func stopWatching() {
        fileWatchSource?.cancel()
        fileWatchSource = nil
    }

    deinit { stopWatching() }

    private func notifyStateChange() {
        onStateChange?(self)
    }

    private func refreshPresentationMetadata() {
        let metadata = Self.presentationMetadata(h1Title: cachedH1Title, fileURL: fileURL)
        displayTitle = metadata.displayTitle
        sidebarDisplayTitle = metadata.sidebarDisplayTitle
        faviconLetter = metadata.faviconLetter
        hasH1 = metadata.hasH1
    }

    private static func presentationMetadata(
        h1Title: String?,
        fileURL: URL?
    ) -> (displayTitle: String, sidebarDisplayTitle: String, faviconLetter: String, hasH1: Bool) {
        let displayTitle = h1Title
            ?? fileURL?.deletingPathExtension().lastPathComponent
            ?? "Untitled"
        var sidebarDisplayTitle = displayTitle
        if let first = displayTitle.unicodeScalars.first,
           first.properties.isEmoji,
           first.value > 0x238C {
            // dropFirst() drops one Swift Character (= full grapheme cluster, handles ZWJ emoji)
            let rest = String(displayTitle.dropFirst())
            sidebarDisplayTitle = rest.hasPrefix(" ") ? String(rest.dropFirst()) : rest
        }
        let faviconLetter = h1Title?.first
            ?? fileURL?.deletingPathExtension().lastPathComponent.first
        return (
            displayTitle,
            sidebarDisplayTitle,
            faviconLetter.map { String($0).uppercased() } ?? "M",
            h1Title != nil
        )
    }

    private static func fileSignature(for url: URL) -> FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return FileSignature(
            modificationDate: attributes[.modificationDate] as? Date,
            size: (attributes[.size] as? NSNumber)?.intValue,
            systemFileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        )
    }
}

private struct FileSignature: Equatable {
    let modificationDate: Date?
    let size: Int?
    let systemFileNumber: UInt64?
}

extension Document: Hashable {
    static func == (lhs: Document, rhs: Document) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
