import Foundation
import Observation

@Observable
final class Document: Identifiable {
    let id: UUID
    var fileURL: URL?
    var rawText: String
    @ObservationIgnored private(set) var lineCount: Int
    var isDirty: Bool
    /// Text as of the last save or open — used to detect whether undo restored the clean state.
    var savedText: String
    var mode: EditMode
    /// Scroll position as a ratio [0,1] of the document height. @ObservationIgnored
    /// to avoid re-rendering the entire view hierarchy on every scroll event.
    @ObservationIgnored var scrollRatio: Double
    var headings: [HeadingNode]
    var activeHeadingID: String?
    var isTOCExpanded: Bool
    /// IDs of TOC headings the user has collapsed (hides their descendant headings).
    var collapsedHeadingIDs: Set<String> = []

    @ObservationIgnored private var fileWatchSource: DispatchSourceFileSystemObject?

    init(fileURL: URL? = nil, rawText: String = "") {
        self.id = UUID()
        self.fileURL = fileURL
        self.rawText = rawText
        self.lineCount = Self.lineCount(for: rawText)
        self.savedText = rawText
        self.isDirty = false
        self.mode = .edit
        self.scrollRatio = 0
        self.headings = []
        self.activeHeadingID = nil
        self.isTOCExpanded = false
    }

    static func lineCount(for text: String) -> Int {
        max(1, text.reduce(into: 1) { count, ch in
            if ch == "\n" { count += 1 }
        })
    }

    var tocHeadings: [HeadingNode] {
        headings.filter { $0.level > 1 }
    }

    func updateTextMetrics() {
        lineCount = Self.lineCount(for: rawText)
    }

    func setActiveHeading(_ heading: HeadingNode?) {
        setActiveHeadingID(heading?.id)
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
        guard !tocHeadings.isEmpty else {
            setActiveHeadingID(nil)
            return
        }
        let probeLine = Int((Double(max(lineCount - 1, 0)) * scrollRatio).rounded())
        let newID = tocHeadings.last(where: { $0.lineNumber <= probeLine })?.id
        setActiveHeadingID(newID)
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
            headings = HeadingParser.parseHeadings(in: text)
            reconcileActiveHeadingWithCurrentContent()
        }
        if restartWatching { startWatching() }
    }

    func stopWatching() {
        fileWatchSource?.cancel()
        fileWatchSource = nil
    }

    deinit { stopWatching() }

    var displayTitle: String {
        HeadingParser.firstH1Title(in: rawText)
            ?? fileURL?.deletingPathExtension().lastPathComponent
            ?? "Untitled"
    }

    /// Like displayTitle but strips a leading emoji (and any space after it) so it
    /// isn't shown twice when the emoji is already displayed in the favicon badge.
    var sidebarDisplayTitle: String {
        let title = displayTitle
        guard let first = title.unicodeScalars.first,
              first.properties.isEmoji,
              first.value > 0x238C else { return title }
        // dropFirst() drops one Swift Character (= full grapheme cluster, handles ZWJ emoji)
        let rest = String(title.dropFirst())
        return rest.hasPrefix(" ") ? String(rest.dropFirst()) : rest
    }

    var faviconLetter: String {
        if let letter = HeadingParser.firstH1Letter(in: rawText) {
            return letter
        }
        if let filename = fileURL?.deletingPathExtension().lastPathComponent,
           let first = filename.first {
            return String(first).uppercased()
        }
        return "M"
    }
}

extension Document: Hashable {
    static func == (lhs: Document, rhs: Document) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
