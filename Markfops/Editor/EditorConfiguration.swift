import AppKit

struct EditorConfiguration {
    var fontSize: CGFloat
    var lineHeightMultiple: CGFloat
    var editorInsets: NSEdgeInsets
    var backgroundColor: NSColor
    var textColor: NSColor
    var fontFamily: String

    static var `default`: EditorConfiguration {
        EditorConfiguration(
            fontSize: 15,
            lineHeightMultiple: 1.4,
            editorInsets: NSEdgeInsets(top: 24, left: 32, bottom: 24, right: 32),
            backgroundColor: .textBackgroundColor,
            textColor: .textColor,
            fontFamily: "SF Mono"
        )
    }

    var font: NSFont {
        NSFont(name: fontFamily, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    func isEquivalent(to other: EditorConfiguration) -> Bool {
        fontSize == other.fontSize
            && lineHeightMultiple == other.lineHeightMultiple
            && editorInsets.top == other.editorInsets.top
            && editorInsets.left == other.editorInsets.left
            && editorInsets.bottom == other.editorInsets.bottom
            && editorInsets.right == other.editorInsets.right
            && backgroundColor.isEqual(other.backgroundColor)
            && textColor.isEqual(other.textColor)
            && fontFamily == other.fontFamily
    }

    func isHighlightingEquivalent(to other: EditorConfiguration) -> Bool {
        fontSize == other.fontSize
            && lineHeightMultiple == other.lineHeightMultiple
            && textColor.isEqual(other.textColor)
            && fontFamily == other.fontFamily
    }
}
