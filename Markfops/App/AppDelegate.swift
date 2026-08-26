import AppKit
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// App-lifetime owner for every document scene and every recovery write.
    let coordinator = DocumentCoordinator()

    /// Sparkle 2 — feed URL and signing key live in `Info.plist` (`SUFeedURL`, `SUPublicEDKey`).
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // MARK: - Launch

    func applicationWillFinishLaunching(_ notification: Notification) {
        CompactTabContextMenuController.start()
        NSWindow.allowsAutomaticWindowTabbing = false  // remove View > "Show Tab Bar" / "Show All Tabs"
        AuxiliaryWindowCloseHandler.start()
        restoreLastSession()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Scene registration owns per-window frame and proxy state. Recovery has already been
        // loaded in applicationWillFinishLaunching, but a scene may not exist yet.
        coordinator.restorePersistedSession()
    }

    // MARK: - Quit

    /// Returns .terminateLater so we can show a sheet; replies via NSApp.reply after user decides.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let dirty = coordinator.sessions.values.flatMap { $0.store.documents }.filter(\.isDirty)
        guard !dirty.isEmpty else { return .terminateNow }
        coordinator.reviewUnsavedForQuit { shouldQuit in
            NSApp.reply(toApplicationShouldTerminate: shouldQuit)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Open from Finder / Dock drag

    func open(url: URL) {
        coordinator.open(url: url)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        coordinator.open(urls: urls)
    }

    // MARK: - Session persistence

    func applicationWillTerminate(_ notification: Notification) {
        persistSession()
    }

    private func restoreLastSession() {
        coordinator.restorePersistedSession()
    }

    private func persistSession() {
        coordinator.persistSession()
    }
}
