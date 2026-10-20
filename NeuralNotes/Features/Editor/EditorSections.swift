import Foundation
import NeuralNotesCore

extension EditorViewModel {
    @discardableResult
    func changeSections(_ action: (DocumentWorkspace) async throws -> Void) async -> Bool {
        guard hasLease, !loading, !navigating, !hasActiveStroke else { return false }
        navigating = true; defer { navigating = false }
        guard await flush(), !hasActiveStroke else { return false }
        do {
            try await action(workspace)
            sections = try await workspace.catalog().sections ?? []
            scheduleMaintenance(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
