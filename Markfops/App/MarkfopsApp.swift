import SwiftUI

@main
struct MarkfopsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.store)
                .focusedSceneValue(\.documentStore, appDelegate.store)
                .onOpenURL { url in
                    appDelegate.store.open(url: url)
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
