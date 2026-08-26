import Foundation
import os.signpost

/// Signposts for the tab-switch hot path. Record Markfops with Instruments' "Points of Interest"
/// template and filter for the Markfops subsystem.
enum TabSwitchProfiler {
    private struct ActiveSwitch {
        let targetDocumentID: UUID
        let signpostID: OSSignpostID
    }

    static let log = OSLog(
        subsystem: "com.markfops.Markfops",
        category: .pointsOfInterest
    )

    private static var activeSwitchesByWindow: [UUID: ActiveSwitch] = [:]
    private static var scheduledFinishWindows: Set<UUID> = []

    static func beginSwitch(windowID: UUID, from oldDocumentID: UUID?, to document: Document) {
        scheduledFinishWindows.remove(windowID)
        if let unfinished = activeSwitchesByWindow.removeValue(forKey: windowID) {
            os_signpost(
                .end,
                log: log,
                name: "Tab Switch",
                signpostID: unfinished.signpostID,
                "result=%{public}s",
                "superseded"
            )
        }

        let signpostID = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: "Tab Switch",
            signpostID: signpostID,
            "from=%{public}@ to=%{public}@ chars=%{public}ld lines=%{public}ld mode=%{public}s",
            oldDocumentID?.uuidString as NSString? ?? "none",
            document.id.uuidString as NSString,
            document.textStorage.length,
            document.lineCount,
            document.mode == .edit ? "edit" : "preview"
        )
        activeSwitchesByWindow[windowID] = ActiveSwitch(
            targetDocumentID: document.id,
            signpostID: signpostID
        )
    }

    static func finishSwitch(documentID: UUID, surface: String) {
        guard let entry = activeSwitchesByWindow.first(where: {
            $0.value.targetDocumentID == documentID
        }), scheduledFinishWindows.insert(entry.key).inserted else { return }

        os_signpost(
            .event,
            log: log,
            name: "Native Surface Updated",
            "surface=%{public}@",
            surface as NSString
        )
        DispatchQueue.main.async {
            scheduledFinishWindows.remove(entry.key)
            finishSwitchAfterMainQueueSettles(
                windowID: entry.key,
                documentID: documentID,
                surface: surface
            )
        }
    }

    private static func finishSwitchAfterMainQueueSettles(
        windowID: UUID,
        documentID: UUID,
        surface: String
    ) {
        guard let activeSwitch = activeSwitchesByWindow[windowID],
              activeSwitch.targetDocumentID == documentID else { return }

        activeSwitchesByWindow.removeValue(forKey: windowID)
        os_signpost(
            .end,
            log: log,
            name: "Tab Switch",
            signpostID: activeSwitch.signpostID,
            "surface=%{public}@",
            surface as NSString
        )
    }

    static func beginInterval(
        _ name: StaticString,
        document: Document,
        active: Bool
    ) -> OSSignpostID {
        let signpostID = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: name,
            signpostID: signpostID,
            "chars=%{public}ld lines=%{public}ld active=%{public}d",
            document.textStorage.length,
            document.lineCount,
            active ? 1 : 0
        )
        return signpostID
    }

    static func endInterval(_ name: StaticString, signpostID: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: signpostID)
    }

    static func selected(document: Document, wasMounted: Bool, mountedCount: Int) {
        os_signpost(
            .event,
            log: log,
            name: "Surface Selected",
            "chars=%{public}ld lines=%{public}ld warm=%{public}d mounted=%{public}ld mode=%{public}s",
            document.textStorage.length,
            document.lineCount,
            wasMounted ? 1 : 0,
            mountedCount,
            document.mode == .edit ? "edit" : "preview"
        )
    }

    static func surfaceStackAppeared(
        instanceID: UUID,
        activeID: UUID?,
        mountedCount: Int,
        documentCount: Int
    ) {
        surfaceStackLifecycle(
            "Surface Stack Appear",
            instanceID: instanceID,
            activeID: activeID,
            mountedCount: mountedCount,
            documentCount: documentCount
        )
    }

    static func surfaceStackDisappeared(
        instanceID: UUID,
        activeID: UUID?,
        mountedCount: Int,
        documentCount: Int
    ) {
        surfaceStackLifecycle(
            "Surface Stack Disappear",
            instanceID: instanceID,
            activeID: activeID,
            mountedCount: mountedCount,
            documentCount: documentCount
        )
    }

    static func viewStateChanged(_ state: String, from oldValue: String, to newValue: String) {
        os_signpost(
            .event,
            log: log,
            name: "View State Changed",
            "state=%{public}@ from=%{public}@ to=%{public}@",
            state as NSString,
            oldValue as NSString,
            newValue as NSString
        )
    }

    private static func surfaceStackLifecycle(
        _ name: StaticString,
        instanceID: UUID,
        activeID: UUID?,
        mountedCount: Int,
        documentCount: Int
    ) {
        os_signpost(
            .event,
            log: log,
            name: name,
            "instance=%{public}@ active=%{public}@ mounted=%{public}ld documents=%{public}ld",
            instanceID.uuidString as NSString,
            activeID?.uuidString as NSString? ?? "none",
            mountedCount,
            documentCount
        )
    }
}
