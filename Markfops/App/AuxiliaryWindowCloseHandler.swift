import AppKit

/// Lets Cmd+W close auxiliary windows (Settings, About, Sparkle's update UI).
///
/// MarkfopsCommands replaces the File menu's saveItem group with close buttons
/// that forward to the focused document store. Auxiliary windows have no document
/// store in their focus chain, so the system ends up with no working Cmd+W there
/// at all; SwiftUI's own Close command is gone from the menu.
///
/// This monitor catches Cmd+W before menu dispatch and closes the key window when
/// it is not a document window. Document windows are left alone: the event falls
/// through to the File menu, where the document-scoped close logic lives.
enum AuxiliaryWindowCloseHandler {
    static func start() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "w",
                  let window = NSApp.keyWindow,
                  !isDocumentWindow(window)
            else { return event }
            window.close()
            return nil
        }
    }

    private static func isDocumentWindow(_ window: NSWindow) -> Bool {
        // Document scenes get autosave names of the form "Markfops-<uuid>";
        // Settings, About, and Sparkle windows never do.
        window.frameAutosaveName.hasPrefix("Markfops-")
    }
}
