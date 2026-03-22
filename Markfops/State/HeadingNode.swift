import Foundation

struct HeadingNode: Identifiable, Equatable {
    let id: UUID
    let level: Int        // 1–6
    let title: String     // heading text without # marks
    let lineNumber: Int   // 0-based line index for scroll-to

    init(level: Int, title: String, lineNumber: Int) {
        self.id = UUID()
        self.level = level
        self.title = title
        self.lineNumber = lineNumber
    }
}
