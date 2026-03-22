import SwiftUI

struct TOCItemView: View {
    let heading: HeadingNode
    let isHighlighted: Bool
    let isCollapsible: Bool
    let isCollapsed: Bool
    let onTap: () -> Void
    let onToggleCollapse: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Indent — H2 is the new root (H1 is shown as the row title), so subtract 2
            Spacer()
                .frame(width: CGFloat(max(0, heading.level - 2)) * 12)

            // Collapse chevron (reserved space for all rows so text aligns)
            Button(action: {
                withAnimation(.spring(duration: 0.22)) { onToggleCollapse() }
            }) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isCollapsible ? 1 : 0)
            .disabled(!isCollapsible)

            // Heading title — tapping scrolls to it
            Button(action: onTap) {
                Text(heading.title)
                    .font(.system(size: 12))
                    .foregroundColor(isHighlighted ? .accentColor : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .animation(.easeOut(duration: 0.25), value: isHighlighted)
    }
}
