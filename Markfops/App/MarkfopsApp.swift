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
                .frame(minWidth: 700, minHeight: 500)
        }
        .commands {
            MarkfopsCommands()
        }
        .defaultSize(width: 660, height: 700)

        Settings {
            SettingsView()
        }
    }
}
