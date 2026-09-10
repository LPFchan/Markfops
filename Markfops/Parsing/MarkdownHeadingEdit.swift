import Foundation

/// Decides what the heading commands do to the source: every line the
/// selection touches becomes an ATX heading of the requested level, or a
/// plain line for level 0. Shared by the monospace editor and formatted mode.
enum MarkdownHeadingEdit {
    /// An ATX prefix: up to three spaces, one to six hashes, and the
    /// whitespace binding them to the content (or the end of the line).
    private static let atxPrefix = try! NSRegularExpression(pattern: #"^ {0,3}(#{1,6})([ \t]+|$)"#)
    /// A setext underline, which makes the line above it a heading.
    private static let setextUnderline = try! NSRegularExpression(pattern: #"^ {0,3}(?:=+|-+)[ \t]*$"#)

    private struct Line {
        let content: NSRange
        let terminator: NSRange
    }

    /// Rewrites the lines `selection` touches, from the first non-blank one
    /// to the last: each line's ATX prefix, or the empty range at its first
    /// non-space character, becomes `#` times `level` and a space, or nothing
    /// for level 0. Blank lines are left alone. Returns nil when there is
    /// nothing to rewrite: every touched line is blank, or a touched line
    /// belongs to a setext heading, which this edit does not convert. The
    /// selection afterwards covers the rewritten lines' content.
    ///
    /// Old characters map into the new text so an animation can pair them:
    /// content and untouched lines shift, the first kept hashes land on the
    /// new hashes by index, the first whitespace character after them lands
    /// on the new space, and the rest of an old prefix is removed.
    static func edit(in text: NSString, selection: NSRange, level: Int) -> MarkdownSourceEdit? {
        guard (0...6).contains(level) else { return nil }
        let length = text.length
        let start = max(0, min(selection.location, length))
        let end = max(start, min(NSMaxRange(selection), length))
        let span = text.lineRange(for: NSRange(location: start, length: end - start))

        let lines = self.lines(in: span, of: text)
        guard let first = lines.firstIndex(where: { !isBlank($0.content, in: text) }),
              let last = lines.lastIndex(where: { !isBlank($0.content, in: text) }) else { return nil }
        for line in lines[first...last] where !isBlank(line.content, in: text) {
            guard !belongsToSetextHeading(line, in: text) else { return nil }
        }

        let range = NSRange(location: lines[first].content.location, length: NSMaxRange(lines[last].content) - lines[first].content.location)
        let replacement = NSMutableString()
        var kept: [MarkdownSourceEdit.Kept] = []
        var selectionStart: Int?
        var selectionEnd = range.location

        func keep(_ old: NSRange) {
            guard old.length > 0 else { return }
            kept.append(MarkdownSourceEdit.Kept(old: old, newLocation: range.location + replacement.length))
            replacement.append(text.substring(with: old))
        }

        for (index, line) in lines[first...last].enumerated() {
            if index > 0 {
                keep(lines[first + index - 1].terminator)
            }
            guard !isBlank(line.content, in: text) else {
                keep(line.content)
                continue
            }
            let prefix = self.prefix(of: line.content, in: text)
            keep(NSRange(location: line.content.location, length: prefix.range.location - line.content.location))
            if level > 0 {
                let keptHashes = min(prefix.hashes.length, level)
                keep(NSRange(location: prefix.hashes.location, length: keptHashes))
                replacement.append(String(repeating: "#", count: level - keptHashes))
                if prefix.whitespace.length > 0 {
                    kept.append(MarkdownSourceEdit.Kept(
                        old: NSRange(location: prefix.whitespace.location, length: 1),
                        newLocation: range.location + replacement.length
                    ))
                }
                replacement.append(" ")
            }
            let contentStart = range.location + replacement.length
            selectionStart = selectionStart ?? contentStart
            keep(NSRange(location: NSMaxRange(prefix.range), length: NSMaxRange(line.content) - NSMaxRange(prefix.range)))
            selectionEnd = range.location + replacement.length
        }

        let selectionLocation = selectionStart ?? range.location
        return MarkdownSourceEdit(
            range: range,
            replacement: replacement as String,
            selection: NSRange(location: selectionLocation, length: max(0, selectionEnd - selectionLocation)),
            kept: kept
        )
    }

    private static func lines(in span: NSRange, of text: NSString) -> [Line] {
        var lines: [Line] = []
        var cursor = span.location
        while cursor < NSMaxRange(span) {
            let line = line(at: cursor, in: text)
            lines.append(line)
            cursor = NSMaxRange(line.terminator)
        }
        return lines
    }

    private static func line(at offset: Int, in text: NSString) -> Line {
        var start = 0
        var end = 0
        var contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0))
        return Line(
            content: NSRange(location: start, length: contentsEnd - start),
            terminator: NSRange(location: contentsEnd, length: end - contentsEnd)
        )
    }

    private static func isBlank(_ content: NSRange, in text: NSString) -> Bool {
        text.substring(with: content).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private struct Prefix {
        /// The whole prefix, or an empty range at the first non-space character.
        let range: NSRange
        let hashes: NSRange
        let whitespace: NSRange
    }

    private static func prefix(of content: NSRange, in text: NSString) -> Prefix {
        let line = text.substring(with: content)
        if let match = atxPrefix.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
            let hashes = match.range(at: 1)
            let whitespace = match.range(at: 2)
            return Prefix(
                range: NSRange(location: content.location + match.range.location, length: match.range.length),
                hashes: NSRange(location: content.location + hashes.location, length: hashes.length),
                whitespace: NSRange(location: content.location + whitespace.location, length: whitespace.length)
            )
        }
        let firstNonSpace = (line as NSString).rangeOfCharacter(from: CharacterSet(charactersIn: " \t").inverted).location
        let location = content.location + (firstNonSpace == NSNotFound ? content.length : firstNonSpace)
        return Prefix(
            range: NSRange(location: location, length: 0),
            hashes: NSRange(location: location, length: 0),
            whitespace: NSRange(location: location, length: 0)
        )
    }

    /// A non-blank line followed by an underline is a setext heading, and so
    /// is the underline itself when a non-blank line precedes it.
    private static func belongsToSetextHeading(_ line: Line, in text: NSString) -> Bool {
        let nextStart = NSMaxRange(line.terminator)
        if line.terminator.length > 0, nextStart < text.length,
           isSetextUnderline(self.line(at: nextStart, in: text).content, in: text) {
            return true
        }
        if isSetextUnderline(line.content, in: text), line.content.location > 0 {
            let previous = self.line(at: line.content.location - 1, in: text)
            return !isBlank(previous.content, in: text)
        }
        return false
    }

    private static func isSetextUnderline(_ content: NSRange, in text: NSString) -> Bool {
        let line = text.substring(with: content)
        return setextUnderline.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }
}
