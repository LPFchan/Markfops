import WebKit

/// Intercepts link clicks in the preview and opens them in the default browser.
/// Also tracks the last-loaded HTML so PreviewView can skip redundant reloads.
final class PreviewNavigationDelegate: NSObject, WKNavigationDelegate {
    var lastLoadedHTML: String = ""

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
}
