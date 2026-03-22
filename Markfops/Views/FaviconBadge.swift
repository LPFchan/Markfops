import SwiftUI

/// Colored square badge showing the first letter of the document title.
struct FaviconBadge: View {
    let letter: String
    var size: CGFloat = 24
    var fontSize: CGFloat = 13

    var body: some View {
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
