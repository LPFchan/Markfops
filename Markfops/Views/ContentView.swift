import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Shared flag: true while the sidebar column is animating between its endpoints.
/// The editor reads this to pin its text-wrap width mid-slide, so the document
/// re-wraps once when the slide ends instead of reflowing on every animation frame.
enum SidebarSlideState {
    static var isSliding = false
}

struct ContentView: View {
    @Environment(DocumentStore.self) private var store
    @AppStorage("editorFontSize") private var fontSize: Double = 15
    @AppStorage("editorFontFamily") private var fontFamily: String = "SF Mono"

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var scrollToHeading: HeadingNode? = nil
    @State private var isSidebarTransitioning = false
    @State private var isToolbarContentVisible = true
    @State private var toolbarUsesCompactLayout = false
    @State private var sidebarTransitionGeneration = 0
    /// In-flight viewport-anchor capture for the current sidebar/compact toggle.
    @State private var layoutTransitionSession: ViewportAnchorSync.LayoutTransitionSession?

    private var editorConfig: EditorConfiguration {
        var config = EditorConfiguration.default
        config.fontSize = fontSize
        config.fontFamily = fontFamily
        return config
    }

    private var sidebarVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { columnVisibility },
            set: { newVisibility, transaction in
                guard newVisibility != columnVisibility else { return }
                // Do NOT touch transition state here. prepareSidebarTransition()
                // collapses the compact pill row to zero width, which lets the detail
                // expand to full width in the SAME SwiftUI update as the column change —
                // that is the hard cut. Defer the toolbar mask until the split view
                // actually starts animating (SidebarTransitionObserver fires then).
                withTransaction(transaction) {
                    columnVisibility = newVisibility
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibilityBinding) {
            SidebarView(
                onTOCTap: handleTOCTap,
                columnVisibility: sidebarVisibilityBinding
            )
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            Group {
                if let document = store.activeDocument {
                    @Bindable var doc = document
                    EditorContainerView(
                        document: document,
                        configuration: editorConfig,
                        scrollToHeading: scrollToHeading
                    )
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            CompactToolbarPrincipalItem(
                                isCompact: toolbarUsesCompactLayout,
                                isTransitioning: isSidebarTransitioning,
                                isVisible: isToolbarContentVisible
                            )
                        }
                        ModeToggleToolbarItem(
                            mode: $doc.mode,
                            isVisible: isToolbarContentVisible
                        )
                    }
                } else {
                    WelcomeView()
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                CompactToolbarPrincipalItem(
                                    isCompact: toolbarUsesCompactLayout,
                                    isTransitioning: isSidebarTransitioning,
                                    isVisible: isToolbarContentVisible
                                )
                            }
                        }
                }
            }
            // Title visibility is handled by navigationTitle ("" in compact mode).
            // We deliberately do NOT call toolbar(removing: .title) here: toggling the
            // toolbar item set at transition end rebuilds the toolbar and momentarily
            // blanks the detail content (WebView frame -> 0), forcing a full WebKit
            // re-render of the document — the end-of-slide freeze.
        }
        // Scene-level so the View-menu command and Cmd+backslash keep working even
        // when focus sits in the toolbar pill row (compact mode) rather than the editor.
        .focusedSceneValue(\.sidebarVisibility, sidebarVisibilityBinding)
        // The native title owns the draggable file proxy while the sidebar is visible.
        .navigationTitle(
            toolbarUsesCompactLayout
                ? ""
                : (store.activeDocument?.displayTitle ?? "Markfops")
        )
        // Hidden Cmd+1-9 / Cmd+0 shortcuts for tab selection — not in Commands so they don't create menu items
        .background {
            VStack {
                ForEach(1..<10, id: \.self) { i in
                    Button("") { store.selectTab(at: i - 1) }
                        .keyboardShortcut(KeyEquivalent(Character(String(i))), modifiers: .command)
                }
                Button("") { store.activeID = store.documents.last?.id }
                    .keyboardShortcut("0", modifiers: .command)
            }
            .opacity(0)
        }
        .background {
            SidebarTransitionObserver(
                isCompact: columnVisibility == .detailOnly,
                onTransitionBegan: beginSidebarTransitionIfNeeded,
                onTransitionSettled: finishSidebarTransition
            )
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleWindowDrop(providers: providers)
        }
        .onChange(of: store.activeDocument?.isDirty) { _, isDirty in
            documentWindow?.isDocumentEdited = isDirty ?? false
        }
        .onChange(of: store.activeDocument?.fileURL) { _, _ in
            refreshProxyIcon()
        }
        .onChange(of: store.activeDocument?.headings) { _, _ in
            refreshProxyIcon()
        }
        .onChange(of: store.activeID) { _, _ in
            let doc = store.activeDocument
            documentWindow?.isDocumentEdited = doc?.isDirty ?? false
            refreshProxyIcon()
        }
    }

    /// Keeps the window proxy icon in sync with the active document.
    /// For saved files, representedURL drives the icon automatically.
    /// For unsaved files with no H1 (= no colored-badge favicon), we force-show
    /// a generic markdown icon so the proxy icon area is never empty.
    private func refreshProxyIcon() {
        guard let window = documentWindow else { return }
        let doc = store.activeDocument
        window.representedURL = doc?.fileURL

        // If the document is unsaved and has no H1, show a placeholder icon
        guard doc?.fileURL == nil,
              let btn = window.standardWindowButton(.documentIconButton) else { return }
        let hasH1 = doc?.headings.contains(where: { $0.level == 1 }) ?? false
        if !hasH1 {
            let icon = NSWorkspace.shared.icon(for: UTType("net.daringfireball.markdown") ?? .plainText)
            btn.image = icon
            btn.isHidden = false
        }
    }

    private var documentWindow: NSWindow? {
        store.managedWindow
    }

    private func prepareSidebarTransition() {
        sidebarTransitionGeneration &+= 1

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isToolbarContentVisible = false
            isSidebarTransitioning = true
        }
        SidebarSlideState.isSliding = true

        captureLayoutAnchor()
    }

    /// Snapshots the content at the center of the viewport before the detail pane
    /// changes width, so the restore (fired when the transition settles) can put the
    /// same content back in the middle instead of leaving the scroll position drifted.
    private func captureLayoutAnchor() {
        layoutTransitionSession?.cancel()
        layoutTransitionSession = nil
        guard let document = store.activeDocument else { return }
        layoutTransitionSession = ViewportAnchorSync.captureForLayoutTransition(
            context: .shared(for: document)
        )
    }

    private func beginSidebarTransitionIfNeeded() {
        guard SidebarTransitionGeometry.shouldBeginFromObserver(
            toolbarIsVisible: isToolbarContentVisible,
            isTransitioning: isSidebarTransitioning
        ) else { return }
        prepareSidebarTransition()
    }

    private func finishSidebarTransition() {
        let generation = sidebarTransitionGeneration
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isSidebarTransitioning = false
            toolbarUsesCompactLayout = columnVisibility == .detailOnly
        }

        // The layout has settled — put the captured center content back in the middle.
        // Firing here (instead of on a fixed timer) removes the drift-then-snap flash.
        layoutTransitionSession?.fire()
        layoutTransitionSession = nil
        SidebarSlideState.isSliding = false
        // Re-wrap the editor at the final width NOW rather than waiting ~540ms for
        // AppKit to deliver another resize — that wait was the end-of-slide stall.
        store.activeDocument.map { $0.sharedEditorBridge.releaseWrapFreeze() }

        // Fire the fade directly. We are already on the main thread here; deferring
        // to DispatchQueue.main.async queued the fade behind ~580ms of runloop work
        // that the sidebar animation system enqueues, which was the lag spike.
        guard generation == sidebarTransitionGeneration else { return }
        // One short cross-fade covers both the incoming toolbar content and
        // the outgoing, so the eye sees a swap rather than a blank gap.
        withAnimation(.easeInOut(duration: 0.18)) {
            isToolbarContentVisible = true
        }
    }

    private func handleTOCTap(_ heading: HeadingNode) {
        store.activeDocument?.focusHeading(heading)
        scrollToHeading = heading
        // Reset after a tick so future taps to the same heading still trigger
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            scrollToHeading = nil
        }
    }

    private func handleWindowDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension.lowercased() == "md"
                        || url.pathExtension.lowercased() == "markdown"
                        || url.pathExtension.lowercased() == "txt" else { return }
                DispatchQueue.main.async {
                    store.coordinator?.open(url: url, preferredWindowID: store.windowID)
                }
            }
        }
        return true
    }
}

/// Watches the AppKit split view without participating in its visibility binding.
///
/// The native sidebar button animates `NSSplitViewItem` directly. Observing that resize lets the
/// toolbar mask appear before AppKit presents the first transition frame while leaving the native
/// `NavigationSplitView` binding untouched.
enum SidebarTransitionGeometry {
    static let collapsedEndpointWidth: CGFloat = 4.5
    static let expandedEndpointTolerance: CGFloat = 1.5

    static func reachedEndpoint(
        compact: Bool,
        widths: [CGFloat],
        expandedWidth: CGFloat
    ) -> Bool {
        if compact {
            return widths.allSatisfy { $0 <= collapsedEndpointWidth }
        }
        return widths.allSatisfy {
            abs($0 - expandedWidth) <= expandedEndpointTolerance
        }
    }

    static func shouldBeginFromObserver(
        toolbarIsVisible: Bool,
        isTransitioning: Bool
    ) -> Bool {
        toolbarIsVisible && !isTransitioning
    }

    /// The collapse endpoint is the sidebar column having shrunk to ~zero width.
    /// It deliberately reads the sidebar, not the detail frame, so a slow detail
    /// layout cannot postpone settle-detection past the safety fallback.
    static func reachedCollapsedEndpoint(widths: [CGFloat]) -> Bool {
        widths.allSatisfy { $0 <= collapsedEndpointWidth }
    }

    static func isSidebarTransitionResize(
        transitionIsActive: Bool,
        wasCollapsed: Bool,
        isCollapsed: Bool,
        previousWidth: CGFloat,
        currentWidth: CGFloat
    ) -> Bool {
        transitionIsActive
            || wasCollapsed != isCollapsed
            || (previousWidth <= collapsedEndpointWidth)
                != (currentWidth <= collapsedEndpointWidth)
    }
}

private struct SidebarTransitionObserver: NSViewRepresentable {
    let isCompact: Bool
    let onTransitionBegan: () -> Void
    let onTransitionSettled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.coordinator = context.coordinator
        context.coordinator.update(
            isCompact: isCompact,
            onTransitionBegan: onTransitionBegan,
            onTransitionSettled: onTransitionSettled
        )
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        context.coordinator.update(
            isCompact: isCompact,
            onTransitionBegan: onTransitionBegan,
            onTransitionSettled: onTransitionSettled
        )
        context.coordinator.attachIfNeeded(from: nsView)
    }

    static func dismantleNSView(_ nsView: ProbeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class ProbeView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attachIfNeeded(from: self)
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            coordinator?.attachIfNeeded(from: self)
        }
    }

    final class Coordinator {
        // The native sidebar slide is ~0.25s. The safety fallback must land just past
        // that, not well past it, or the toolbar handoff snaps late (the hard-cut feel).
        private static let safetyDelay: TimeInterval = 0.32
        private static let presentationCheckDelay: TimeInterval = 1.0 / 120.0

        private weak var splitView: NSSplitView?
        private var resizeObserver: NSObjectProtocol?
        private var endpointWorkItem: DispatchWorkItem?
        private var safetyWorkItem: DispatchWorkItem?
        private var attachWorkItem: DispatchWorkItem?
        private var isTransitionActive = false
        private var isCompact = false
        private var sidebarWasCollapsed = false
        private var lastSidebarWidth: CGFloat?
        private var expandedSidebarWidth: CGFloat = 180
        private var onTransitionBegan: () -> Void = {}
        private var onTransitionSettled: () -> Void = {}

        deinit {
            detach()
        }

        func update(
            isCompact: Bool,
            onTransitionBegan: @escaping () -> Void,
            onTransitionSettled: @escaping () -> Void
        ) {
            self.isCompact = isCompact
            self.onTransitionBegan = onTransitionBegan
            self.onTransitionSettled = onTransitionSettled
        }

        func attachIfNeeded(from probe: NSView) {
            guard probe.window != nil else {
                detach()
                return
            }
            guard let candidate = nearestSplitView(from: probe) else {
                scheduleAttachRetry(from: probe)
                return
            }
            guard candidate !== splitView else { return }

            detach()
            splitView = candidate
            sidebarWasCollapsed = sidebarItem(in: candidate)?.isCollapsed ?? isCompact
            lastSidebarWidth = sidebarWidth(in: candidate)
            if !sidebarWasCollapsed,
               let width = lastSidebarWidth,
               width > SidebarTransitionGeometry.collapsedEndpointWidth {
                expandedSidebarWidth = width
            }
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification,
                object: candidate,
                queue: .main
            ) { [weak self] _ in
                self?.splitViewDidResize()
            }
        }

        func detach() {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
            resizeObserver = nil
            splitView = nil
            attachWorkItem?.cancel()
            attachWorkItem = nil
            endpointWorkItem?.cancel()
            endpointWorkItem = nil
            safetyWorkItem?.cancel()
            safetyWorkItem = nil
            isTransitionActive = false
            lastSidebarWidth = nil
        }

        private func splitViewDidResize() {
            guard let splitView else { return }

            let sidebarIsCollapsed = sidebarItem(in: splitView)?.isCollapsed ?? isCompact
            let width = sidebarWidth(in: splitView)
            let previousWidth = lastSidebarWidth ?? width
            let belongsToSidebarTransition = SidebarTransitionGeometry.isSidebarTransitionResize(
                transitionIsActive: isTransitionActive,
                wasCollapsed: sidebarWasCollapsed,
                isCollapsed: sidebarIsCollapsed,
                previousWidth: previousWidth,
                currentWidth: width
            )

            sidebarWasCollapsed = sidebarIsCollapsed
            lastSidebarWidth = width

            guard belongsToSidebarTransition else {
                if width > SidebarTransitionGeometry.collapsedEndpointWidth {
                    expandedSidebarWidth = width
                }
                return
            }
            beginIfNeeded()
            scheduleEndpointCheckIfNeeded()
        }

        private func beginIfNeeded() {
            guard !isTransitionActive else { return }
            isTransitionActive = true
            onTransitionBegan()

            safetyWorkItem?.cancel()
            let safety = DispatchWorkItem { [weak self] in
                self?.finishIfNeeded()
            }
            safetyWorkItem = safety
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.safetyDelay, execute: safety)
        }

        private func scheduleEndpointCheckIfNeeded() {
            guard isTransitionActive, transitionReachedEndpoint() else { return }

            endpointWorkItem?.cancel()
            let check = DispatchWorkItem { [weak self] in
                self?.finishIfPresentationReachedEndpoint()
            }
            endpointWorkItem = check
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.presentationCheckDelay,
                execute: check
            )
        }

        private func finishIfPresentationReachedEndpoint() {
            guard isTransitionActive else { return }
            guard transitionReachedEndpoint(includePresentationFrame: true) else {
                scheduleEndpointCheckIfNeeded()
                return
            }
            finishIfNeeded()
        }

        private func transitionReachedEndpoint(includePresentationFrame: Bool = false) -> Bool {
            guard let splitView else {
                return false
            }

           if isCompact {
                // Base the collapse endpoint on the sidebar item itself, which AppKit
                // drives directly. Requiring the DETAIL to reach the window edge (the old
                // check) coupled settle-detection to a slow, wedged layout pass, so the
                // endpoint was missed and the safety fallback fired on every collapse.
                guard let item = sidebarItem(in: splitView), item.isCollapsed else {
                    return false
                }
                let width = sidebarWidth(in: splitView)
                let widths = includePresentationFrame
                    ? [width, splitView.subviews.min(by: { $0.frame.minX < $1.frame.minX })?.layer?.presentation()?.frame.width ?? width]
                    : [width]
                return SidebarTransitionGeometry.reachedCollapsedEndpoint(widths: widths)
            }

            guard let sidebar = splitView.subviews.min(by: { $0.frame.minX < $1.frame.minX }) else {
                return false
            }
            let widths = includePresentationFrame
                ? [sidebar.frame.width, sidebar.layer?.presentation()?.frame.width ?? sidebar.frame.width]
                : [sidebar.frame.width]

            return SidebarTransitionGeometry.reachedEndpoint(
                compact: false,
                widths: widths,
                expandedWidth: expandedSidebarWidth
            )
        }

        private func finishIfNeeded() {
            guard isTransitionActive else { return }
            isTransitionActive = false
            endpointWorkItem?.cancel()
            endpointWorkItem = nil
            safetyWorkItem?.cancel()
            safetyWorkItem = nil
            onTransitionSettled()
        }

        private func scheduleAttachRetry(from probe: NSView) {
            guard attachWorkItem == nil else { return }
            let retry = DispatchWorkItem { [weak self, weak probe] in
                self?.attachWorkItem = nil
                guard let self, let probe else { return }
                self.attachIfNeeded(from: probe)
            }
            attachWorkItem = retry
            DispatchQueue.main.async(execute: retry)
        }

        private func nearestSplitView(from probe: NSView) -> NSSplitView? {
            var ancestor = probe.superview
            while let view = ancestor {
                if let splitView = view as? NSSplitView {
                    return splitView
                }
                ancestor = view.superview
            }

            guard let root = probe.window?.contentView else { return nil }
            return largestSplitView(in: root)
        }

        private func largestSplitView(in view: NSView) -> NSSplitView? {
            let descendants = view.subviews.flatMap { child -> [NSSplitView] in
                var matches = largestSplitView(in: child).map { [$0] } ?? []
                if let splitView = child as? NSSplitView {
                    matches.append(splitView)
                }
                return matches
            }
            return descendants.max {
                $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height
            }
        }

        private func sidebarItem(in splitView: NSSplitView) -> NSSplitViewItem? {
            var responder: NSResponder? = splitView
            while let current = responder {
                if let controller = current as? NSSplitViewController,
                   controller.splitView === splitView {
                    return controller.splitViewItems.first
                }
                responder = current.nextResponder
            }
            return nil
        }

        private func sidebarWidth(in splitView: NSSplitView) -> CGFloat {
            splitView.subviews.min(by: { $0.frame.minX < $1.frame.minX })?.frame.width ?? 0
        }
    }
}

/// Persistent compact tab host.
///
/// Its toolbar item and tab graph remain mounted at zero width behind the native window title while
/// the sidebar is visible. Compact mode expands the same host, avoiding the expensive reconstruction
/// without replacing AppKit's draggable document title and proxy icon.
private struct CompactToolbarPrincipalItem: View {
    let isCompact: Bool
    let isTransitioning: Bool
    let isVisible: Bool
    @Environment(DocumentStore.self) private var store
    @State private var windowWidth: CGFloat = 720

    private static let reservedChromeWidth: CGFloat = 244
    private static let minimumIdealWidth: CGFloat = 180

    private var idealWidth: CGFloat {
        return max(Self.minimumIdealWidth, windowWidth - Self.reservedChromeWidth)
    }

    private var occupiesToolbarSpace: Bool {
        isCompact && !isTransitioning
    }

   var body: some View {
       // Keep the outer frame at a CONSTANT width in both modes. Collapsing the
       // principal item to zero width on every toggle forced the whole pill strip to
       // re-layout twice and stalled the main runloop (~550ms) — the lag spike. A
       // fixed frame with the strip clipped/faded avoids the geometry churn entirely.
       // Keep the frame constant in both modes (no zero-width swap) and drive the
       // cross-fade purely through opacity, so the handoff does no geometry churn.
       TabPillRowView(toolbarSlotWidth: idealWidth)
           .frame(width: idealWidth, alignment: .center)
           .clipped()
           .opacity(occupiesToolbarSpace && isVisible ? 1 : 0)
           .allowsHitTesting(occupiesToolbarSpace && isVisible)
           .accessibilityHidden(!occupiesToolbarSpace || !isVisible)
        // NSToolbar asks the principal item for its preferred size; a fully fixed
        // frame can end up squeezed to zero width when the toolbar rebuilds its item
        // set, leaving the pill row invisible in compact mode. A flexible range with
        // an ideal keeps the constant geometry AND answers the sizing query.
        .frame(
            minWidth: idealWidth,
            idealWidth: idealWidth,
            maxWidth: .infinity,
            alignment: .center
        )
        .frame(height: ToolbarMetrics.compactPillRowHeight)
        .layoutPriority(-1)
        .onAppear { refreshWindowWidth() }
        .onChange(of: isCompact) { _, compact in
            if compact {
                refreshWindowWidth()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { note in
            guard isCompact,
                  let window = note.object as? NSWindow,
                  window === store.managedWindow else { return }
            updateWindowWidth(window.contentView?.bounds.width ?? window.frame.width)
        }
    }

    private func refreshWindowWidth() {
        guard let window = store.managedWindow else { return }
        updateWindowWidth(window.contentView?.bounds.width ?? window.frame.width)
    }

    private func updateWindowWidth(_ width: CGFloat) {
        guard abs(width - windowWidth) > 0.5 else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            windowWidth = width
        }
    }
}

/// Switches ownership of the center toolbar slot only after the sidebar has reached its endpoint.
/// The surrounding toolbar is hidden while AppKit installs or removes its native title item.
// MARK: - Welcome screen

private struct WelcomeView: View {
    @Environment(DocumentStore.self) private var store

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Markfops")
                .font(.largeTitle.bold())

            HStack(spacing: 12) {
                Button("New Document") { store.newDocument() }
                    .keyboardShortcut("n", modifiers: .command)
                    .buttonStyle(.borderedProminent)

                Button("Open…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!]
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        store.coordinator?.open(
                            urls: panel.urls,
                            preferredWindowID: store.windowID
                        )
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}
