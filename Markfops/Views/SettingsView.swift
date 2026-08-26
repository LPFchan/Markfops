import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("editorFontSize") private var fontSize: Double = 15
    @AppStorage("editorFontFamily") private var fontFamily: String = "SF Mono"

    var body: some View {
        Form {
            Section("Updates") {
                Button("Check for Updates…") {
                    (NSApp.delegate as? AppDelegate)?.updaterController.checkForUpdates(nil)
                }

                // Sparkle persists this choice itself via SPUUpdater.
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { (NSApp.delegate as? AppDelegate)?.updaterController.updater.automaticallyChecksForUpdates ?? true },
                    set: { (NSApp.delegate as? AppDelegate)?.updaterController.updater.automaticallyChecksForUpdates = $0 }
                ))
            }

            Section("Editor") {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Stepper("\(Int(fontSize))pt", value: $fontSize, in: 10...32, step: 1)
                }

                Picker("Font", selection: $fontFamily) {
                    Text("SF Mono").tag("SF Mono")
                    Text("Menlo").tag("Menlo")
                    Text("Monaco").tag("Monaco")
                    Text("Courier New").tag("Courier New")
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .background(SettingsCloseShortcutSupport())
    }
}

/// Restores the standard Close menu item so the Settings window responds to
/// Cmd+W. MarkfopsCommands replaces the `.saveItem` group with document-scoped
/// close buttons that are no-ops when no document store is focused (as in the
/// Settings window), which leaves the system with no ⌘W close item at all.
/// Document windows are unaffected: their custom close buttons appear earlier
/// in the File menu and win key-equivalent matching while a document is key.
private struct SettingsCloseShortcutSupport: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.installCloseItemIfNeeded() }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private static func installCloseItemIfNeeded() {
        guard let fileMenu = NSApp.mainMenu?.items.first(where: { $0.title == "File" })?.submenu,
              !fileMenu.items.contains(where: { $0.action == #selector(NSWindow.performClose(_:)) })
        else { return }
        fileMenu.addItem(withTitle: "Close",
                         action: #selector(NSWindow.performClose(_:)),
                         keyEquivalent: "w")
    }
}
