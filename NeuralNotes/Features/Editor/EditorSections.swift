import Foundation
import NeuralNotesCore

extension EditorViewModel {
    @discardableResult
    func changeSections(_ action: (DocumentWorkspace) async throws -> Void) async -> Bool {
        guard hasLease, !loading, !navigating, !hasActiveStroke else { return false }
        navigating = true; defer { navigating = false }
        guard await flush(), !hasActiveStroke else { return false }
        do {
            let before = try await workspace.catalog().sections ?? []
            try await action(workspace)
            sections = try await workspace.catalog().sections ?? []
            if before != sections {
                let cost = (try? JSONEncoder().encode(before).count) ?? 0
                history.record(.sections(before, sections), label: "Modifica sezioni", cost: cost * 2)
            }
            scheduleMaintenance(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
