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
    /// Becomes true once the pill has entered the detach zone (threshold exceeded).
    /// The mouseUp handler uses this instead of raw distance to decide whether to detach.
    var wasInDetachZone: Bool = false

    /// Weak reference — not observed; views don't need to react to this changing.
    @ObservationIgnored weak var sourceStore: DocumentStore?
    /// Safety-net: auto-resets drag state if the mouseUp monitor never fires (e.g. system swallows the event).
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    func begin(documentID: UUID, from store: DocumentStore) {
        draggingDocumentID = documentID
        dragTranslation = .zero
        wasInDetachZone = false
        sourceStore = store
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.draggingDocumentID == documentID else { return }
            self.reset()
        }
    }

    /// Called by `performDrop` when a drop target accepts the drag. Clears the document ID
    /// so the mouse-up monitor doesn't also fire `detachToNewWindow`.
    func clear() {
        timeoutTask?.cancel()
        timeoutTask = nil
        draggingDocumentID = nil
        dragTranslation = .zero
        wasInDetachZone = false
    }

    /// Called after detach-to-new-window or on any cancellation path.
    func reset() {
        timeoutTask?.cancel()
        timeoutTask = nil
        draggingDocumentID = nil
        dragTranslation = .zero
        sourceStore = nil
        wasInDetachZone = false
    }
}
