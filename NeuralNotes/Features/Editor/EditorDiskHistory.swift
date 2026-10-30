import Foundation
import NeuralNotesCore

/// One logical action may change thousands of pages, but owns only immutable
/// snapshot references and page identities in memory.
struct EditorDiskChange {
    let before: PageEditSnapshot, after: PageEditSnapshot
    let beforeOrder: [UUID], afterOrder: [UUID]
    let beforePage: UUID, afterPage: UUID
    var residentCost: Int { before.residentCost + after.residentCost + (beforeOrder.count + afterOrder.count) * 24 }
    var diskCost: Int64 {
        let sum = before.byteCount.addingReportingOverflow(after.byteCount)
        return sum.overflow ? Int64.max : sum.partialValue
    }
}

@MainActor
extension EditorViewModel {
    /// The caller prepares both snapshots before any document mutation.
    func applyDiskChange(_ change: EditorDiskChange, label: String) async throws {
        guard history.accepts(cost: change.residentCost) else { throw WorkspaceFailure.oversizedImport }
        try await restoreDiskChange(change, undo: false)
        history.record(.disk(change), label: label, cost: change.residentCost, diskCost: change.diskCost)
    }
    func restoreDiskChange(_ change: EditorDiskChange, undo: Bool) async throws {
        let target = undo ? change.before : change.after
        var revisions: [UUID: Int] = [:]
        for id in target.pageIDs {
            if let current = try await workspace.retainedPageSnapshot(id) { revisions[id] = current.revision }
        }
        try await workspace.applyPageEdit(target, expectedOrder: undo ? change.afterOrder : change.beforeOrder,
            newOrder: undo ? change.beforeOrder : change.afterOrder, expectedRevisions: revisions)
        for id in Set(change.before.pageIDs).union(change.after.pageIDs) { PageWordIndex.shared.invalidatePage(id) }
        pages = try await workspace.pages()
        let focus = undo ? change.beforePage : change.afterPage
        if let selected = pages.first(where: { $0.id == focus }) ?? pages.first { try await load(selected) }
        scheduleMaintenance()
    }
}
