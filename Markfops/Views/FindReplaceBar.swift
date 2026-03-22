import SwiftUI

/// Thin find/replace bar that forwards to NSTextView's built-in find bar.
/// NSTextView handles find/replace natively via usesFindBar = true and Cmd+F.
/// This view is kept as a placeholder for future custom enhancements.
struct FindReplaceBar: View {
    @Binding var isVisible: Bool

    var body: some View {
        EmptyView()
    }
}
