import Foundation
import PencilKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    func useCurrentPDFAsTemplate() async -> Bool {
        guard let page, let file = page.pdfFile, let index = page.pdfIndex, !hasActiveStroke, await flush() else { return false }
        var template = PageTemplate(paper: page.paper, appearance: page.appearance ?? PaperAppearance())
        template.pdfFile = file; template.pdfIndex = index; template.sourceWidth = page.width; template.sourceHeight = page.height
        do { try await workspace.setDefaultPageTemplate(template); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    /// Keep page selection and Pencil input locked for the entire import, not
    /// only its last load. The continuous viewport must not rebase mid-import.
    func importPages(from url: URL, native: Bool = false) async {
        guard hasLease, !navigating, !loading, !hasActiveStroke else { return }
        navigating = true
        let interactive = canvas.isUserInteractionEnabled; canvas.isUserInteractionEnabled = false
        defer { navigating = false; canvas.isUserInteractionEnabled = interactive }
        guard await flush() else { return }
        let before = pages.map(\.id), selected = page?.id
        do {
            if audio?.recording == true { await audio?.pause(reason: "Importazione pagine") }
            let imported: [PageSnapshot]
            if native {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                imported = try await workspace.appendNative(from: url)
            } else { imported = try await DocumentServices.importPDF(from: url, into: workspace) }
            if let first = imported.first { try await load(first) }
        } catch { self.error = error.localizedDescription }
        do {
            pages = try await workspace.pages()
            recordOrder(before, selectedBefore: selected, label: "Importa pagine")
        } catch { self.error = error.localizedDescription }
    }
}
