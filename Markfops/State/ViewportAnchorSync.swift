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

    /// The editor and reader surfaces for one document. Bridges are class references
    /// (weakly bound to live coordinators), so the pair can be created before the
    /// views exist and safely passed in from an ancestor like ContentView.
    struct Context {
        let document: Document
        let editorBridge: EditorBridge
        let readerBridge: ReaderBridge

        init(
            document: Document,
            editorBridge: EditorBridge,
            readerBridge: ReaderBridge
        ) {
            self.document = document
            self.editorBridge = editorBridge
            self.readerBridge = readerBridge
        }

        /// Lazily creates (or returns) the shared bridges held by the document, so
        /// ContentView, EditorContainerView, and this helper all talk to the same
        /// underlying coordinators.
        static func shared(for document: Document) -> Context {
            Context(
                document: document,
                editorBridge: document.sharedEditorBridge,
                readerBridge: document.sharedReaderBridge
            )
        }
    }

    /// A captured center-of-viewport anchor. sourceLine is preferred because it
    /// survives reflow; ratio is the fallback for content with no clear line mapping.
    struct Anchor {
        let sourceLine: Int?
        let ratio: Double
    }

    // MARK: - Capture

    /// Reads the current center-of-viewport anchor from whichever surface is live.
    static func capture(context: Context, surface: Surface? = nil) -> Anchor {
        let document = context.document
        let liveSurface = surface ?? {
            document.mode == .preview ? .reader : .editor
        }()
        switch liveSurface {
        case .editor:
            return Anchor(
                sourceLine: context.editorBridge.currentSourceLineAtViewportCenter(),
                ratio: context.editorBridge.currentScrollRatio() ?? document.scrollRatio
            )
        case .reader:
            return Anchor(
                sourceLine: context.readerBridge.currentSourceLineAtViewportCenter(),
                ratio: context.readerBridge.currentScrollRatio() ?? document.scrollRatio
            )
        }
    }

    // MARK: - Restore

    /// Re-centers the live surface on a previously captured anchor. For the editor the
    /// caller decides when layout has settled; the reader queues the restore until its
    /// presentation is ready.
    static func restore(
        _ anchor: Anchor,
        context: Context,
        editorDelay: TimeInterval = 0.05
    ) {
        let document = context.document
        document.scrollRatio = anchor.ratio

        if document.mode != .edit {
            context.readerBridge.setPendingViewportRestore(
                sourceLine: anchor.sourceLine,
                ratio: anchor.ratio,
                applyImmediately: true
            )
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + editorDelay) {
                guard document.mode == .edit else { return }
                if anchor.sourceLine
                    .map({ context.editorBridge.scrollToSourceLineCentered($0) }) != true {
                    context.editorBridge.scrollToRatio(anchor.ratio)
                }
            }
        }
    }

    // MARK: - Sidebar / compact toggle

    /// Captures the center anchor before the sidebar layout change. The caller fires
    /// the returned session once the transition has visually settled; the restore then
    /// re-centers on the anchor. Driving the restore from the settle signal (rather
    /// than a fixed timer) means there is no window where the reflowed layout is
    /// visible at a drifted scroll offset before the correction lands.
    @discardableResult
    static func captureForLayoutTransition(
        context: Context
    ) -> LayoutTransitionSession {
        let session = LayoutTransitionSession()
        session.arm(anchor: capture(context: context), context: context)
        return session
    }

    /// Holds a captured anchor until the caller reports the layout transition has
    /// settled, then performs the restore. Cancellable so a superseding toggle or a
    /// mode switch can drop a stale restore.
    final class LayoutTransitionSession {
        private(set) var isCancelled = false
        private var pendingAnchor: Anchor?
        private var pendingContext: Context?

        func arm(anchor: Anchor, context: Context) {
            guard !isCancelled else { return }
            pendingAnchor = anchor
            pendingContext = context
        }

        /// Fires the restore for the armed anchor, if any. No-op when cancelled or
        /// when capture has not completed yet.
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
