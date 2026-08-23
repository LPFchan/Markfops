import Foundation
import Observation
import UniformTypeIdentifiers

// MARK: - Tab drag state

/// Singleton that holds the in-flight tab drag state so drop delegates can identify the
/// document being reordered within the document window.
/// @Observable so SwiftUI views can react to drag state changes for visual feedback.
@Observable
final class TabDragState {
    static let shared = TabDragState()
    static let documentDragType = UTType.data
    private init() {}

    var draggingDocumentID: UUID?
    /// Safety-net: auto-resets drag state if a system drag ends without a drop callback.
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    func begin(documentID: UUID) {
        draggingDocumentID = documentID
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.draggingDocumentID == documentID else { return }
            self.reset()
        }
    }

    /// Called by `performDrop` when a drop target accepts the drag.
    func clear() {
        timeoutTask?.cancel()
        timeoutTask = nil
        draggingDocumentID = nil
    }

    /// Called on any cancellation path.
    func reset() {
        timeoutTask?.cancel()
        timeoutTask = nil
        draggingDocumentID = nil
    }
}
