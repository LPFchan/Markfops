import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Colored square badge showing the first letter of the document title.
/// When the document has no H1 heading, shows the system Finder icon for the
/// file type (or the generic plain-text icon for unsaved documents).
struct FaviconBadge: View {
    let letter: String
    var size: CGFloat = 24
    var fontSize: CGFloat = 13
    var fileURL: URL? = nil
    var hasH1: Bool = true

    var body: some View {
        Group {
            if !hasH1 {
                Image(nsImage: DocumentFileIconCache.shared.icon(for: fileURL))
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
    }
}

/// File-type icons are shared across rows. Markfops opens Markdown documents, so hundreds of
/// distinct file URLs should still resolve through one NSWorkspace lookup and appear immediately.
@MainActor
final class DocumentFileIconCache {
    static let shared = DocumentFileIconCache()

    private var iconsByType: [String: NSImage] = [:]
    private(set) var workspaceLookupCount = 0

    func icon(for url: URL?) -> NSImage {
        let fileExtension = url?.pathExtension.lowercased()
        let key = fileExtension.flatMap { $0.isEmpty ? nil : $0 } ?? "public.plain-text"
        if let icon = iconsByType[key] { return icon }

        let type = fileExtension.flatMap { UTType(filenameExtension: $0) } ?? .plainText
        let icon = NSWorkspace.shared.icon(for: type)
        iconsByType[key] = icon
        workspaceLookupCount += 1
        return icon
    }
}
