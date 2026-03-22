import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Colored square badge showing the first letter of the document title.
/// When the document has no H1 heading, shows the system Finder icon for the
/// file (or the generic plain-text icon for unsaved documents) loaded asynchronously.
struct FaviconBadge: View {
    let letter: String
    var size: CGFloat = 24
    var fontSize: CGFloat = 13
    var fileURL: URL? = nil
    var hasH1: Bool = true

    @State private var cachedIcon: NSImage? = nil

    var body: some View {
        Group {
            if !hasH1, let icon = cachedIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor)
                        .frame(width: size, height: size)
                    Text(letter)
                        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
        }
        .task(id: "\(hasH1)-\(fileURL?.path ?? "")") {
            guard !hasH1 else { cachedIcon = nil; return }
            cachedIcon = await loadIcon(for: fileURL)
        }
    }

    private func loadIcon(for url: URL?) async -> NSImage {
        await Task.detached(priority: .utility) {
            if let url {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            if let type = UTType(filenameExtension: "md") {
                return NSWorkspace.shared.icon(for: type)
            }
            return NSWorkspace.shared.icon(for: .plainText)
        }.value
    }
}
