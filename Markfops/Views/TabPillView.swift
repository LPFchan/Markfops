import SwiftUI

struct TabPillView: View {
    let document: Document
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            FaviconBadge(letter: document.faviconLetter, size: 18, fontSize: 10)

            Text(document.displayTitle)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120)

            if document.isDirty {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
            }

            if isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 14, height: 14)
            } else if !document.isDirty {
                Spacer().frame(width: 14)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isActive
                    ? Color(NSColor.controlAccentColor).opacity(0.15)
                    : (isHovered ? Color(NSColor.quaternaryLabelColor) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
    }
}
