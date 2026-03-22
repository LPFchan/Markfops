import SwiftUI

struct TOCItemView: View {
    let heading: HeadingNode
    let isHighlighted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Spacer()
                    .frame(width: CGFloat((heading.level - 1)) * 12)

                Image(systemName: "text.justify.left")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text(heading.title)
                    .font(.system(size: 12))
                    .foregroundColor(isHighlighted ? .accentColor : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.25), value: isHighlighted)
    }
}
