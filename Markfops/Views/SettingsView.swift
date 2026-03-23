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
            }
        }
        .padding(20)
        .frame(width: 360, height: 240)
    }
}
