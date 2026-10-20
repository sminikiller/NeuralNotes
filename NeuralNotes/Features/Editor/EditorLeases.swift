import Foundation
import Observation

/// One writable editor per document across all scenes; readers/search can share
/// the workspace actor. A new window never silently overwrites another canvas.
@MainActor @Observable
final class EditorLeases {
    static let shared = EditorLeases()
    private struct Owner { weak var editor: EditorViewModel?; let id: UUID }
    private var owners: [UUID: Owner] = [:]
    private var cloudWriters: Set<UUID> = []
    func reserveCloud(_ document: UUID) -> Bool {
        guard owners[document]?.editor == nil, !cloudWriters.contains(document) else { return false }
        cloudWriters.insert(document); return true
    }
    func releaseCloud(_ document: UUID) { cloudWriters.remove(document) }
    func acquire(document: UUID, owner: UUID, editor: EditorViewModel) -> Bool {
        guard !cloudWriters.contains(document) else { return false }
        guard owners[document]?.editor == nil || owners[document]?.id == owner else { return false }
        owners[document] = Owner(editor: editor, id: owner); return true
    }
    func release(document: UUID, owner: UUID) { if owners[document]?.id == owner { owners[document] = nil } }
    func isOpen(_ document: UUID) -> Bool { owners[document]?.editor != nil }
}
