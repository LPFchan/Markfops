import SwiftUI
import WebKit

// MARK: - Bridge

/// Shared reference that lets EditorContainerView call into the WKWebView coordinator
/// (e.g. to extract text before switching to edit mode).
final class PreviewBridge {
    /// Weak reference to the coordinator. Uses didSet to forward any ratio that
    /// was queued before makeNSView had a chance to create the coordinator.
    weak var coordinator: PreviewView.Coordinator? {
        didSet {
            if let ratio = _bufferedScrollRatio, let coord = coordinator {
                coord.pendingScrollRatio = ratio
                _bufferedScrollRatio = nil
            }
            if let heading = _bufferedHeading, let coord = coordinator {
                coord.pendingHeading = heading
                _bufferedHeading = nil
            }
        }
    }
    /// Holds a scroll ratio when setPendingScrollRatio is called before the
    /// coordinator exists (i.e. before makeNSView runs for this mode switch).
    private var _bufferedScrollRatio: Double?
    private var _bufferedHeading: HeadingNode?

    func extractText(completion: @escaping (String) -> Void) {
        guard let coord = coordinator else { completion(""); return }
        coord.extractText(completion: completion)
    }

    @discardableResult
    func focus() -> Bool {
        coordinator?.focusWebView() ?? false
    }

    func find(_ query: String, forward: Bool, completion: @escaping (Bool) -> Void) {
        coordinator?.find(query, forward: forward, completion: completion) ?? completion(false)
    }

    func resetEditingFlag() {
        coordinator?.isEditingInView = false
    }

    func scrollToHeading(_ heading: HeadingNode) {
        _bufferedHeading = heading
        coordinator?.pendingHeading = heading
        coordinator?.scrollToHeading(heading)
    }

    func setPendingScrollRatio(_ ratio: Double) {
        _bufferedScrollRatio = ratio
        coordinator?.pendingScrollRatio = ratio

        // If the page is already loaded (coordinator + webView exist), apply immediately
        // via JS rather than waiting for didFinish — which never fires when HTML is cached.
        if let webView = coordinator?.webView {
            let js = """
            (function() {
                var h = document.documentElement.scrollHeight;
                if (h > 0) {
                    var targetY = \(ratio) * h - window.innerHeight / 2;
                    window.scrollTo(0, Math.max(0, Math.round(targetY)));
                }
            })();
            """
            webView.evaluateJavaScript(js)
        }
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
        // Setting coordinator triggers didSet, which forwards any buffered scroll ratio.
        bridge.coordinator = context.coordinator

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
        var pendingHeading: HeadingNode?

        @discardableResult
        func focusWebView() -> Bool {
            guard let webView else { return false }
            webView.window?.makeFirstResponder(webView)
            return webView.window?.firstResponder === webView
        }

        func find(_ query: String, forward: Bool, completion: @escaping (Bool) -> Void) {
            guard let webView else { return }
            guard let encodedQuery = Self.javaScriptStringLiteral(query) else {
                completion(false)
                return
            }
            let js = """
            (function() {
                if (!window.__markfopsFind) return false;
                return window.__markfopsFind.find(\(encodedQuery), \(!forward));
            })();
            """
            webView.evaluateJavaScript(js) { result, _ in
                DispatchQueue.main.async {
                    completion(result as? Bool ?? false)
                }
            }
        }

        private static func javaScriptStringLiteral(_ string: String) -> String? {
            guard let data = try? JSONSerialization.data(withJSONObject: [string]),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return String(json.dropFirst().dropLast())
        }

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

                window.__markfopsFindOverlayCleanup = function() {
                    document.querySelectorAll('.markfops-find-overlay').forEach(function(node) {
                        node.remove();
                    });
                };

                function flashCurrentSelection() {
                    window.__markfopsFindOverlayCleanup();
                    var selection = window.getSelection();
                    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return false;
                    var range = selection.getRangeAt(0);
                    var rects = Array.from(range.getClientRects()).filter(function(rect) {
                        return rect.width > 0 && rect.height > 0;
                    });
                    if (rects.length === 0) return false;

                    rects.forEach(function(rect, index) {
                        var overlay = document.createElement('div');
                        overlay.className = 'markfops-find-overlay';
                        overlay.style.position = 'absolute';
                        overlay.style.left = (rect.left + window.scrollX - 4) + 'px';
                        overlay.style.top = (rect.top + window.scrollY - 3) + 'px';
                        overlay.style.width = (rect.width + 8) + 'px';
                        overlay.style.height = (rect.height + 6) + 'px';
                        overlay.style.borderRadius = '7px';
                        overlay.style.pointerEvents = 'none';
                        overlay.style.background = 'rgba(255, 220, 64, 0.34)';
                        overlay.style.boxShadow = '0 0 0 1px rgba(255, 196, 0, 0.9), 0 10px 24px rgba(255, 196, 0, 0.2)';
                        overlay.style.opacity = '0';
                        overlay.style.transform = 'scale(0.96)';
                        overlay.style.transition = 'opacity 0.16s ease-out, transform 0.16s ease-out';
                        overlay.style.zIndex = '2147483647';
                        document.body.appendChild(overlay);
                        requestAnimationFrame(function() {
                            overlay.style.opacity = '1';
                            overlay.style.transform = 'scale(1)';
                        });
                        setTimeout(function() {
                            overlay.style.opacity = '0';
                            overlay.style.transform = 'scale(1.02)';
                        }, 620 + index * 40);
                        setTimeout(function() {
                            overlay.remove();
                        }, 940 + index * 40);
                    });
                    return true;
                }

                window.__markfopsFind = {
                    find: function(term, backwards) {
                        if (!term) {
                            window.__markfopsFindOverlayCleanup();
                            return false;
                        }
                        article.focus();
                        var found = window.find(term, false, backwards, true, false, true, false);
                        if (!found) return false;
                        flashCurrentSelection();
                        var selection = window.getSelection();
                        if (selection && selection.rangeCount > 0) {
                            var range = selection.getRangeAt(0);
                            var rect = range.getBoundingClientRect();
                            var targetY = Math.max(0, rect.top + window.scrollY - window.innerHeight * 0.25);
                            window.scrollTo({ top: targetY, behavior: 'smooth' });
                        }
                        return true;
                    }
                };

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

                // Report scroll position (throttled) so Swift can sync back to editor.
                // Reports center-of-viewport ratio: (scrollY + innerHeight/2) / scrollHeight
                var scrollThrottle;
                window.addEventListener('scroll', function() {
                    if (scrollThrottle) return;
                    scrollThrottle = setTimeout(function() {
                        scrollThrottle = null;
                        var total = document.documentElement.scrollHeight;
                        if (total > 0) {
                            var ratio = (window.scrollY + window.innerHeight / 2) / total;
                            window.webkit.messageHandlers.scrollChanged.postMessage(ratio);
                        }
                    }, 100);
                }, { passive: true });
            })();
            """
            webView.evaluateJavaScript(js)

            // Apply deferred scroll ratio now that the page is ready.
            // ratio = center-of-viewport / scrollHeight, so restore: scrollTo(ratio*h - innerHeight/2)
            if let ratio = pendingScrollRatio {
                pendingScrollRatio = nil
                let scrollJS = """
                (function() {
                    var h = document.documentElement.scrollHeight;
                    var targetY = \(ratio) * h - window.innerHeight / 2;
                    window.scrollTo(0, Math.max(0, Math.round(targetY)));
                })();
                """
                webView.evaluateJavaScript(scrollJS)
            }

            if let heading = pendingHeading {
                pendingHeading = nil
                scrollToHeading(heading)
            }
        }

        /// Scroll to a heading in the preview and flash it with a highlight.
        func scrollToHeading(_ heading: HeadingNode) {
            pendingHeading = heading
            let js = """
            (function() {
                var target = document.getElementById('\(heading.domID)');
                if (!target) return;

                var startY = window.scrollY;
                var targetY = Math.max(0, Math.round(target.getBoundingClientRect().top + window.scrollY));
                var distance = targetY - startY;
                if (Math.abs(distance) < 1) {
                    return;
                }

                var duration = Math.min(820, Math.max(460, Math.abs(distance) * 0.55));
                var startTime = null;
                function easeOutCubic(t) {
                    return 1 - Math.pow(1 - t, 3);
                }

                function step(timestamp) {
                    if (startTime === null) startTime = timestamp;
                    var elapsed = timestamp - startTime;
                    var progress = Math.min(1, elapsed / duration);
                    var eased = easeOutCubic(progress);
                    window.scrollTo(0, Math.round(startY + distance * eased));
                    if (progress < 1) {
                        window.requestAnimationFrame(step);
                    } else {
                        window.scrollTo(0, targetY);
                    }
                }

                window.requestAnimationFrame(step);
                target.style.transition = 'background-color 0.1s ease-in';
                target.style.borderRadius = '4px';
                target.style.backgroundColor = 'rgba(255,200,0,0.35)';
                setTimeout(function() {
                    target.style.transition = 'background-color 0.7s ease-out';
                    target.style.backgroundColor = 'transparent';
                }, 300);
            })();
            """
            webView?.evaluateJavaScript(js) { [weak self] _, error in
                if error == nil {
                    self?.pendingHeading = nil
                }
            }
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
