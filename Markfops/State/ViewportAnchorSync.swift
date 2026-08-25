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

    /// The editor/preview surfaces for one document. Bridges are class references
    /// (weakly bound to live coordinators), so the pair can be created before the
    /// views exist and safely passed in from an ancestor like ContentView.
    struct Context {
        let document: Document
        let editorBridge: EditorBridge
        let previewBridge: PreviewBridge

        init(document: Document, editorBridge: EditorBridge, previewBridge: PreviewBridge) {
            self.document = document
            self.editorBridge = editorBridge
            self.previewBridge = previewBridge
        }

        /// Lazily creates (or returns) the shared bridges held by the document, so
        /// ContentView, EditorContainerView, and this helper all talk to the same
        /// underlying coordinators.
        static func shared(for document: Document) -> Context {
            Context(
                document: document,
                editorBridge: document.sharedEditorBridge,
                previewBridge: document.sharedPreviewBridge
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
    /// The preview read is asynchronous (JS eval), so capture always goes through a
    /// completion handler. In edit mode the editor is read synchronously and the
    /// completion fires on the next main runloop turn for a uniform contract.
    static func capture(context: Context, completion: @escaping (Anchor) -> Void) {
        let document = context.document
        let documentID = document.id
        if document.mode == .preview {
            context.previewBridge.currentViewportAnchor { anchor in
                DispatchQueue.main.async {
                    guard document.id == documentID else { return }
                    completion(Anchor(
                        sourceLine: anchor?.sourceLine,
                        ratio: anchor?.ratio ?? document.scrollRatio
                    ))
                }
            }
        } else {
            let anchor = Anchor(
                sourceLine: context.editorBridge.currentSourceLineAtViewportCenter(),
                ratio: context.editorBridge.currentScrollRatio() ?? document.scrollRatio
            )
            DispatchQueue.main.async {
                guard document.id == documentID else { return }
                completion(anchor)
            }
        }
    }

    // MARK: - Restore

    /// Re-centers the live surface on a previously captured anchor. For the editor the
    /// caller decides when layout has settled; for the preview the restore is queued
    /// and the bridge applies it once any in-flight body update lands.
    static func restore(
        _ anchor: Anchor,
        context: Context,
        editorDelay: TimeInterval = 0.05
    ) {
        let document = context.document
        let documentID = document.id
        document.scrollRatio = anchor.ratio

        if document.mode == .preview {
            context.previewBridge.setPendingViewportRestore(
                sourceLine: anchor.sourceLine,
                ratio: anchor.ratio,
                applyImmediately: true
            )
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + editorDelay) {
                guard document.id == documentID, document.mode == .edit else { return }
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
        capture(context: context) { anchor in
            session.arm(anchor: anchor, context: context)
        }
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
