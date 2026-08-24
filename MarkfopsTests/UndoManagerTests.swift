import AppKit
import Observation
import SwiftUI
import XCTest
@testable import Markfops

final class UndoManagerTests: XCTestCase {
    func testHeadingNavigationUsesUTF16RangeForUnicodeText() {
        let heading = "## GPIO (XIAO ESP32-S3) 🔌"
        let text = "# Ninebot 🛴\n한국어 설명 🦊\r\n\(heading)\nBody"
        let expectedRange = (text as NSString).range(of: heading)
        let document = Document(rawText: text)
        let editor = makeEditor(for: document)

        editor.coordinator.scrollToLine(2)

        XCTAssertEqual(editor.textView.selectedRange().location, expectedRange.location)
        var highlightedRange = NSRange(location: NSNotFound, length: 0)
        XCTAssertNotNil(
            editor.textView.layoutManager?.temporaryAttribute(
                .backgroundColor,
                atCharacterIndex: expectedRange.location,
                effectiveRange: &highlightedRange
            )
        )
        XCTAssertEqual(highlightedRange, expectedRange)
        XCTAssertEqual(
            (text as NSString).substring(with: highlightedRange),
            heading
        )
    }

    func testTextViewUsesDocumentUndoManagerAndSupportsUndoRedo() {
        let document = Document(rawText: "Hello")
        let editor = makeEditor(for: document)
        replaceText(in: editor.textView, range: NSRange(location: 5, length: 0), with: "!")

        XCTAssertIdentical(editor.textView.undoManager, document.undoManager)
        XCTAssertTrue(document.undoManager.canUndo)
        document.undoManager.undo()
        XCTAssertEqual(editor.textView.string, "Hello")
        XCTAssertTrue(document.undoManager.canRedo)
        document.undoManager.redo()
        XCTAssertEqual(editor.textView.string, "Hello!")
    }

    func testUndoHistoriesAreIsolatedPerDocument() {
        let first = Document(rawText: "First")
        let second = Document(rawText: "Second")
        let firstEditor = makeEditor(for: first)
        let secondEditor = makeEditor(for: second)

        replaceText(in: firstEditor.textView, range: NSRange(location: 5, length: 0), with: "!")

        XCTAssertTrue(first.undoManager.canUndo)
        XCTAssertFalse(second.undoManager.canUndo)
        second.undoManager.undo()
        XCTAssertEqual(secondEditor.textView.string, "Second")
        XCTAssertEqual(firstEditor.textView.string, "First!")
    }

    func testUndoHistorySurvivesCoordinatorTeardownAndEditorRecreation() {
        let document = Document(rawText: "Hello")
        let original = makeEditor(for: document)
        replaceText(in: original.textView, range: NSRange(location: 5, length: 0), with: "!")
        original.coordinator.teardown()

        let recreated = makeEditor(for: document)
        XCTAssertTrue(document.undoManager.canUndo)
        document.undoManager.undo()
        XCTAssertEqual(document.rawText, "Hello")
        XCTAssertEqual(recreated.textView.string, "Hello")
        XCTAssertTrue(document.undoManager.canRedo)
        document.undoManager.redo()
        XCTAssertEqual(recreated.textView.string, "Hello!")
    }

    func testHostedDocumentSwitchRebuildsEditorAndPreservesEachHistory() {
        let first = Document(rawText: "First")
        let second = Document(rawText: "Second")
        let selection = HostedDocumentSelection(document: first)
        let hostingView = NSHostingView(rootView: HostedDocumentContent(selection: selection))
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        settle(hostingView)
        guard let firstTextView = findTextView(in: hostingView) else {
            return XCTFail("The hosted editor did not create an NSTextView")
        }
        XCTAssertTrue(firstTextView.textStorage === first.textStorage)
        replaceText(in: firstTextView, range: NSRange(location: 5, length: 0), with: "!")

        selection.document = second
        settle(hostingView)
        guard let secondTextView = findTextView(in: hostingView) else {
            return XCTFail("The hosted editor did not recreate for the second document")
        }
        XCTAssertTrue(secondTextView.textStorage === second.textStorage)
        XCTAssertEqual(secondTextView.string, "Second")
        XCTAssertFalse(second.undoManager.canUndo)
        replaceText(in: secondTextView, range: NSRange(location: 6, length: 0), with: "!")

        selection.document = first
        settle(hostingView)
        guard let restoredFirstTextView = findTextView(in: hostingView) else {
            return XCTFail("The hosted editor did not recreate when switching back")
        }
        XCTAssertTrue(restoredFirstTextView.textStorage === first.textStorage)
        XCTAssertEqual(restoredFirstTextView.string, "First!")
        XCTAssertTrue(first.undoManager.canUndo)
        first.undoManager.undo()
        XCTAssertEqual(restoredFirstTextView.string, "First")
        XCTAssertEqual(second.rawText, "Second!")
        XCTAssertTrue(second.undoManager.canUndo)
    }

    func testHostedEditorHasInteractiveScrollableGeometry() {
        let text = Array(repeating: "A long line of editable Markdown text.", count: 200)
            .joined(separator: "\n")
        let document = Document(rawText: text)
        let selection = HostedDocumentSelection(document: document)
        let hostingView = NSHostingView(rootView: HostedDocumentContent(selection: selection))
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        defer { window.orderOut(nil) }

        settle(hostingView)
        guard let textView = findTextView(in: hostingView),
              let scrollView = textView.enclosingScrollView else {
            return XCTFail("The hosted editor did not create its scrollable text view")
        }
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        settle(hostingView)

        XCTAssertTrue(textView.isEditable)
        XCTAssertTrue(textView.isVerticallyResizable)
        XCTAssertGreaterThan(textView.frame.height, scrollView.contentView.bounds.height)
        XCTAssertTrue(window.makeFirstResponder(textView))
        XCTAssertIdentical(window.firstResponder, textView)
    }

    func testHostedDocumentSwitchRestoresScrollPositionForEachDocument() {
        let first = Document(rawText: longDocument(prefix: "First"))
        let second = Document(rawText: longDocument(prefix: "Second"))
        let selection = HostedDocumentSelection(document: first)
        let hostingView = NSHostingView(rootView: HostedDocumentContent(selection: selection))
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        defer { window.orderOut(nil) }

        settle(hostingView)
        guard let firstTextView = findTextView(in: hostingView),
              let firstScrollView = firstTextView.enclosingScrollView else {
            return XCTFail("The first hosted editor did not create its scroll view")
        }
        firstTextView.layoutManager?.ensureLayout(for: firstTextView.textContainer!)
        settle(hostingView)

        let firstTargetY = (firstTextView.bounds.height - firstScrollView.contentView.bounds.height) * 0.55
        firstTextView.scroll(NSPoint(x: 0, y: firstTargetY))
        firstScrollView.reflectScrolledClipView(firstScrollView.contentView)
        NotificationCenter.default.post(
            name: NSScrollView.didLiveScrollNotification,
            object: firstScrollView
        )
        let savedRatio = first.scrollRatio
        XCTAssertGreaterThan(savedRatio, 0.4)

        selection.document = second
        settle(hostingView)
        selection.document = first
        settle(hostingView)

        guard let restoredTextView = findTextView(in: hostingView),
              let restoredScrollView = restoredTextView.enclosingScrollView else {
            return XCTFail("The restored editor did not create its scroll view")
        }
        let restoredRatio = waitForScrollRatio(
            savedRatio,
            in: restoredTextView,
            scrollView: restoredScrollView
        )
        let visibleRect = restoredScrollView.contentView.documentVisibleRect

        XCTAssertGreaterThan(visibleRect.minY, 0)
        XCTAssertEqual(restoredRatio, savedRatio, accuracy: 0.03)
    }

    func testWrappedEditorContentTracksHeadingAtViewportCenter() {
        let linesBeforeTarget = (0..<80).map { "Short line \($0)" }.joined(separator: "\n")
        let longWrappedLine = Array(repeating: "wrapped content", count: 2_000).joined(separator: " ")
        let text = "## First\n\(linesBeforeTarget)\n## Target\n\(longWrappedLine)"
        let document = Document(rawText: text)
        document.headings = HeadingParser.parseHeadings(in: text)
        guard let targetHeading = document.tocHeadings.last else {
            return XCTFail("The target heading was not parsed")
        }

        let selection = HostedDocumentSelection(document: document)
        let hostingView = NSHostingView(rootView: HostedDocumentContent(selection: selection))
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        defer { window.orderOut(nil) }

        settle(hostingView)
        guard let textView = findTextView(in: hostingView),
              let scrollView = textView.enclosingScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return XCTFail("The hosted editor did not create its scrollable text view")
        }
        layoutManager.ensureLayout(for: textContainer)
        settle(hostingView)

        let targetCharacterRange = (text as NSString).range(of: "## Target")
        let targetGlyphRange = layoutManager.glyphRange(
            forCharacterRange: targetCharacterRange,
            actualCharacterRange: nil
        )
        let targetRect = layoutManager.boundingRect(forGlyphRange: targetGlyphRange, in: textContainer)
        let targetY = targetRect.minY + textView.textContainerOrigin.y
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        NotificationCenter.default.post(
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView
        )

        let ratioEstimatedLine = Int(
            (Double(max(document.lineCount - 1, 0)) * document.scrollRatio).rounded()
        )
        XCTAssertLessThan(ratioEstimatedLine, targetHeading.lineNumber)
        XCTAssertEqual(document.activeHeadingID, targetHeading.id)
    }

    func testManualSidebarScrollSuspendsAutomaticFollowingUntilResumed() {
        let context = SidebarScrollContext()
        context.lastTargetY = 120
        context.desiredTargetY = 180

        context.beginManualScrolling()

        XCTAssertNil(context.lastTargetY)
        XCTAssertNil(context.desiredTargetY)
        XCTAssertFalse(context.allowsAutomaticFollowing(force: false))
        XCTAssertTrue(context.allowsAutomaticFollowing(force: true))

        context.resumeAutomaticFollowing()

        XCTAssertTrue(context.allowsAutomaticFollowing(force: false))
    }

    func testForcedSidebarFollowAtLiveTargetDoesNotRearmAfterGeometryCallback() {
        let context = SidebarScrollContext()
        let snapDistance = SidebarScrollPhysics.snapDistance(backingScaleFactor: 2)
        context.desiredTargetY = 240

        XCTAssertTrue(
            context.hasSettledTOCTarget(
                currentY: 180,
                targetY: 180,
                snapDistance: snapDistance
            )
        )
        XCTAssertNil(context.desiredTargetY)

        let timer = Timer(timeInterval: 1, repeats: true) { _ in }
        context.displayTimer = timer
        XCTAssertFalse(
            context.hasSettledTOCTarget(
                currentY: 180,
                targetY: 180,
                snapDistance: snapDistance
            )
        )
        timer.invalidate()
    }

    func testSidebarSpringSnapsAtBackingScaleQuantumOrWatchdog() {
        XCTAssertEqual(
            SidebarScrollPhysics.snapDistance(backingScaleFactor: 2),
            0.5,
            accuracy: 0.001
        )
        XCTAssertTrue(
            SidebarScrollPhysics.shouldSnap(
                currentY: 179.6,
                targetY: 180,
                nextY: 179.7,
                elapsed: 0,
                tickCount: 1,
                snapDistance: 0.5,
                maximumDuration: 0.9,
                maximumTicks: 180
            )
        )
        XCTAssertTrue(
            SidebarScrollPhysics.shouldSnap(
                currentY: 0,
                targetY: 180,
                nextY: 1,
                elapsed: 0.9,
                tickCount: 2,
                snapDistance: 0.5,
                maximumDuration: 0.9,
                maximumTicks: 180
            )
        )
        XCTAssertTrue(
            SidebarScrollPhysics.shouldSnap(
                currentY: 0,
                targetY: 180,
                nextY: 1,
                elapsed: 0,
                tickCount: 180,
                snapDistance: 0.5,
                maximumDuration: 0.9,
                maximumTicks: 180
            )
        )
        XCTAssertFalse(
            SidebarScrollPhysics.shouldSnap(
                currentY: 0,
                targetY: 180,
                nextY: 1,
                elapsed: 0.1,
                tickCount: 2,
                snapDistance: 0.5,
                maximumDuration: 0.9,
                maximumTicks: 180
            )
        )
    }

    func testEditorUserScrollReattachesOncePerGestureWithoutHeadingChange() {
        let text = "## One long section\n" + Array(repeating: "Body", count: 200).joined(separator: "\n")
        let document = Document(rawText: text)
        document.headings = HeadingParser.parseHeadings(in: text)
        document.syncActiveHeading(toSourceLine: 1)
        let originalHeadingID = document.activeHeadingID

        let editor = makeEditor(for: document)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        editor.textView.frame = NSRect(x: 0, y: 0, width: 600, height: 3_000)
        scrollView.documentView = editor.textView
        editor.coordinator.attach(scrollView: scrollView)

        let liveScroll = Notification(name: NSScrollView.didLiveScrollNotification, object: scrollView)
        editor.coordinator.scrollViewDidLiveScroll(liveScroll)
        editor.coordinator.scrollViewDidLiveScroll(liveScroll)

        XCTAssertEqual(document.activeHeadingID, originalHeadingID)
        XCTAssertEqual(document.userContentScrollGeneration, 1)

        editor.coordinator.scrollViewDidEndLiveScroll(
            Notification(name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        )
        editor.coordinator.scrollViewDidLiveScroll(liveScroll)

        XCTAssertEqual(document.userContentScrollGeneration, 2)
    }

    func testEditorUserScrollReattachesAfterIdleWhenEndNotificationIsMissing() {
        let document = Document(rawText: longDocument(prefix: "Idle fallback"))
        let editor = makeEditor(for: document)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        editor.textView.frame = NSRect(x: 0, y: 0, width: 600, height: 3_000)
        scrollView.documentView = editor.textView
        editor.coordinator.attach(scrollView: scrollView)

        let liveScroll = Notification(name: NSScrollView.didLiveScrollNotification, object: scrollView)
        editor.coordinator.scrollViewDidLiveScroll(liveScroll)
        XCTAssertEqual(document.userContentScrollGeneration, 1)

        let idleReset = expectation(description: "missing end-live-scroll notification falls back to idle")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + TextViewCoordinator.userScrollIdleResetDelay + 0.05
        ) {
            idleReset.fulfill()
        }
        wait(for: [idleReset], timeout: 1)

        editor.coordinator.scrollViewDidLiveScroll(liveScroll)
        XCTAssertEqual(document.userContentScrollGeneration, 2)
    }

    func testProgrammaticEditorScrollingDoesNotRegisterUserGesture() {
        let document = Document(rawText: longDocument(prefix: "Restore"))
        document.headings = HeadingParser.parseHeadings(in: document.rawText)
        let editor = makeEditor(for: document)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        editor.textView.frame = NSRect(x: 0, y: 0, width: 600, height: 3_000)
        scrollView.documentView = editor.textView
        editor.coordinator.attach(scrollView: scrollView)

        editor.coordinator.scrollToRatio(0.5)

        XCTAssertEqual(document.userContentScrollGeneration, 0)
        XCTAssertEqual(editor.coordinator.currentScrollRatio() ?? -1, 0.5, accuracy: 0.01)
    }

    func testEditorCanCenterARequestedSourceLine() {
        let text = (0..<240).map { "Line \($0)" }.joined(separator: "\n")
        let document = Document(rawText: text)
        let editor = makeEditor(for: document)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        editor.textView.frame = NSRect(x: 0, y: 0, width: 600, height: 5_000)
        editor.textView.textContainer?.containerSize = NSSize(
            width: 560,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = editor.textView
        editor.coordinator.attach(scrollView: scrollView)
        editor.textView.layoutManager?.ensureLayout(for: editor.textView.textContainer!)

        XCTAssertTrue(editor.coordinator.scrollToSourceLineCentered(150))
        XCTAssertEqual(editor.coordinator.currentSourceLineAtViewportCenter(), 150)
    }

    func testHiddenEditorScrollDoesNotOverwriteActiveSurfaceRatio() {
        let document = Document(rawText: longDocument(prefix: "Hidden"))
        document.scrollRatio = 0.73
        let editor = makeEditor(for: document)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        editor.textView.frame = NSRect(x: 0, y: 0, width: 600, height: 3_000)
        scrollView.documentView = editor.textView
        editor.coordinator.attach(scrollView: scrollView)
        editor.coordinator.isActive = false

        editor.coordinator.scrollViewDidLiveScroll(
            Notification(name: NSScrollView.didLiveScrollNotification, object: scrollView)
        )

        XCTAssertEqual(document.scrollRatio, 0.73, accuracy: 0.001)
        XCTAssertEqual(document.userContentScrollGeneration, 0)
    }

    func testPreviewScrollRestoreCanWaitForUpdatedContent() {
        let bridge = PreviewBridge()
        let coordinator = PreviewView.Coordinator()
        coordinator.isPageReady = true
        bridge.coordinator = coordinator

        bridge.setPendingScrollRatio(0.42, applyImmediately: false)

        XCTAssertEqual(coordinator.pendingScrollRatio ?? -1, 0.42, accuracy: 0.001)
    }

    func testPreviewViewportRestoreKeepsSourceLineWhileContentUpdates() {
        let bridge = PreviewBridge()
        let coordinator = PreviewView.Coordinator()
        coordinator.isPageReady = true
        bridge.coordinator = coordinator

        bridge.setPendingViewportRestore(
            sourceLine: 84,
            ratio: 0.42,
            applyImmediately: false
        )

        XCTAssertEqual(coordinator.pendingViewportSourceLine, 84)
        XCTAssertEqual(coordinator.pendingScrollRatio ?? -1, 0.42, accuracy: 0.001)
    }

    func testPreviewViewportAnchorDecodesSourceLineAndFallbackRatio() {
        let anchor = PreviewViewportAnchor(messageBody: [
            "sourceLine": NSNumber(value: 84),
            "ratio": NSNumber(value: 0.42)
        ])

        XCTAssertEqual(anchor, PreviewViewportAnchor(
            messageBody: ["sourceLine": NSNumber(value: 84), "ratio": NSNumber(value: 0.42)]
        ))
        XCTAssertEqual(anchor?.sourceLine, 84)
        XCTAssertEqual(anchor?.ratio ?? -1, 0.42, accuracy: 0.001)
    }

    func testPreviewScrollReportCarriesUserGestureSeparatelyFromRatio() {
        let userReport = PreviewScrollReport(messageBody: [
            "ratio": 0.42,
            "userGesture": 7
        ])
        let programmaticReport = PreviewScrollReport(messageBody: [
            "ratio": 0.75,
            "userGesture": 0
        ])
        let legacyReport = PreviewScrollReport(messageBody: 0.25)

        XCTAssertEqual(userReport?.ratio, 0.42)
        XCTAssertEqual(userReport?.userGesture, 7)
        XCTAssertEqual(programmaticReport?.ratio, 0.75)
        XCTAssertEqual(programmaticReport?.userGesture, 0)
        XCTAssertEqual(legacyReport?.ratio, 0.25)
        XCTAssertNil(legacyReport?.userGesture)
    }

    func testUserScrollGestureStateStartsOnlyOnceUntilEnded() {
        var gesture = UserScrollGestureState()

        XCTAssertTrue(gesture.begin())
        XCTAssertFalse(gesture.begin())
        gesture.end()
        XCTAssertTrue(gesture.begin())
    }

    func testSidebarReinstallsScrollObserversWhenItsScrollViewChanges() {
        let context = SidebarScrollContext()
        let first = NSScrollView()
        let replacement = NSScrollView()

        XCTAssertTrue(context.needsScrollObserverInstallation(for: first))

        context.observedScrollView = first
        context.liveScrollObserver = NSObject()
        context.endLiveScrollObserver = NSObject()

        XCTAssertFalse(context.needsScrollObserverInstallation(for: first))
        XCTAssertTrue(context.needsScrollObserverInstallation(for: replacement))
    }

    private struct EditorFixture {
        let textView: MarkdownNSTextView
        let coordinator: TextViewCoordinator
    }

    private func makeEditor(for document: Document) -> EditorFixture {
        let textView = MarkdownNSTextView(textStorage: document.textStorage)
        let coordinator = TextViewCoordinator(document: document)
        textView.delegate = coordinator
        coordinator.textView = textView
        textView.allowsUndo = true
        if textView.string != document.rawText {
            textView.setPlainTextWithoutUndo(document.rawText)
        }
        return EditorFixture(textView: textView, coordinator: coordinator)
    }

    private func replaceText(in textView: MarkdownNSTextView, range: NSRange, with replacement: String) {
        XCTAssertTrue(textView.shouldChangeText(in: range, replacementString: replacement))
        textView.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
    }

    private func longDocument(prefix: String) -> String {
        (0..<300).map { "## \(prefix) section \($0)\nBody line \($0)" }
            .joined(separator: "\n")
    }

    private func settle(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        view.layoutSubtreeIfNeeded()
    }

    private func waitForScrollRatio(
        _ expectedRatio: Double,
        in textView: MarkdownNSTextView,
        scrollView: NSScrollView,
        timeout: TimeInterval = 2
    ) -> Double {
        let deadline = Date(timeIntervalSinceNow: timeout)
        var ratio = 0.0

        repeat {
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            scrollView.layoutSubtreeIfNeeded()
            let visibleRect = scrollView.contentView.documentVisibleRect
            ratio = Double((visibleRect.minY + visibleRect.height / 2) / textView.bounds.height)
            if abs(ratio - expectedRatio) <= 0.03 { return ratio }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        } while Date() < deadline

        return ratio
    }

    private func findTextView(in view: NSView) -> MarkdownNSTextView? {
        if let textView = view as? MarkdownNSTextView { return textView }
        for subview in view.subviews {
            if let textView = findTextView(in: subview) { return textView }
        }
        return nil
    }
}

@Observable
private final class HostedDocumentSelection {
    var document: Document

    init(document: Document) {
        self.document = document
    }
}

private struct HostedDocumentContent: View {
    @Bindable var selection: HostedDocumentSelection

    var body: some View {
        EditorContainerView(
            document: selection.document,
            configuration: .default,
            scrollToHeading: nil
        )
    }
}
