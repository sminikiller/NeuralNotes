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
    case pages([EditorContentState], [EditorContentState], UUID, UUID)
}

@MainActor
extension EditorViewModel {
    var canUndo: Bool { history.undo != nil }
    var canRedo: Bool { history.redo != nil }

    func captureEdit(ink: Bool = false) -> EditorContentState? {
        page.map { EditorContentState(page: $0, drawing: ink ? canvas.drawing.dataRepresentation() : nil) }
    }

    func recordEdit(_ before: EditorContentState?, label: String) {
        if !applyingHistory, let before, before.page.id == page?.id { settleDiagramReferences(from: before.page) }
        guard !applyingHistory, let before, let after = captureEdit(ink: before.drawing != nil), before != after else { return }
        recognitionNoticeTask?.cancel(); recognitionNotice = nil
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
        guard hasLease, !navigating, !loading, !hasActiveStroke else { return }
        // CanvasHost shields new touches while navigating. Keep the native
        // responder alive so PencilKit can finish its pending drawing callbacks.
        navigating = true; defer { navigating = false }
        guard await settleInkBeforeHistory(),
              let immediate = undo ? history.undo : history.redo else { return }
        // Same-page edits already contain both complete states. Installing one
        // must not wait for a writer, rescan page headers or write two revisions.
        // An in-flight save rebases its revision/file pointers onto this live
        // state; dirty stays set so the normal save loop drains the latest edit.
        if case .content(let before, let after) = immediate.event,
           let current = page, current.id == before.page.id, current.id == after.page.id {
            do {
                let target = undo ? before : after
                let ink = try target.drawing.map { try PKDrawing(data: $0) }
                let preserveWords = scanWordsUnchanged(from: current, to: target.page, drawing: ink)
                applyingHistory = true; defer { applyingHistory = false }
                var restored = target.page
                restored.revision = current.revision; restored.drawingFile = current.drawingFile
                restored.previousDrawingFile = current.previousDrawingFile
                page = restored
                if let ink { replaceInkSession(with: ink) }
                selectedObjectID = nil
                if undo { history.didUndo() } else { history.didRedo() }
                drawingChanged(preservingRecognizedWords: preserveWords)
                status = "\(undo ? "Annullato" : "Ripristinato"): \(immediate.label)"
            } catch { self.error = error.localizedDescription }
            return
        }
        guard await flush(), let entry = undo ? history.undo : history.redo else { return }
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
                if let bytes = target.drawing { replaceInkSession(with: try PKDrawing(data: bytes)) }
                selectedObjectID = nil; drawingChanged()
                guard await flush() else { return }
            case .order(let before, let after, let beforePage, let afterPage):
                let order = undo ? before : after
                try await workspace.restorePageOrder(order, expected: undo ? after : before)
                pages = try await workspace.pages()
                let selected = undo ? beforePage : afterPage
                if let target = pages.first(where: { $0.id == selected }) ?? pages.first { try await load(target) }
            case .pages(let before, let after, let beforeID, let afterID):
                let targets = undo ? before : after
                var changes: [PageMutation] = []
                for target in targets {
                    let latest = try await workspace.pageSnapshot(target.page.id)
                    let bytes: Data
                    if let stored = target.drawing { bytes = stored }
                    else { bytes = try await workspace.drawing(latest) ?? PKDrawing().dataRepresentation() }
                    changes.append(PageMutation(page: target.page, expectedRevision: latest.revision, drawing: bytes))
                }
                try await workspace.applyPageBatch(changes)
                pages = try await workspace.pages()
                if let target = pages.first(where: { $0.id == (undo ? beforeID : afterID) }) { try await load(target) }
            }
            if undo { history.didUndo() } else { history.didRedo() }
            status = "\(undo ? "Annullato" : "Ripristinato"): \(entry.label)"
        } catch { self.error = error.localizedDescription }
    }

    /// Comparing ordinary ink is needed only for a cached scan, once per undo.
    /// A marker-only undo keeps its recognized words; undoing pen/image edits
    /// invalidates them even when the currently selected tool is the marker.
    private func scanWordsUnchanged(from current: PageSnapshot, to restored: PageSnapshot, drawing: PKDrawing?) -> Bool {
        guard PageWordIndex.shared.hasRecognizedScanWords(current), current.pdfFile == restored.pdfFile,
              current.pdfIndex == restored.pdfIndex, current.width == restored.width, current.height == restored.height,
              current.images == restored.images else { return false }
        guard let drawing else { return true }
        let original = PKDrawing(strokes: canvas.drawing.strokes.filter { $0.ink.inkType != .marker })
        let replacement = PKDrawing(strokes: drawing.strokes.filter { $0.ink.inkType != .marker })
        return EditorInkSignatures.make(original) == EditorInkSignatures.make(replacement)
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

    func straightenSelectedImage(_ edit: PhotoAdjustment) {
        guard let id = selectedObjectID, let old = page?.images.first(where: { $0.id == id }),
              edit.perspective?.isConvex != false, (0...3).contains(edit.quarterTurns),
              let source = DocumentRenderCache.shared.image(workspace.package.appendingPathComponent(old.file)),
              let result = PhotoPerspective.render(source, adjustment: edit, maxDimension: 800) else { return }
        let sourceRatio = Double(result.size.height / max(1, result.size.width))
        // Object rotation predates photo adjustments and swaps its bounding box.
        // Keep that transform when correcting a photo that was already rotated.
        let sideways = abs((old.rotation ?? 0).truncatingRemainder(dividingBy: 180)) == 90
        let ratio = sideways ? 1 / sourceRatio : sourceRatio
        mutatePage("Raddrizza e ritaglia immagine") { page in
            guard let i = page.images.firstIndex(where: { $0.id == id }) else { return }
            page.images[i].perspective = edit.perspective; page.images[i].crop = edit.crop
            page.images[i].photoQuarterTurns = edit.quarterTurns; page.images[i].photoEnhanced = edit.enhanced
            page.images[i].height = max(24, page.images[i].width * ratio)
            let maximum = max(24, page.height - 32)
            if page.images[i].height > maximum {
                page.images[i].width *= maximum / page.images[i].height; page.images[i].height = maximum
            }
            page.images[i].y = min(page.images[i].y, max(0, page.height - page.images[i].height))
        }
    }
}
