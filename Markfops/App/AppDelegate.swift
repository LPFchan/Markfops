import AppKit
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {

    private static let documentWindowIdentifier = NSUserInterfaceItemIdentifier("Markfops.DocumentWindow")

    /// Single source of truth — owned here so all lifecycle callbacks can reach it.
    let store = DocumentStore()

    weak private var documentWindow: NSWindow?

    var mainDocumentWindow: NSWindow? { documentWindow }

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
            self.documentWindow?.setFrameAutosaveName("MarkfopsMain")
            // Set initial proxy icon for the active document (if a file was restored).
            self.documentWindow?.representedURL = self.store.activeDocument?.fileURL
        }
    }

    /// Called by the SwiftUI document scene once its AppKit window exists.
    /// Keeping this reference lets file-open events target the existing window even when a
    /// settings window is currently key.
    func registerDocumentWindow(_ window: NSWindow) {
        documentWindow = window
        window.identifier = Self.documentWindowIdentifier
        window.setFrameAutosaveName("MarkfopsMain")
        window.representedURL = store.activeDocument?.fileURL
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

    func open(url: URL) {
        store.open(url: url)
        presentDocumentWindow()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { store.open(url: url) }
        presentDocumentWindow()
    }

    private func presentDocumentWindow() {
        NSApp.activate(ignoringOtherApps: true)
        bringDocumentWindowForward(after: 0)
    }

    private func bringDocumentWindowForward(after delay: TimeInterval, attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let window = self.documentWindow
                ?? NSApp.windows.first(where: { $0.identifier == Self.documentWindowIdentifier })
            guard let window else {
                // The SwiftUI Window scene may still be materializing after a cold launch or
                // after its only document window was closed. Give it a few run-loop turns.
                guard attempt < 12 else { return }
                self.bringDocumentWindowForward(after: 0.05, attempt: attempt + 1)
                return
            }
            self.documentWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Session persistence

    func applicationWillTerminate(_ notification: Notification) {
        persistSession()
    }

    private func restoreLastSession() {
        store.restorePersistedSession()
    }

    private func persistSession() {
        store.persistSession()
    }
}
