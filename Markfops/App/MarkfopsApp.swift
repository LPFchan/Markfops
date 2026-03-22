import SwiftUI

@main
struct MarkfopsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store = DocumentStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .focusedSceneValue(\.documentStore, store)
                .onOpenURL { url in
                    store.open(url: url)
                }
                .frame(minWidth: 700, minHeight: 500)
        }
        .commands {
            MarkfopsCommands()
        }
        .defaultSize(width: 1100, height: 700)

        Settings {
            SettingsView()
        }
    }
}
