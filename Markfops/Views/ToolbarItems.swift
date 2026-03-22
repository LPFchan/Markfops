import SwiftUI

struct ModeToggleToolbarItem: ToolbarContent {
    @Binding var mode: EditMode

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Mode", selection: $mode) {
                Label("Edit", systemImage: "pencil").tag(EditMode.edit)
                Label("Preview", systemImage: "eye").tag(EditMode.preview)
            }
            .pickerStyle(.segmented)
            .frame(width: 110)
            .help("Toggle Edit / Preview  ⌘⇧P")
        }
    }
}
