import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

// MARK: - Tab drag state

/// Shared native drag state. The source store is weak because ownership transfers to the
/// coordinator as soon as a drop is accepted. `UTType.data` is intentional: a custom exported UTI
/// would require Info.plist declarations and produces warnings in this app's generated metadata.
@Observable
final class TabDragState {
    static let shared = TabDragState()
    static let documentDragType = UTType.data

    var draggingDocumentID: UUID?
    var dragTranslation: CGSize = .zero
    var wasInDetachZone = false

    @ObservationIgnored weak var sourceStore: DocumentStore?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var finishTask: Task<Void, Never>?
    @ObservationIgnored private var dragOrigin: NSPoint = .zero

    private init() {}

    static func displacement(from origin: NSPoint, to location: NSPoint) -> CGSize {
        CGSize(width: location.x - origin.x, height: origin.y - location.y)
    }

    static func shouldDetach(translation: CGSize, threshold: CGFloat = 60) -> Bool {
        max(abs(translation.width), abs(translation.height)) > threshold
    }

    func begin(documentID: UUID, from store: DocumentStore) {
        reset()
        draggingDocumentID = documentID
        sourceStore = store
        dragOrigin = NSEvent.mouseLocation
        startPolling(documentID: documentID)
    }

    func clear() {
        pollingTask?.cancel()
        finishTask?.cancel()
        pollingTask = nil
        finishTask = nil
        draggingDocumentID = nil
        dragTranslation = .zero
        wasInDetachZone = false
        sourceStore = nil
        dragOrigin = .zero
    }

    func reset() {
        clear()
    }

    private func startPolling(documentID: UUID) {
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.draggingDocumentID == documentID else { return }
                self.samplePointer()

                // AppKit's native drag tracking can swallow both local and global mouse events.
                // The pressed-button state remains observable while the pointer is outside the
                // app, so polling gives us a reliable end-of-drag signal without a timeout.
                guard NSEvent.pressedMouseButtons & (1 << 0) != 0 else {
                    self.scheduleFinish(documentID: documentID)
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: 16_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func samplePointer() {
        let translation = Self.displacement(from: dragOrigin, to: NSEvent.mouseLocation)
        dragTranslation = translation
        if Self.shouldDetach(translation: translation) {
            wasInDetachZone = true
        }
    }

    private func scheduleFinish(documentID: UUID) {
        guard finishTask == nil else { return }

        // DropDelegate.performDrop can arrive just after the button is released. Defer the
        // detach decision briefly so an accepted same/cross-window drop clears this state first.
        finishTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
            guard let self, self.draggingDocumentID == documentID else { return }
            let shouldDetach = self.wasInDetachZone
            let sourceStore = self.sourceStore
            self.clear()
            if shouldDetach, let sourceStore {
                sourceStore.coordinator?.detach(documentID: documentID, from: sourceStore.windowID)
            }
        }
    }
}
