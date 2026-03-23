import AppKit
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Single source of truth — owned here so all lifecycle callbacks can reach it.
    let store = DocumentStore()

    /// Sparkle 2 — feed URL and signing key live in `Info.plist` (`SUFeedURL`, `SUPublicEDKey`).
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // MARK: - Launch

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false  // remove View > "Show Tab Bar" / "Show All Tabs"
        restoreLastSession()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            // Autosave the window frame so position/size survives restarts.
            NSApp.mainWindow?.setFrameAutosaveName("MarkfopsMain")
            // Set initial proxy icon for the active document (if a file was restored).
            NSApp.mainWindow?.representedURL = self.store.activeDocument?.fileURL
        }
    }

    // MARK: - Quit

    /// Returns .terminateLater so we can show a sheet; replies via NSApp.reply after user decides.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let dirty = store.documents.filter(\.isDirty)
        guard !dirty.isEmpty else { return .terminateNow }
        store.reviewUnsavedForQuit { shouldQuit in
            NSApp.reply(toApplicationShouldTerminate: shouldQuit)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Open from Finder / Dock drag

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { store.open(url: url) }
    }

    // MARK: - Session persistence

    func applicationWillTerminate(_ notification: Notification) {
        persistSession()
    }

    private func restoreLastSession() {
        let strings = UserDefaults.standard.stringArray(forKey: "lastOpenDocuments") ?? []
        let urls = strings
            .compactMap { URL(string: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        for url in urls { store.open(url: url) }
    }

    private func persistSession() {
        let strings = store.documents.compactMap { $0.fileURL?.absoluteString }
        UserDefaults.standard.set(strings, forKey: "lastOpenDocuments")
    }
}
