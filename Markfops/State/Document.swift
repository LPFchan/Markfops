import Foundation
import Observation

@Observable
final class Document: Identifiable {
    let id: UUID
    var fileURL: URL?
    var rawText: String
    var isDirty: Bool
    /// Text as of the last save or open — used to detect whether undo restored the clean state.
    var savedText: String
    var mode: EditMode
    /// Scroll position as a ratio [0,1] of the document height. @ObservationIgnored
    /// to avoid re-rendering the entire view hierarchy on every scroll event.
    @ObservationIgnored var scrollRatio: Double
    var headings: [HeadingNode]
    var isTOCExpanded: Bool

    init(fileURL: URL? = nil, rawText: String = "") {
        self.id = UUID()
        self.fileURL = fileURL
        self.rawText = rawText
        self.savedText = rawText
        self.isDirty = false
        self.mode = .edit
        self.scrollRatio = 0
        self.headings = []
        self.isTOCExpanded = false
    }

    var displayTitle: String {
        HeadingParser.firstH1Title(in: rawText)
            ?? fileURL?.deletingPathExtension().lastPathComponent
            ?? "Untitled"
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
