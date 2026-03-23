import Foundation
import Observation

// MARK: - Global drag state

/// Singleton that holds the in-flight tab drag state so any window's drop delegate
/// can identify the source document and store, regardless of which window started the drag.
/// @Observable so SwiftUI views can react to drag state changes for visual feedback.
@Observable
final class TabDragState {
    static let shared = TabDragState()
    private init() {}

    var draggingDocumentID: UUID?
    /// Accumulated translation since drag began (deltaX/Y from NSEvent monitors, SwiftUI-coord-space).
    var dragTranslation: CGSize = .zero

    /// Weak reference — not observed; views don't need to react to this changing.
    @ObservationIgnored weak var sourceStore: DocumentStore?

    func begin(documentID: UUID, from store: DocumentStore) {
        draggingDocumentID = documentID
        dragTranslation = .zero
        sourceStore = store
    }

    /// Called by `performDrop` when a drop target accepts the drag. Clears the document ID
    /// so the mouse-up monitor doesn't also fire `detachToNewWindow`.
    func clear() {
        draggingDocumentID = nil
        dragTranslation = .zero
    }

    /// Called after detach-to-new-window or on any cancellation path.
    func reset() {
        draggingDocumentID = nil
        dragTranslation = .zero
        sourceStore = nil
    }
}
