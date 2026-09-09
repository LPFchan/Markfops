import AppKit

/// What a source character means, decided by a deliberately tiny Markdown parser.
enum CharKind {
    case prose
    case heading
    case code
    case syntax
}

struct SourceChar {
    let character: Character
    let kind: CharKind
}

/// Parses `# ` headings and `inline code` spans. Everything else is prose.
func parseSource(_ text: String) -> [SourceChar] {
    var result: [SourceChar] = []
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    for (lineIndex, line) in lines.enumerated() {
        if lineIndex > 0 {
            result.append(SourceChar(character: "\n", kind: .prose))
        }
        var body = Substring(line)
        var baseKind = CharKind.prose
        if line.hasPrefix("# ") {
            result.append(contentsOf: "# ".map { SourceChar(character: $0, kind: .syntax) })
            body = line.dropFirst(2)
            baseKind = .heading
        }
        var inCode = false
        for character in body {
            if character == "`" {
                result.append(SourceChar(character: character, kind: .syntax))
                inCode.toggle()
            } else {
                result.append(SourceChar(character: character, kind: inCode ? .code : baseKind))
            }
        }
    }
    return result
}

/// One way of showing the source characters: which of them are visible, and how they are styled.
struct Presentation {
    let attributed: NSAttributedString
    /// For each source character index, its character index in `attributed`, or nil when hidden.
    let indexMap: [Int?]
}

enum Style {
    static let sourceFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    static let proseFont = NSFont.systemFont(ofSize: 15)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
    static let headingFont = NSFont.systemFont(ofSize: 28, weight: .bold)

    static let textColor = NSColor.white
    static let syntaxColor = NSColor(white: 0.55, alpha: 1)
    static let codeColor = NSColor(red: 0.62, green: 0.83, blue: 0.62, alpha: 1)
    static let capsuleColor = NSColor(white: 1, alpha: 0.10)
    static let backgroundColor = NSColor(white: 0.11, alpha: 1)
}

/// Editor view: every character visible, everything monospace, syntax dimmed.
func sourcePresentation(_ chars: [SourceChar]) -> Presentation {
    let paragraph = NSMutableParagraphStyle()
    paragraph.paragraphSpacing = 12
    let result = NSMutableAttributedString()
    var indexMap: [Int?] = []
    for char in chars {
        indexMap.append(result.length)
        let color = char.kind == .syntax ? Style.syntaxColor : Style.textColor
        result.append(NSAttributedString(string: String(char.character), attributes: [
            .font: Style.sourceFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]))
    }
    return Presentation(attributed: result, indexMap: indexMap)
}

/// Reader view: syntax hidden, prose proportional, code monospace, headings large.
func renderedPresentation(_ chars: [SourceChar]) -> Presentation {
    let paragraph = NSMutableParagraphStyle()
    paragraph.paragraphSpacing = 14
    let result = NSMutableAttributedString()
    var indexMap: [Int?] = []
    for char in chars {
        let font: NSFont
        let color: NSColor
        switch char.kind {
        case .syntax:
            indexMap.append(nil)
            continue
        case .prose:
            font = Style.proseFont
            color = Style.textColor
        case .heading:
            font = Style.headingFont
            color = Style.textColor
        case .code:
            font = Style.codeFont
            color = Style.codeColor
        }
        indexMap.append(result.length)
        result.append(NSAttributedString(string: String(char.character), attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]))
    }
    return Presentation(attributed: result, indexMap: indexMap)
}
