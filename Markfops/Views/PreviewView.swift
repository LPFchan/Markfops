import SwiftUI
import WebKit

struct PreviewView: NSViewRepresentable {
    let htmlContent: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(htmlContent, baseURL: Bundle.main.resourceURL)
    }

    func makeCoordinator() -> PreviewNavigationDelegate {
        PreviewNavigationDelegate()
    }
}
