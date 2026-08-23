import AppKit
import SwiftUI

@main
struct MarkfopsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Markfops", id: "document") {
            ContentView()
                .environment(appDelegate.store)
                .focusedSceneValue(\.documentStore, appDelegate.store)
                .onOpenURL { url in
                    appDelegate.open(url: url)
                }
                .background {
                    DocumentWindowAccessor { window in
                        appDelegate.registerDocumentWindow(window)
                    }
                    .frame(width: 0, height: 0)
                }
                .frame(minHeight: 500)
        }
        // Match sidebar-mode titlebar/toolbar height; `.unifiedCompact` (often the default) is shorter.
        .windowToolbarStyle(.unified)
        .commands {
            MarkfopsCommands()
        }
        .defaultSize(width: 660, height: 700)

        Settings {
            SettingsView()
        }
    }
}

private struct DocumentWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        resolveWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        resolveWindow(for: nsView)
    }

    private func resolveWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            onResolve(window)
        }
    }
}
