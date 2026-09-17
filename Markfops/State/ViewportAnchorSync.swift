import Foundation

/// Capture-and-restore helper that keeps the content at the visual center of the
/// viewport stable across layout changes (mode switches, sidebar/compact toggles).
///
/// The pattern is always the same: capture which source line sits at the center
/// of the screen (plus the scroll ratio as a fallback) while the current layout is
/// still live, let the layout change happen, then re-center on that anchor. Both
/// the edit/preview mode switch and the sidebar/compact toggle use this so the
/// user never sees content drift when the surrounding chrome changes shape.
final class ViewportAnchorSync {

    enum Surface {
        case editor
        case reader
    }

    /// The shared surface for one document. In the single-renderer architecture
    /// both modes use the same text view, so only the editor bridge is needed.
    struct Context {
        let document: Document
        let editorBridge: EditorBridge

        init(document: Document, editorBridge: EditorBridge) {
            self.document = document
            self.editorBridge = editorBridge
        }

        static func shared(for document: Document) -> Context {
            Context(
                document: document,
                editorBridge: document.sharedEditorBridge
            )
        }
    }

    struct Anchor {
        let sourceLine: Int?
        let ratio: Double
        let sourceCursor: Int?

        init(sourceLine: Int?, ratio: Double, sourceCursor: Int? = nil) {
            self.sourceLine = sourceLine
            self.ratio = ratio
            self.sourceCursor = sourceCursor
        }
    }

    // MARK: - Capture

    static func capture(context: Context, surface: Surface? = nil) -> Anchor {
        let document = context.document
        return Anchor(
            sourceLine: context.editorBridge.currentSourceLineAtViewportCenter(),
            ratio: context.editorBridge.currentScrollRatio() ?? document.scrollRatio,
            sourceCursor: context.editorBridge.currentSourceCursor()
        )
    }

    // MARK: - Restore

    static func restore(
        _ anchor: Anchor,
        context: Context,
        editorDelay: TimeInterval = 0.05
    ) {
        let document = context.document
        document.scrollRatio = anchor.ratio

        DispatchQueue.main.asyncAfter(deadline: .now() + editorDelay) {
            if anchor.sourceLine
                .map({ context.editorBridge.scrollToSourceLineCentered($0) }) != true {
                context.editorBridge.scrollToRatio(anchor.ratio)
            }
        }
    }

    // MARK: - Sidebar / compact toggle

    @discardableResult
    static func captureForLayoutTransition(
        context: Context
    ) -> LayoutTransitionSession {
        let session = LayoutTransitionSession()
        session.arm(anchor: capture(context: context), context: context)
        return session
    }

    final class LayoutTransitionSession {
        private(set) var isCancelled = false
        private var pendingAnchor: Anchor?
        private var pendingContext: Context?

        func arm(anchor: Anchor, context: Context) {
            guard !isCancelled else { return }
            pendingAnchor = anchor
            pendingContext = context
        }

        func fire() {
            guard !isCancelled,
                  let anchor = pendingAnchor,
                  let context = pendingContext else { return }
            pendingAnchor = nil
            pendingContext = nil
            restore(anchor, context: context)
        }

        func cancel() {
            isCancelled = true
            pendingAnchor = nil
            pendingContext = nil
        }
    }
}
