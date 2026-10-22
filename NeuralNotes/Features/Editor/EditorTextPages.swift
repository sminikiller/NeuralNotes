import Foundation
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    /// Appends editable text pages (for example a lecture "sbobina") after the
    /// last page, with the notebook's paper; one undo step removes them again.
    @discardableResult
    func appendTextPages(_ texts: [String], label: String) async -> Bool {
        guard hasLease, !loading, !navigating, !hasActiveStroke, !texts.isEmpty, texts.count <= 200 else { return false }
        navigating = true; defer { navigating = false }
        guard await flush() else { return false }
        do {
            let catalog = try await workspace.catalog()
            let order = pages.map(\.id), selected = page?.id
            var first: PageSnapshot?
            for value in texts {
                var next = catalog.defaultPageTemplate?.makePage() ?? PageSnapshot()
                if catalog.defaultPageTemplate == nil, let page { next.width = page.width; next.height = page.height; next.paper = page.paper; next.appearance = page.appearance }
                var text = TextElement(text: value); text.fontSize = 16
                text.x = 48; text.y = 56; text.width = max(200, next.width - 96)
                next.texts = [text]
                let created = try await workspace.addPage(next)
                if first == nil { first = created }
            }
            if let first { try await load(first) }
            recordOrder(order, selectedBefore: selected, label: label)
            scheduleMaintenance()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
