import Foundation
import Observation

@Observable
final class Document: Identifiable {
    let id: UUID
    var fileURL: URL?
    var rawText: String
    var isDirty: Bool
    var mode: EditMode
    var scrollPosition: CGFloat
    var headings: [HeadingNode]
    var isTOCExpanded: Bool

    init(fileURL: URL? = nil, rawText: String = "") {
        self.id = UUID()
        self.fileURL = fileURL
        self.rawText = rawText
        self.isDirty = false
        self.mode = .edit
        self.scrollPosition = 0
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
