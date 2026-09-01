import Sparkle
import SwiftUI

struct SettingsView: View {
    let updaterController: SPUStandardUpdaterController

    @AppStorage("editorFontSize") private var fontSize: Double = 15
    @AppStorage("editorFontFamily") private var fontFamily: String = "SF Mono"

    var body: some View {
        // Form always embeds a scroll view on macOS; a fixed VStack keeps the
        // pane at exactly the size of its content with no scrollbar.
        VStack(alignment: .leading, spacing: 20) {
            settingsSection { Text("Updates") } content: {
                HStack {
                    Button("Check for Updates…") {
                        updaterController.checkForUpdates(nil)
                    }
                    Spacer()
                    // Sparkle persists this choice itself via SPUUpdater.
                    Toggle(isOn: Binding(
                        get: { updaterController.updater.automaticallyChecksForUpdates },
                        set: { updaterController.updater.automaticallyChecksForUpdates = $0 }
                    )) {
                        Text("Automatically check for updates")
                    }
                    .toggleStyle(.checkbox)
                }
            }

            settingsSection { Text("Editor") } content: {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Stepper("\(Int(fontSize))pt", value: $fontSize, in: 10...32, step: 1)
                }

                HStack {
                    Text("Font")
                    Spacer()
                    Picker("Font", selection: $fontFamily) {
                        Text("SF Mono").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Monaco").tag("Monaco")
                        Text("Courier New").tag("Courier New")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(WindowSizingToFit())
    }

    private func settingsSection<Content: View>(
        @ViewBuilder title: () -> Text,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            title().font(.headline)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// Pins the hosting window's content size to the view's ideal size so the pane
/// is never scrollable or larger than its content.
private struct WindowSizingToFit: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.fit(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.fit(nsView) }
    }

    private static func fit(_ view: NSView) {
        guard let window = view.window,
              let contentView = window.contentView else { return }
        let size = contentView.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        window.setContentSize(size)
        window.styleMask.remove(.resizable)
    }
}
