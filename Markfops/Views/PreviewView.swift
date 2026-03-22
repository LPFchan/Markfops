import SwiftUI
import WebKit

// MARK: - Bridge

/// Shared reference that lets EditorContainerView call into the WKWebView coordinator
/// (e.g. to extract text before switching to edit mode).
final class PreviewBridge {
    weak var coordinator: PreviewView.Coordinator?

    func extractText(completion: @escaping (String) -> Void) {
        guard let coord = coordinator else { completion(""); return }
        coord.extractText(completion: completion)
    }

    func resetEditingFlag() {
        coordinator?.isEditingInView = false
    }
}

// MARK: - View

/// WYSIWYG editing surface: renders markdown as HTML and makes it directly editable.
/// The user sees formatted output (headings, bold, code blocks, tables) and can click
/// anywhere and start typing — just like a word processor.
/// Paste and Match Style is enforced: all pasted content is stripped to plain text.
struct PreviewView: NSViewRepresentable {
    let htmlContent: String
    let bridge: PreviewBridge
    var onTextChange: ((String) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "textChanged")

        let config = WKWebViewConfiguration()
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true

        context.coordinator.webView = webView
        context.coordinator.onTextChange = onTextChange
        bridge.coordinator = context.coordinator

        if !htmlContent.isEmpty {
            context.coordinator.lastLoadedHTML = htmlContent
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTextChange = onTextChange

        // Don't reload while the user is actively editing inside the web view.
        guard !context.coordinator.isEditingInView,
              !htmlContent.isEmpty,
              htmlContent != context.coordinator.lastLoadedHTML else { return }

        context.coordinator.lastLoadedHTML = htmlContent
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var lastLoadedHTML: String = ""
        var isEditingInView = false
        var onTextChange: ((String) -> Void)?

        // JS posts debounced innerText here after the user pauses typing.
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "textChanged",
                  let text = message.body as? String else { return }
            isEditingInView = true
            onTextChange?(text)
        }

        // After HTML loads, enable editing and wire up JS helpers.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let js = """
            (function() {
                var article = document.querySelector('.markdown-body');
                if (!article) return;

                // Make content editable — click anywhere and type
                article.setAttribute('contenteditable', 'true');
                article.setAttribute('spellcheck', 'true');
                article.style.outline = 'none';
                article.style.cursor = 'text';
                article.style.caretColor = 'auto';

                // Paste and Match Style: always strip rich-text formatting on paste
                article.addEventListener('paste', function(e) {
                    e.preventDefault();
                    var plain = (e.clipboardData || window.clipboardData).getData('text/plain');
                    document.execCommand('insertText', false, plain);
                });

                // Notify Swift of text changes (debounced 400 ms)
                var debounceTimer;
                article.addEventListener('input', function() {
                    clearTimeout(debounceTimer);
                    debounceTimer = setTimeout(function() {
                        window.webkit.messageHandlers.textChanged.postMessage(article.innerText);
                    }, 400);
                });

                // Keyboard formatting shortcuts inside the viewer
                article.addEventListener('keydown', function(e) {
                    if (!e.metaKey) return;
                    if (e.key === 'b') { e.preventDefault(); document.execCommand('bold'); }
                    if (e.key === 'i') { e.preventDefault(); document.execCommand('italic'); }
                    if (e.key === 'u') { e.preventDefault(); /* underline — no-op in md */ }
                });
            })();
            """
            webView.evaluateJavaScript(js)
        }

        /// Pull the current plain text out of the editable article element.
        func extractText(completion: @escaping (String) -> Void) {
            webView?.evaluateJavaScript(
                "document.querySelector('.markdown-body')?.innerText ?? ''"
            ) { result, _ in
                DispatchQueue.main.async {
                    completion((result as? String) ?? "")
                }
            }
        }

        // Open links in the default browser.
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
}
