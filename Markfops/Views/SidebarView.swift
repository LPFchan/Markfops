import SwiftUI
import UniformTypeIdentifiers
import AppKit
import QuartzCore

private let sidebarTOCContentSpace = "SidebarTOCContentSpace"
private let sidebarScrollViewportSpace = "SidebarScrollViewportSpace"

private struct TOCHeadingMidYKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct SidebarDocumentHeaderMinYKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private final class SidebarScrollContext {
    weak var scrollView: NSScrollView?
    var lastTargetY: CGFloat?
    var desiredTargetY: CGFloat?
    var displayTimer: Timer?
    var lastStepTime: CFTimeInterval?
    var velocity: CGFloat = 0
    var isProgrammaticScroll = false
    var liveScrollObserver: NSObjectProtocol?
    var endLiveScrollObserver: NSObjectProtocol?
    var isRespectingManualScrollPosition = false
    var suppressTOCFollowUntil: CFTimeInterval = 0
}

private struct SidebarScrollViewAccessor: NSViewRepresentable {
    let context: SidebarScrollContext
    let onResolve: () -> Void

    func makeNSView(context _: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            self.resolveScrollView(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            self.resolveScrollView(from: nsView)
        }
    }

    private func resolveScrollView(from view: NSView) {
        var current: NSView? = view
        while let candidate = current {
            if let scrollView = candidate.enclosingScrollView {
                if context.scrollView !== scrollView {
                    context.scrollView = scrollView
                    onResolve()
                }
                return
            }
            current = candidate.superview
        }
    }
}

struct SidebarView: View {
    private static let tocFollowScrollLeadDelay: CFTimeInterval = 0.008
    private static let documentPinSuppressFollowDuration: CFTimeInterval = 0.38
    private static let documentPinRetargetDelay: CFTimeInterval = 0.09
    private static let documentPinRetargetAttempts = 5
    private static let initialTOCSyncDelay: CFTimeInterval = 0.12
    private static let initialTOCSyncAttempts = 5
    private static let tocFollowScrollStiffness: CGFloat = 30
    private static let tocFollowScrollDamping: CGFloat = 12
    private static let tocFollowScrollSettlingDistance: CGFloat = 0.12
    private static let tocFollowScrollSettlingVelocity: CGFloat = 1.2
    private static let tocFollowScrollNearTargetDistance: CGFloat = 14
    private static let tocFollowScrollNearTargetVelocityDamping: CGFloat = 0.46
    private static let tocFollowScrollFinalApproachDistance: CGFloat = 5
    private static let tocFollowScrollFinalApproachVelocityDamping: CGFloat = 0.24
    private static let tocRowHeight: CGFloat = 24
    private static let sidebarContentTopPadding: CGFloat = 4
    private static let documentHeaderPinTolerance: CGFloat = 1.5
    // The pinned document pill/header occupies the top of the scroll view, so TOC rows
    // hidden behind it are not actually visible even if their geometry is within bounds.
    private static let tocPinnedHeaderVisibilityInset: CGFloat = 42
    private static let tocBottomVisibilityPadding: CGFloat = 10
    private static let tocCenterReactivationBand: CGFloat = 30

    @Environment(DocumentStore.self) private var store
    var onTOCTap: (HeadingNode) -> Void
    /// Passed from ContentView so the toolbar + button hides when the sidebar itself is hidden (compact mode).
    @Binding var columnVisibility: NavigationSplitViewVisibility

    /// Per-document TOC visibility — collapses on deselect, restores on reselect.
    @State private var tocVisible: [UUID: Bool] = [:]
    /// Index before which the accent insertion line is shown during a cross-window drag.
    @State private var dropInsertionIndex: Int? = nil
    @State private var pendingTOCFollowScroll: DispatchWorkItem? = nil
    @State private var headingMidYByID: [String: CGFloat] = [:]
    @State private var documentHeaderMinYByID: [UUID: CGFloat] = [:]
    @State private var scrollContext = SidebarScrollContext()
    @State private var pendingImmediateTOCScrollTarget: String? = nil
    @State private var pendingDocumentPinWorkItem: DispatchWorkItem? = nil
    @State private var pendingInitialTOCSyncWorkItem: DispatchWorkItem? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(Array(store.documents.enumerated()), id: \.element.id) { i, document in
                        Section {
                            // Collapse TOC while this pill is being dragged
                            let isVisible = (tocVisible[document.id] ?? false)
                                && TabDragState.shared.draggingDocumentID != document.id
                            if isVisible && !document.headings.isEmpty {
                                ForEach(visibleHeadings(for: document), id: \.id) { heading in
                                    TOCItemView(
                                        heading: heading,
                                        isHighlighted: document.activeHeadingID == heading.id,
                                        isCollapsible: headingHasChildren(heading, in: document),
                                        isCollapsed: document.collapsedHeadingIDs.contains(heading.id),
                                        onTap: {
                                            pendingImmediateTOCScrollTarget = heading.id
                                            if store.activeID != document.id {
                                                store.activeID = document.id
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                                    onTOCTap(heading)
                                                }
                                            } else {
                                                onTOCTap(heading)
                                            }
                                        },
                                        onToggleCollapse: {
                                            withAnimation(.spring(duration: 0.22)) {
                                                toggleCollapse(heading, in: document)
                                            }
                                        }
                                    )
                                    .id(heading.id)
                                    .padding(.horizontal, 6)
                                    .background {
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: TOCHeadingMidYKey.self,
                                                value: [heading.id: geo.frame(in: .named(sidebarTOCContentSpace)).midY]
                                            )
                                        }
                                    }
                                }
                                .padding(.bottom, 4)
                            }
                        } header: {
                            sectionHeader(document: document, index: i)
                        }  // Section
                    }  // ForEach
                }  // LazyVStack
                .padding(.vertical, 4)
                .coordinateSpace(name: sidebarTOCContentSpace)
                .background {
                    SidebarScrollViewAccessor(
                        context: scrollContext,
                        onResolve: {
                            if let scrollView = scrollContext.scrollView {
                                installScrollObserverIfNeeded(for: scrollView)
                            }
                            store.activeDocument?.syncActiveHeadingToScrollPosition()
                            scheduleScrollToActiveHeading(force: true)
                        }
                    )
                    .frame(width: 0, height: 0)
                }
            }
            .coordinateSpace(name: sidebarScrollViewportSpace)
            .onPreferenceChange(TOCHeadingMidYKey.self) { values in
                headingMidYByID = values
                scheduleScrollToActiveHeading()
            }
            .onPreferenceChange(SidebarDocumentHeaderMinYKey.self) { values in
                documentHeaderMinYByID = values
                if let activeID = store.activeID,
                   let headerMinY = values[activeID] {
                    if scrollContext.suppressTOCFollowUntil > CACurrentMediaTime() {
                        scrollDocumentHeaderToTop(documentID: activeID)
                    }
                    if headerMinY <= Self.sidebarContentTopPadding + Self.documentHeaderPinTolerance,
                       store.activeDocument?.activeHeadingID != nil {
                        scheduleScrollToActiveHeading(force: true)
                    }
                }
            }
            .onChange(of: store.activeID) { oldID, newID in
                pendingDocumentPinWorkItem?.cancel()
                pendingInitialTOCSyncWorkItem?.cancel()
                // Collapse outgoing document (persist its expanded intent first)
                if let old = oldID,
                   let doc = store.documents.first(where: { $0.id == old }) {
                    doc.isTOCExpanded = tocVisible[old] ?? false
                    scrollContext.lastTargetY = nil
                    scrollContext.suppressTOCFollowUntil = 0
                    scrollContext.isRespectingManualScrollPosition = false
                    withAnimation(.spring(duration: 0.22)) {
                        tocVisible[old] = false
                    }
                }
                // Restore incoming document's TOC
                if let new = newID,
                   let doc = store.documents.first(where: { $0.id == new }) {
                    doc.syncActiveHeadingToScrollPosition()
                    scrollContext.lastTargetY = nil
                    scrollContext.suppressTOCFollowUntil = CACurrentMediaTime() + Self.documentPinSuppressFollowDuration
                    scrollContext.isRespectingManualScrollPosition = false
                    withAnimation(.spring(duration: 0.22)) {
                        tocVisible[new] = doc.isTOCExpanded
                    }
                    scheduleDocumentHeaderPin(documentID: new)
                    scheduleInitialTOCSync(documentID: new)
                }
            }
            .onChange(of: store.activeDocument?.activeHeadingID) { _, newID in
                let shouldForce = newID != nil && newID == pendingImmediateTOCScrollTarget
                if shouldForce {
                    pendingImmediateTOCScrollTarget = nil
                }
                if newID != nil {
                    scrollContext.isRespectingManualScrollPosition = false
                }
                scheduleScrollToActiveHeading(force: shouldForce)
            }
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
        .toolbar {
            // Only show the + button when the sidebar column is actually visible.
            // In compact mode the pill bar already has its own + button.
            if columnVisibility != .detailOnly {
                ToolbarItemGroup(placement: .automatic) {
                    Spacer()
                    Button(action: { store.newDocument() }) {
                        Image(systemName: "plus")
                    }
                    .help("New Document  ⌘N")
                }
            }
        }
        .onAppear {
            for doc in store.documents {
                tocVisible[doc.id] = doc.isTOCExpanded && doc.id == store.activeID
            }
        }
        .onDisappear {
            pendingInitialTOCSyncWorkItem?.cancel()
            removeScrollObserver()
            stopTOCFollowAnimation()
        }
    }

    // MARK: - Section header (extracted to help Swift type-checker)

    @ViewBuilder
    private func sectionHeader(document: Document, index: Int) -> some View {
        let isDragging    = TabDragState.shared.draggingDocumentID == document.id
        let isAnyDragging = TabDragState.shared.draggingDocumentID != nil
        let translation   = TabDragState.shared.dragTranslation
        // In the sidebar (vertical list), horizontal drag = detach; vertical drag = reorder.
        let inDetachZone  = isDragging && abs(translation.width) > 60

        VStack(spacing: 0) {
            if dropInsertionIndex == index {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 1.5)
                    .padding(.horizontal, 14)
                    .transition(.opacity)
            }
            SidebarTabRowView(
                document: document,
                isActive: store.activeID == document.id,
                isTOCVisible: Binding(
                    get: { tocVisible[document.id] ?? false },
                    set: { tocVisible[document.id] = $0 }
                ),
                onSelect: { store.activeID = document.id },
                onClose: { store.close(id: document.id) },
                isInDetachZone: inDetachZone
            )
            .id(document.id)
            .padding(.horizontal, 6)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: SidebarDocumentHeaderMinYKey.self,
                        value: [document.id: geo.frame(in: .named(sidebarScrollViewportSpace)).minY]
                    )
                }
            }
            .opacity(isAnyDragging && !isDragging ? 0.45 : 1.0)
            .scaleEffect(
                inDetachZone ? 1.04 : (isDragging ? 1.03 : (isAnyDragging ? 0.97 : 1.0)),
                anchor: .trailing
            )
            .shadow(
                color: isDragging ? .black.opacity(0.25) : .clear,
                radius: inDetachZone ? 12 : (isDragging ? 8 : 0),
                y: isDragging ? 4 : 0
            )
            .offset(
                x: isDragging ? translation.width : 0,
                y: isDragging ? translation.height : 0
            )
            .zIndex(isDragging ? 100 : 0)
            .animation(.spring(duration: 0.22), value: isDragging)
            .animation(.spring(duration: 0.18), value: inDetachZone)
            .animation(.spring(duration: 0.15), value: isAnyDragging)
            .onDrag { makeDragProvider(for: document) }
            .onDrop(of: [TabDragState.documentDragType],
                    delegate: DocumentDropDelegate(
                        targetDocument: document,
                        store: store,
                        onInsertionIndexChange: { idx in
                            withAnimation(.spring(duration: 0.12)) {
                                dropInsertionIndex = idx
                            }
                        }
                    ))
        }
    }

    private func makeDragProvider(for document: Document) -> NSItemProvider {
        TabDragState.shared.begin(documentID: document.id, from: store)

        var upMonitor:   Any?
        var moveMonitor: Any?

        // Global monitors (not local) so events are received during system drag sessions.
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { event in
            DispatchQueue.main.async {
                TabDragState.shared.dragTranslation.width  += event.deltaX
                TabDragState.shared.dragTranslation.height -= event.deltaY
            }
        }

        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            if let m = upMonitor   { NSEvent.removeMonitor(m) }
            if let m = moveMonitor { NSEvent.removeMonitor(m) }
            upMonitor = nil; moveMonitor = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard TabDragState.shared.draggingDocumentID == document.id else { return }
                let shouldDetach = TabDragState.shared.wasInDetachZone
                TabDragState.shared.reset()
                if shouldDetach { store.detachToNewWindow(document) }
            }
        }

        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: TabDragState.documentDragType.identifier,
            visibility: .all
        ) { completion in
            let data = document.id.uuidString.data(using: .utf8) ?? Data()
            completion(data, nil)
            return nil
        }
        return provider
    }

    // MARK: - TOC helpers

    private func visibleHeadings(for document: Document) -> [HeadingNode] {
        let headings = document.headings.filter { $0.level > 1 }
        var result: [HeadingNode] = []
        var hiddenBelowLevel: Int? = nil

        for heading in headings {
            if let barrier = hiddenBelowLevel {
                if heading.level > barrier { continue }
                hiddenBelowLevel = nil
            }
            result.append(heading)
            if document.collapsedHeadingIDs.contains(heading.id) {
                hiddenBelowLevel = heading.level
            }
        }
        return result
    }

    private func headingHasChildren(_ heading: HeadingNode, in document: Document) -> Bool {
        let headings = document.headings.filter { $0.level > 1 }
        guard let idx = headings.firstIndex(where: { $0.id == heading.id }),
              idx + 1 < headings.count else { return false }
        return headings[idx + 1].level > heading.level
    }

    private func toggleCollapse(_ heading: HeadingNode, in document: Document) {
        if document.collapsedHeadingIDs.contains(heading.id) {
            document.collapsedHeadingIDs.remove(heading.id)
        } else {
            document.collapsedHeadingIDs.insert(heading.id)
        }
    }

    private func scheduleScrollToActiveHeading(force: Bool = false) {
        pendingTOCFollowScroll?.cancel()
        let workItem = DispatchWorkItem {
            scrollToActiveHeading(force: force)
        }
        pendingTOCFollowScroll = workItem
        let delay = force ? 0 : Self.tocFollowScrollLeadDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scrollToActiveHeading(force: Bool = false) {
        guard let document = store.activeDocument,
              (tocVisible[document.id] ?? false),
              let activeHeadingID = document.activeHeadingID,
              let scrollView = scrollContext.scrollView else { return }

        if let headerMinY = documentHeaderMinYByID[document.id],
           headerMinY > Self.sidebarContentTopPadding + Self.documentHeaderPinTolerance {
            scrollDocumentHeaderToTop(documentID: document.id)
            return
        }

        let now = CACurrentMediaTime()
        if !force, scrollContext.suppressTOCFollowUntil > now {
            return
        }

        guard let targetMidY = headingMidYByID[activeHeadingID] else { return }

        let viewportHeight = scrollView.contentView.bounds.height
        let visibleRect = scrollView.contentView.bounds
        let rowHalfHeight = Self.tocRowHeight / 2
        let topVisibleY = visibleRect.minY + Self.tocPinnedHeaderVisibilityInset + rowHalfHeight
        let bottomVisibleY = visibleRect.maxY - Self.tocBottomVisibilityPadding - rowHalfHeight
        let centerY = (topVisibleY + bottomVisibleY) / 2

        if !force,
           scrollContext.isRespectingManualScrollPosition {
            let isVisible = targetMidY >= topVisibleY && targetMidY <= bottomVisibleY
            if !isVisible || targetMidY > centerY {
                scrollContext.isRespectingManualScrollPosition = false
            } else {
                scrollContext.lastTargetY = nil
                scrollContext.desiredTargetY = nil
                stopTOCFollowAnimation()
                return
            }
        }

        let contentHeight = scrollView.documentView?.bounds.height ?? 0
        let maxOffset = max(0, contentHeight - viewportHeight)
        let centeredTargetY = max(0, min(maxOffset, targetMidY - viewportHeight / 2))
        let targetY: CGFloat
        if !force, scrollContext.isRespectingManualScrollPosition {
            if targetMidY > bottomVisibleY {
                targetY = centeredTargetY
            } else {
                targetY = minimalRevealOffset(for: targetMidY, in: scrollView, maxOffset: maxOffset)
            }
        } else {
            targetY = centeredTargetY
        }

        if !force,
           let lastTargetY = scrollContext.lastTargetY,
           abs(lastTargetY - targetY) < Self.tocFollowScrollSettlingDistance {
            return
        }

        scrollContext.lastTargetY = targetY
        scrollContext.desiredTargetY = targetY

        if force,
           scrollContext.displayTimer == nil,
           let clipView = scrollView.contentView as NSClipView? {
            clipView.setBoundsOrigin(NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(clipView)
            scrollContext.velocity = 0
        }

        startTOCFollowAnimationIfNeeded()
    }

    private func scrollDocumentHeaderToTop(documentID: UUID) {
        guard let scrollView = scrollContext.scrollView,
              let headerMinY = documentHeaderMinYByID[documentID] else { return }

        let currentOffset = scrollView.contentView.bounds.minY
        let viewportHeight = scrollView.contentView.bounds.height
        let contentHeight = scrollView.documentView?.bounds.height ?? 0
        let maxOffset = max(0, contentHeight - viewportHeight)
          let targetY = max(0, min(maxOffset, currentOffset + headerMinY - Self.sidebarContentTopPadding))

        scrollContext.suppressTOCFollowUntil = CACurrentMediaTime() + Self.documentPinSuppressFollowDuration
        scrollContext.lastTargetY = targetY
        scrollContext.desiredTargetY = targetY
        startTOCFollowAnimationIfNeeded()
    }

    private func scheduleDocumentHeaderPin(documentID: UUID, attemptsRemaining: Int = Self.documentPinRetargetAttempts) {
        pendingDocumentPinWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            guard store.activeID == documentID else { return }

            scrollDocumentHeaderToTop(documentID: documentID)

            guard attemptsRemaining > 1,
                  let headerMinY = documentHeaderMinYByID[documentID],
                  abs(headerMinY - Self.sidebarContentTopPadding) > 0.75 else { return }

            scheduleDocumentHeaderPin(documentID: documentID, attemptsRemaining: attemptsRemaining - 1)
        }

        pendingDocumentPinWorkItem = workItem
        let initialDelay: CFTimeInterval = attemptsRemaining == Self.documentPinRetargetAttempts ? 0.25 : Self.documentPinRetargetDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay, execute: workItem)
    }

    private func scheduleInitialTOCSync(documentID: UUID, attemptsRemaining: Int = Self.initialTOCSyncAttempts) {
        pendingInitialTOCSyncWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            guard store.activeID == documentID,
                  let document = store.activeDocument else { return }

            document.syncActiveHeadingToScrollPosition()
            scheduleScrollToActiveHeading(force: true)

            guard attemptsRemaining > 1,
                  let activeHeadingID = document.activeHeadingID,
                  headingMidYByID[activeHeadingID] == nil else { return }

            scheduleInitialTOCSync(documentID: documentID, attemptsRemaining: attemptsRemaining - 1)
        }

        pendingInitialTOCSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialTOCSyncDelay, execute: workItem)
    }

    private func startTOCFollowAnimationIfNeeded() {
        guard scrollContext.displayTimer == nil else { return }

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { _ in
            stepTOCFollowAnimation()
        }
        timer.tolerance = 1.0 / 240.0
        RunLoop.main.add(timer, forMode: .common)
        scrollContext.displayTimer = timer
        scrollContext.lastStepTime = CACurrentMediaTime()
    }

    private func stopTOCFollowAnimation() {
        scrollContext.displayTimer?.invalidate()
        scrollContext.displayTimer = nil
        scrollContext.lastStepTime = nil
        scrollContext.velocity = 0
        scrollContext.isProgrammaticScroll = false
    }

    private func stepTOCFollowAnimation() {
        guard let scrollView = scrollContext.scrollView,
              let targetY = scrollContext.desiredTargetY else {
            stopTOCFollowAnimation()
            return
        }

        let now = CACurrentMediaTime()
        let dt = min(1.0 / 30.0, max(1.0 / 240.0, now - (scrollContext.lastStepTime ?? now)))
        scrollContext.lastStepTime = now

        let clipView = scrollView.contentView
        let currentY = clipView.bounds.origin.y
        let displacement = targetY - currentY

        let acceleration = Self.tocFollowScrollStiffness * displacement - Self.tocFollowScrollDamping * scrollContext.velocity
        scrollContext.velocity += acceleration * dt
        if abs(displacement) < Self.tocFollowScrollNearTargetDistance {
            scrollContext.velocity *= Self.tocFollowScrollNearTargetVelocityDamping
        }
        if abs(displacement) < Self.tocFollowScrollFinalApproachDistance {
            scrollContext.velocity *= Self.tocFollowScrollFinalApproachVelocityDamping
        }
        var nextY = currentY + scrollContext.velocity * dt

        let viewportHeight = clipView.bounds.height
        let contentHeight = scrollView.documentView?.bounds.height ?? 0
        let maxOffset = max(0, contentHeight - viewportHeight)
        nextY = max(0, min(maxOffset, nextY))

        scrollContext.isProgrammaticScroll = true
        clipView.setBoundsOrigin(NSPoint(x: 0, y: nextY))
        scrollView.reflectScrolledClipView(clipView)
        scrollContext.isProgrammaticScroll = false

        if abs(targetY - nextY) < Self.tocFollowScrollSettlingDistance,
           abs(scrollContext.velocity) < Self.tocFollowScrollSettlingVelocity {
            scrollContext.lastTargetY = targetY
            scrollContext.desiredTargetY = nil
            scrollContext.velocity = 0
            stopTOCFollowAnimation()
        }
    }

    private func installScrollObserverIfNeeded(for scrollView: NSScrollView) {
        guard scrollContext.liveScrollObserver == nil,
              scrollContext.endLiveScrollObserver == nil else { return }

        scrollContext.liveScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { _ in
            guard !scrollContext.isProgrammaticScroll else { return }
            scrollContext.isRespectingManualScrollPosition = true
            scrollContext.desiredTargetY = nil
            scrollContext.lastTargetY = nil
            stopTOCFollowAnimation()
        }

        scrollContext.endLiveScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { _ in
            guard !scrollContext.isProgrammaticScroll else { return }
            scrollContext.lastTargetY = nil
            scheduleScrollToActiveHeading()
        }
    }

    private func removeScrollObserver() {
        if let observer = scrollContext.liveScrollObserver {
            NotificationCenter.default.removeObserver(observer)
            scrollContext.liveScrollObserver = nil
        }
        if let observer = scrollContext.endLiveScrollObserver {
            NotificationCenter.default.removeObserver(observer)
            scrollContext.endLiveScrollObserver = nil
        }
    }

    private func isHeadingVisible(at midY: CGFloat, in scrollView: NSScrollView) -> Bool {
        let rowHalfHeight = Self.tocRowHeight / 2
        let visibleRect = scrollView.contentView.bounds
        let minY = visibleRect.minY + Self.tocPinnedHeaderVisibilityInset + rowHalfHeight
        let maxY = visibleRect.maxY - Self.tocBottomVisibilityPadding - rowHalfHeight
        return midY >= minY && midY <= maxY
    }

    private func isHeadingNearCenter(at midY: CGFloat, in scrollView: NSScrollView) -> Bool {
        let visibleRect = scrollView.contentView.bounds
        let top = visibleRect.minY + Self.tocPinnedHeaderVisibilityInset
        let bottom = visibleRect.maxY - Self.tocBottomVisibilityPadding
        guard bottom > top else { return false }
        let centerY = (top + bottom) / 2
        return abs(midY - centerY) <= Self.tocCenterReactivationBand
    }

    private func minimalRevealOffset(for midY: CGFloat, in scrollView: NSScrollView, maxOffset: CGFloat) -> CGFloat {
        let rowHalfHeight = Self.tocRowHeight / 2
        let visibleRect = scrollView.contentView.bounds
        let minY = visibleRect.minY + Self.tocPinnedHeaderVisibilityInset + rowHalfHeight
        let maxY = visibleRect.maxY - Self.tocBottomVisibilityPadding - rowHalfHeight

        if midY < minY {
            return max(0, midY - Self.tocPinnedHeaderVisibilityInset - rowHalfHeight)
        }
        if midY > maxY {
            return min(maxOffset, midY - visibleRect.height + Self.tocBottomVisibilityPadding + rowHalfHeight)
        }
        return visibleRect.minY
    }
}
