import SwiftUI

/// Shared measurements for compact-mode toolbar controls (pill strip + mode toggle).
enum ToolbarMetrics {
    /// Single row height so the edit/preview control aligns with the tab pill strip.
    static let compactPillRowHeight: CGFloat = 40
}

struct ModeToggleToolbarItem: ToolbarContent {
    @Binding var mode: EditMode

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Mode", selection: $mode) {
                Label("Edit", systemImage: "pencil")
                    .tag(EditMode.edit)
                Label("Preview", systemImage: "eye")
                    .tag(EditMode.preview)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .controlSize(.regular)
            .frame(width: 72)
            .frame(height: ToolbarMetrics.compactPillRowHeight)
            .layoutPriority(1)
            .help("Toggle Edit / Preview  ⌘⇧P")
        }
    }
}
