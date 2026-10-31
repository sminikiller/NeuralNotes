import Foundation
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    func typeDeletionPreview(pageIDs requested: Set<UUID>, wholeNotebook: Bool = false, progress: (Int, Int) -> Void = { _, _ in }) async throws -> TypeDeletionPreview {
        try Task.checkCancellation()
        finishInkGesture(); endTextEdit()
        guard hasLease, !loading, !navigating, !hasActiveStroke, await flush() else { throw TypeDeletionFailure.unavailable }
        let order = try await workspace.manifest().pageIDs
        guard !requested.isEmpty, requested.isSubset(of: Set(order)) else { throw TypeDeletionFailure.changed }
        let ids = order.filter { requested.contains($0) }
        var counts: [PageDeletionKind: Int] = [:], revisions: [UUID: Int] = [:]
        for (offset, id) in ids.enumerated() {
            try Task.checkCancellation()
            let page = try await workspace.pageSnapshot(id), data = try await workspace.drawing(page)
            let result = try await Task.detached(priority: .userInitiated) { try TypeDeletionInk.process(data, page: page) }.value
            try Task.checkCancellation()
            revisions[id] = page.revision
            for (kind, count) in result.counts { counts[kind, default: 0] += count }
            progress(offset + 1, ids.count)
        }
        return TypeDeletionPreview(order: order, pageIDs: ids, revisions: revisions, counts: counts,
            requiresBackup: wholeNotebook || (order.count > 1 && ids.count == order.count))
    }

    /// Preparation streams a page at a time. The final disk transaction and its
    /// one history entry cover every affected page, without reverting audio.
    @discardableResult
    func deleteTypes(_ kinds: Set<PageDeletionKind>, preview: TypeDeletionPreview,
                     progress: (String) -> Void = { _ in }) async throws -> Int {
        try Task.checkCancellation()
        finishInkGesture(); endTextEdit()
        guard hasLease, !loading, !navigating, !hasActiveStroke, audio?.recording != true,
              audio?.compressionTask == nil, audio?.compressingSessionID == nil, let focus = page?.id,
              await flush() else { throw TypeDeletionFailure.unavailable }
        guard !kinds.isEmpty, preview.count(kinds) > 0 else { return 0 }
        navigating = true; cancelMaintenance()
        defer { navigating = false }
        let sessions = try await workspace.catalog().sessions
        guard sessions.allSatisfy({ $0.state != "recording" }), try await workspace.pendingAudioCompression() == nil else { throw TypeDeletionFailure.unavailable }
        let order = try await workspace.manifest().pageIDs
        guard order == preview.order, Set(preview.pageIDs).count == preview.pageIDs.count,
              !preview.pageIDs.isEmpty, Set(preview.pageIDs).isSubset(of: Set(order)) else { throw TypeDeletionFailure.changed }
        for id in preview.pageIDs {
            try Task.checkCancellation()
            guard try await workspace.pageSnapshot(id).revision == preview.revisions[id] else { throw TypeDeletionFailure.changed }
        }
        // Selecting all pages manually requires the same protection as the
        // explicit whole-notebook scope, even if automatic backups are off.
        if preview.requiresBackup || (order.count > 1 && preview.pageIDs.count == order.count) {
            progress("Creazione del backup preventivo…")
            guard let metadata = backupMetadata,
                  try await workspace.createAutomaticBackup(metadata: metadata, minimumInterval: 0) != nil else { throw TypeDeletionFailure.backupRequired }
        }
        let before = try PageEditSnapshotBuilder(documentID: workspace.documentID)
        let after = try PageEditSnapshotBuilder(documentID: workspace.documentID)
        let touchesInk = kinds.contains(.pen) || kinds.contains(.marker)
        var changed = 0, removed = 0
        for (offset, id) in preview.pageIDs.enumerated() {
            try Task.checkCancellation()
            var current = try await workspace.pageSnapshot(id)
            guard current.revision == preview.revisions[id] else { throw TypeDeletionFailure.changed }
            let data = touchesInk ? try await workspace.drawing(current) : nil
            let result: TypeDeletionInk.Result
            if touchesInk {
                let snapshot = current
                result = try await Task.detached(priority: .userInitiated) { try TypeDeletionInk.process(data, page: snapshot, removing: kinds) }.value
            } else { result = .init(counts: PageDeletion.metadataCounts(in: current), drawing: nil, anchors: current.anchors) }
            let count = kinds.reduce(0) { $0 + result.counts[$1, default: 0] }
            guard count > 0 else { progress("Preparazione \(offset + 1)/\(preview.pageIDs.count)"); continue }
            try await before.append(current, drawing: result.drawing == nil ? nil : data, sourcePackage: workspace.package)
            if current.connectors?.isEmpty == false { current.refreshConnectorFallbacks(objects: DiagramObjects.make(current)) }
            var next = PageDeletion.removing(kinds, from: current)
            if result.drawing != nil { next.anchors = kinds.contains(.audioLinks) ? [] : result.anchors }
            try await after.append(next, drawing: result.drawing, sourcePackage: workspace.package)
            changed += 1; removed += count
            progress("Preparazione \(offset + 1)/\(preview.pageIDs.count)")
        }
        guard changed > 0 else { return 0 }
        let oldState = try await before.finish(), newState = try await after.finish()
        let change = EditorDiskChange(before: oldState, after: newState, beforeOrder: order,
            afterOrder: order, beforePage: focus, afterPage: focus)
        try Task.checkCancellation()
        progress("Salvataggio delle pagine…")
        try await applyDiskChange(change, label: "Elimina elementi per tipo")
        status = "Eliminati \(removed) elementi · Annulla per ripristinare"
        return removed
    }
}
