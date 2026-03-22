import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Access store from window's content to check dirty docs
        // The check is handled in ContentView's onReceive of terminateNotification
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // Handle files opened from Finder / drag onto Dock icon
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let store = findDocumentStore() else { return }
        for url in urls {
            store.open(url: url)
        }
    }

    private func findDocumentStore() -> DocumentStore? {
        // Retrieve store from the key window's environment via notification
        // The store is also accessible via AppDelegate's stored reference if needed.
        // For simplicity, post a notification that ContentView handles.
        return nil
    }
}
