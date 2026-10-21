import Foundation
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    @discardableResult
    func createMindMap(from artifact: AIArtifact) async -> Bool {
        guard hasLease, !loading, !navigating, !hasActiveStroke else { return false }
        navigating = true; defer { navigating = false }
        guard await flush() else { return false }
        do {
            guard let map = MindMapLayout.page(from: artifact) else { error = "Lo schema deve contenere un titolo e almeno un punto. Seleziona Schema e genera prima l’elaborazione."; return false }
            let order = pages.map(\.id), selected = page?.id
            let created = try await workspace.addPage(map); try await load(created)
            recordOrder(order, selectedBefore: selected, label: "Crea mappa modificabile")
            tool = .objects; selectedObjectID = nil; configureTool(); scheduleMaintenance()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
