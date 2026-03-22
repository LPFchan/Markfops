import WebKit

/// Renders an HTML string to a PDF file via an off-screen WKWebView.
enum PDFExporter {

    static func export(html: String, to url: URL) {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 1))
        webView.loadHTMLString(html, baseURL: nil)

        // Wait for load then print to PDF
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
            printInfo.jobDisposition = .save
            printInfo.dictionary()[NSPrintInfo.AttributeKey("NSPrintJobSavingURL")] = url

            let op = webView.printOperation(with: printInfo)
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            op.run()
        }
    }
}
