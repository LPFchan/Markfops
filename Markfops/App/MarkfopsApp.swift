import AppKit
import SwiftUI

@main
struct MarkfopsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Markfops", id: "document", for: UUID.self) { $windowID in
            DocumentWindowScene(windowID: $windowID, coordinator: appDelegate.coordinator)
        }
        .windowToolbarStyle(.unified)
        .commands { MarkfopsCommands() }
        .defaultSize(width: 660, height: 700)

        Settings { SettingsView() }
    }
}

private struct DocumentWindowScene: View {
    @Binding var windowID: UUID?
    let coordinator: DocumentCoordinator
    @Environment(\.openWindow) private var openWindow
    @StateObject private var identity: DocumentWindowIdentity

    init(windowID: Binding<UUID?>, coordinator: DocumentCoordinator) {
        _windowID = windowID
        self.coordinator = coordinator
        _identity = StateObject(wrappedValue: DocumentWindowIdentity(
            windowID: windowID.wrappedValue,
            coordinator: coordinator
        ))
    }

    private var id: UUID { identity.id }

    var body: some View {
        let store = coordinator.store(for: id)
        ContentView()
            .environment(store)
            .focusedSceneValue(\.documentStore, store)
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .background {
                DocumentWindowAccessor { window in
                    coordinator.registerWindow(id: id, window: window)
                    window.setFrameAutosaveName("Markfops-\(id.uuidString)")
                }
                .frame(width: 0, height: 0)
            }
            .task {
                if windowID == nil { windowID = identity.id }
                coordinator.install(openWindow: { requestedID in
                    openWindow(id: "document", value: requestedID)
                })
            }
            .frame(minHeight: 500)
    }
}

private final class DocumentWindowIdentity: ObservableObject {
    let id: UUID

    init(windowID: UUID?, coordinator: DocumentCoordinator) {
        id = windowID ?? coordinator.bootstrapWindowID()
    }
}

private struct DocumentWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> DocumentWindowProbeView {
        let view = DocumentWindowProbeView(frame: .zero)
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: DocumentWindowProbeView, context: Context) {
        nsView.onResolve = onResolve
    }
}

private final class DocumentWindowProbeView: NSView {
    var onResolve: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveWindow()
    }

    func resolveWindow() {
        guard let window else { return }
        onResolve?(window)
    }
}
