import SwiftUI
import PencilKit
import NeuralNotesCore

struct EditorContentState: Equatable {
    var page: PageSnapshot
    var drawing: Data?
    var normalized: PageSnapshot {
        var copy = page; copy.revision = 0; copy.drawingFile = nil; copy.previousDrawingFile = nil; copy.lastEditedAt = nil; return copy
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.normalized == rhs.normalized && lhs.drawing == rhs.drawing }
}

enum EditorEdit {
    case content(EditorContentState, EditorContentState)
    case order([UUID], [UUID], UUID?, UUID?)
}

@MainActor
extension EditorViewModel {
    var canUndo: Bool { history.undo != nil }
    var canRedo: Bool { history.redo != nil }

    func captureEdit(ink: Bool = false) -> EditorContentState? {
        page.map { EditorContentState(page: $0, drawing: ink ? canvas.drawing.dataRepresentation() : nil) }
    }

    func recordEdit(_ before: EditorContentState?, label: String) {
        guard !applyingHistory, let before, let after = captureEdit(ink: before.drawing != nil), before != after else { return }
        let metadata = (try? JSONEncoder().encode(before.page).count) ?? 0
        history.record(.content(before, after), label: label,
            cost: (before.drawing?.count ?? 0) + (after.drawing?.count ?? 0) + metadata * 2)
    }

    func mutatePage(_ label: String, _ action: (inout PageSnapshot) -> Void) {
        finishInkGesture()
        commitTextEdit()
        guard hasLease, !navigating, !loading, !hasActiveStroke, var value = page else { return }
        let before = captureEdit()
        action(&value); value.pruneObjectReferences(); page = value; recordEdit(before, label: label); drawingChanged()
    }

    func recordOrder(_ before: [UUID], selectedBefore: UUID?, label: String) {
        let after = pages.map(\.id)
        if before != after { history.record(.order(before, after, selectedBefore, page?.id), label: label) }
    }

    func performUndo() async { await applyHistory(undo: true) }
    func performRedo() async { await applyHistory(undo: false) }

    private func applyHistory(undo: Bool) async {
        finishInkGesture(); endTextEdit()
        guard hasLease, !navigating, !loading, !hasActiveStroke, let entry = undo ? history.undo : history.redo else { return }
        navigating = true; defer { navigating = false }
        guard await flush() else { return }
        applyingHistory = true; defer { applyingHistory = false }
        do {
            switch entry.event {
            case .content(let before, let after):
                let target = undo ? before : after
                let latest = try await workspace.pages()
                guard let stored = latest.first(where: { $0.id == target.page.id }) else { throw LibraryFailure.missingItem }
                if page?.id != stored.id { try await load(stored) }
                var restored = target.page
                restored.revision = stored.revision; restored.drawingFile = stored.drawingFile
                restored.previousDrawingFile = stored.previousDrawingFile
                page = restored
                if let bytes = target.drawing { canvas.drawing = try PKDrawing(data: bytes) }
                selectedObjectID = nil; drawingChanged()
                guard await flush() else { return }
            case .order(let before, let after, let beforePage, let afterPage):
                let order = undo ? before : after
                try await workspace.restorePageOrder(order, expected: undo ? after : before)
                pages = try await workspace.pages()
                let selected = undo ? beforePage : afterPage
                if let target = pages.first(where: { $0.id == selected }) ?? pages.first { try await load(target) }
            }
            if undo { history.didUndo() } else { history.didRedo() }
            status = "\(undo ? "Annullato" : "Ripristinato"): \(entry.label)"
        } catch { self.error = error.localizedDescription }
    }

    func reorder(_ ids: [UUID]) async {
        guard hasLease, !navigating, !loading, !hasActiveStroke else { return }
        navigating = true; defer { navigating = false }
        guard await flush() else { return }
        let before = pages.map(\.id), selected = page?.id
        do {
            try await workspace.reorderPages(ids); pages = try await workspace.pages()
            recordOrder(before, selectedBefore: selected, label: "Riordina pagine")
        } catch { self.error = error.localizedDescription }
    }

    func addText() {
        guard hasLease, !loading, !navigating, !hasActiveStroke else { return }
        let text = TextElement(text: "Nuovo testo")
        mutatePage("Aggiungi testo") { $0.texts.append(text) }; selectedObjectID = text.id; tool = .objects
    }
    func addImage(_ image: ImageElement) {
        guard hasLease, !loading, !navigating, !hasActiveStroke else { return }
        mutatePage("Inserisci immagine") { $0.images.append(image) }; selectedObjectID = image.id; tool = .objects
    }
    func addShape(_ kind: ShapeKind) {
        guard hasLease, !loading, !navigating, !hasActiveStroke else { return }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        PaperInk.color(ink).getRed(&r, green: &g, blue: &b, alpha: &a)
        let shape = ShapeElement(kind: kind, red: Double(r), green: Double(g), blue: Double(b), lineWidth: thickness)
        mutatePage("Inserisci \(kind.title)") { $0.shapes = ($0.shapes ?? []) + [shape] }
        selectedObjectID = shape.id; tool = .objects
    }
    func cropSelectedImage(_ crop: NormalizedCrop) {
        guard let id = selectedObjectID else { return }
        mutatePage("Ritaglia immagine") { page in
            guard let i = page.images.firstIndex(where: { $0.id == id }) else { return }
            let old = page.images[i].crop ?? .full
            let sideways = abs((page.images[i].rotation ?? 0).truncatingRemainder(dividingBy: 180)) == 90
            let factor = sideways ? crop.width / old.width * old.height / crop.height : crop.height / old.height * old.width / crop.width
            page.images[i].height = max(24, page.images[i].height * factor)
            let maximum = max(24, page.height - 32)
            if page.images[i].height > maximum {
                page.images[i].width *= maximum / page.images[i].height; page.images[i].height = maximum
            }
            page.images[i].y = min(page.images[i].y, max(0, page.height - page.images[i].height))
            page.images[i].crop = crop
        }
    }
}
