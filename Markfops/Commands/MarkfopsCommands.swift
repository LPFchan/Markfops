import SwiftUI

struct MarkfopsCommands: Commands {
    @FocusedValue(\.documentStore) private var store
    @FocusedValue(\.sidebarVisibility) private var sidebarVisibility

    var body: some Commands {
        // MARK: File menu
        CommandGroup(replacing: .newItem) {
            Button("New") {
                store?.newDocument()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Tab") {
                store?.newDocument()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("New Window") {
                let newStore = DocumentStore()
                newStore.newDocument()
                let rootView = ContentView()
                    .environment(newStore)
                    .focusedSceneValue(\.documentStore, newStore)
                    .frame(minWidth: 700, minHeight: 500)
                let controller = NSHostingController(rootView: rootView)
                let window = NSWindow(contentViewController: controller)
                window.setContentSize(NSSize(width: 900, height: 650))
                window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
                newStore.managedWindow = window
                window.center()
                window.makeKeyAndOrderFront(nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open…") {
                openFile()
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Menu("Open Recent") {
                let recents = NSDocumentController.shared.recentDocumentURLs
                if recents.isEmpty {
                    Text("No Recent Documents").foregroundColor(.secondary)
                } else {
                    ForEach(recents.prefix(10), id: \.self) { url in
                        Button(url.deletingPathExtension().lastPathComponent) {
                            store?.open(url: url)
                        }
                    }
                    Divider()
                    Button("Clear Menu") {
                        NSDocumentController.shared.clearRecentDocuments(nil)
                    }
                }
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                guard let doc = store?.activeDocument else { return }
                try? store?.save(doc)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Save As…") {
                guard let doc = store?.activeDocument else { return }
                try? store?.saveAs(doc)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Duplicate") {
                guard let doc = store?.activeDocument else { return }
                store?.duplicate(doc)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button("Rename…") {
                guard let doc = store?.activeDocument else { return }
                store?.rename(doc)
            }

            Button("Move To…") {
                guard let doc = store?.activeDocument else { return }
                store?.moveTo(doc)
            }

            Divider()

            Button("Revert to Saved") {
                guard let doc = store?.activeDocument else { return }
                store?.revertToSaved(doc)
            }
            .disabled(store?.activeDocument?.fileURL == nil || store?.activeDocument?.isDirty == false)

            Divider()

            Button("Print…") {
                NSApp.sendAction(#selector(NSView.printView(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("p", modifiers: .command)

            Button("Export as PDF…") {
                guard let doc = store?.activeDocument else { return }
                store?.exportAsPDF(doc)
            }

            Divider()

            Button(store?.documents.isEmpty ?? true ? "Close Window" : "Close Tab") {
                if let s = store, !s.documents.isEmpty, let id = s.activeID {
                    s.close(id: id)
                } else {
                    NSApp.keyWindow?.performClose(nil)
                }
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("Close Window") {
                NSApp.keyWindow?.performClose(nil)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        // MARK: Find (Edit menu, after pasteboard group)
        CommandGroup(after: .pasteboard) {
            Menu("Find") {
                Button("Find…") { triggerFinder(.showFindInterface) }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(store?.activeDocument?.mode != .edit)

                Button("Find and Replace…") { triggerFinder(.showReplaceInterface) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    .disabled(store?.activeDocument?.mode != .edit)

                Divider()

                Button("Find Next") { triggerFinder(.nextMatch) }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(store?.activeDocument?.mode != .edit)

                Button("Find Previous") { triggerFinder(.previousMatch) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(store?.activeDocument?.mode != .edit)

                Button("Use Selection for Find") { triggerFinder(.setSearchString) }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(store?.activeDocument?.mode != .edit)
            }
        }

        // MARK: View menu — inject after the built-in toolbar group to avoid creating a duplicate "View" menu
        CommandGroup(after: .toolbar) {
            Button("Toggle Edit / Preview") {
                guard let doc = store?.activeDocument else { return }
                doc.mode = doc.mode == .edit ? .preview : .edit
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button(sidebarVisibility?.wrappedValue == .detailOnly ? "Show Sidebar" : "Hide Sidebar") {
                withAnimation {
                    if sidebarVisibility?.wrappedValue == .detailOnly {
                        sidebarVisibility?.wrappedValue = .all
                    } else {
                        sidebarVisibility?.wrappedValue = .detailOnly
                    }
                }
            }
            .keyboardShortcut("\\", modifiers: .command)

            Divider()

            Button("Next Tab") {
                store?.selectNext()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Previous Tab") {
                store?.selectPrevious()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Divider()

            Button("Increase Font Size") {
                let size = UserDefaults.standard.double(forKey: "editorFontSize")
                UserDefaults.standard.set(min((size > 0 ? size : 15) + 1, 32), forKey: "editorFontSize")
            }
            .keyboardShortcut("=", modifiers: .command)

            Button("Decrease Font Size") {
                let size = UserDefaults.standard.double(forKey: "editorFontSize")
                UserDefaults.standard.set(max((size > 0 ? size : 15) - 1, 10), forKey: "editorFontSize")
            }
            .keyboardShortcut("-", modifiers: .command)
        }

        // MARK: Format menu
        CommandMenu("Format") {
            Button("Bold") {
                NSApp.sendAction(#selector(NSTextView.wrapBold), to: nil, from: nil)
            }
            .keyboardShortcut("b", modifiers: .command)

            Button("Italic") {
                NSApp.sendAction(#selector(NSTextView.wrapItalic), to: nil, from: nil)
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("Inline Code") {
                NSApp.sendAction(#selector(NSTextView.wrapCode), to: nil, from: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .option])

            Divider()

            // Paste and Match Style — strips RTF/rich formatting, inserts plain text.
            // In Edit mode: handled natively by NSTextView (pasteAsPlainText:).
            // In Preview/WYSIWYG mode: enforced automatically via the JS paste interceptor.
            Button("Paste and Match Style") {
                NSApp.sendAction(#selector(NSTextView.pasteAsPlainText(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("v", modifiers: [.command, .option, .shift])
        }
    }

    /// Forwards a text finder action to the first responder regardless of current focus.
    private func triggerFinder(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: item)
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "md")!,
            .init(filenameExtension: "markdown")!,
            .plainText
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store?.open(url: url) }
    }
}

// MARK: - NSTextView formatting selectors

extension NSTextView {
    @objc func wrapBold() {
        (self as? MarkdownNSTextView)?.wrapSelection(prefix: "**", suffix: "**")
    }
    @objc func wrapItalic() {
        (self as? MarkdownNSTextView)?.wrapSelection(prefix: "_", suffix: "_")
    }
    @objc func wrapCode() {
        (self as? MarkdownNSTextView)?.wrapSelection(prefix: "`", suffix: "`")
    }
}
