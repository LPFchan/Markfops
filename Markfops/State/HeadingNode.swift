import Foundation

struct HeadingNode: Identifiable, Equatable {
    let level: Int        // 1–6
    let title: String     // heading text without # marks
    let lineNumber: Int   // 0-based line index for scroll-to

    /// Stable identity derived from content so ForEach doesn't thrash on every re-parse.
    var id: String { "\(lineNumber)-\(level)-\(title)" }
}
