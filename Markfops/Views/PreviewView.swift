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

    func scrollToHeading(_ heading: HeadingNode) {
        coordinator?.scrollToHeading(heading)
    }

    func setPendingScrollRatio(_ ratio: Double) {
        coordinator?.pendingScrollRatio = ratio
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
    var onScrollChange: ((Double) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "textChanged")
        userContent.add(context.coordinator, name: "scrollChanged")

        let config = WKWebViewConfiguration()
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true

        context.coordinator.webView = webView
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onScrollChange = onScrollChange
        bridge.coordinator = context.coordinator

        if !htmlContent.isEmpty {
            context.coordinator.lastLoadedHTML = htmlContent
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onScrollChange = onScrollChange

        // Don't reload while the user is actively editing inside the web view.
        let isEditing = context.coordinator.isEditingInView
        let isEmpty = htmlContent.isEmpty
        let isSame = htmlContent == context.coordinator.lastLoadedHTML
        guard !isEditing, !isEmpty, !isSame else { return }

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
        var onScrollChange: ((Double) -> Void)?
        /// Ratio [0,1] to scroll to once the next page load finishes.
        var pendingScrollRatio: Double?

        // JS posts messages here: debounced innerText ("textChanged") and scroll ratio ("scrollChanged").
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "textChanged", let text = message.body as? String {
                isEditingInView = true
                onTextChange?(text)
            } else if message.name == "scrollChanged", let ratio = message.body as? Double {
                onScrollChange?(ratio)
            }
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

                // Report scroll position (throttled) so Swift can sync back to editor
                var scrollThrottle;
                window.addEventListener('scroll', function() {
                    if (scrollThrottle) return;
                    scrollThrottle = setTimeout(function() {
                        scrollThrottle = null;
                        var total = document.documentElement.scrollHeight - window.innerHeight;
                        if (total > 0) {
                            var midRatio = (window.scrollY + window.innerHeight / 2) / (total + window.innerHeight);
                            window.webkit.messageHandlers.scrollChanged.postMessage(midRatio);
                        }
                    }, 100);
                }, { passive: true });
            })();
            """
            webView.evaluateJavaScript(js)

            // Apply deferred scroll ratio now that the page is ready
            if let ratio = pendingScrollRatio {
                pendingScrollRatio = nil
                let scrollJS = """
                (function() {
                    var total = document.documentElement.scrollHeight - window.innerHeight;
                    if (total > 0) { window.scrollTo(0, Math.round(\(ratio) * (total + window.innerHeight) - window.innerHeight / 2)); }
                })();
                """
                webView.evaluateJavaScript(scrollJS)
            }
        }

        /// Scroll to a heading in the preview and flash it with a highlight.
        func scrollToHeading(_ heading: HeadingNode) {
            let escaped = heading.title
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let js = """
            (function() {
                var all = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
                var target = null;
                for (var h of all) {
                    if (h.textContent.trim() === '\(escaped)') { target = h; break; }
                }
                if (!target) return;
                target.scrollIntoView({ behavior: 'smooth', block: 'start' });
                target.style.transition = 'background-color 0.1s ease-in';
                target.style.borderRadius = '4px';
                target.style.backgroundColor = 'rgba(255,200,0,0.35)';
                setTimeout(function() {
                    target.style.transition = 'background-color 0.7s ease-out';
                    target.style.backgroundColor = 'transparent';
                }, 300);
            })();
            """
            webView?.evaluateJavaScript(js)
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
