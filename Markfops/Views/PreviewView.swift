import SwiftUI
import WebKit

struct PreviewView: NSViewRepresentable {
    let htmlContent: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        // Load initial content
        if !htmlContent.isEmpty {
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only reload when content actually changed to avoid empty-flash on every render pass
        guard !htmlContent.isEmpty,
              htmlContent != context.coordinator.lastLoadedHTML else { return }
        context.coordinator.lastLoadedHTML = htmlContent
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    func makeCoordinator() -> PreviewNavigationDelegate {
        PreviewNavigationDelegate()
    }
}
