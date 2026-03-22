import SwiftUI

struct TOCItemView: View {
    let heading: HeadingNode
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                // Indent based on heading level
                Spacer()
                    .frame(width: CGFloat((heading.level - 1)) * 12)

                Image(systemName: "text.justify.left")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text(heading.title)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }
}
