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
}
