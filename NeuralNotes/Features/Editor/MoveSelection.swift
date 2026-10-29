import SwiftUI
import PencilKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    func moveSelection(to pageID: UUID) async {
        finishInkGesture(); endTextEdit()
        guard hasLease, !navigating, !loading, !hasActiveStroke, let origin = page, pageID != origin.id else { return }
        let ids = origin.includingInternalConnectors(selectedIDs.subtracting(origin.lockedObjects ?? []))
        let selectedInk = selectionIncludesInk ? Set(selectedStrokeIndices ?? Set(canvas.drawing.strokes.indices)) : []
        guard !ids.isEmpty || !selectedInk.isEmpty else { return }
        selectedIDs = ids
        let bounds = selectionBounds
        guard !bounds.isNull, !bounds.isEmpty, [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite) else { return }
        navigating = true
        let interactive = canvas.isUserInteractionEnabled; canvas.isUserInteractionEnabled = false
        defer { navigating = false; canvas.isUserInteractionEnabled = interactive }
        guard await flush(), var source = page else { return }
        do {
            var destination = try await workspace.pageSnapshot(pageID)
            let destinationBytes = try await workspace.drawing(destination)
            let originalInk = canvas.drawing, destinationInk = try destinationBytes.map { try PKDrawing(data: $0) } ?? PKDrawing()
            let sourceObjects = DiagramObjects.make(source)
            source.refreshConnectorFallbacks(objects: sourceObjects)
            let before = [EditorContentState(page: source, drawing: originalInk.dataRepresentation()), EditorContentState(page: destination, drawing: destinationInk.dataRepresentation())]
            let mx: CGFloat = min(24, CGFloat(destination.width) * 0.05), my: CGFloat = min(24, CGFloat(destination.height) * 0.05)
            let scale: CGFloat = min(1, (CGFloat(destination.width) - mx * 2) / bounds.width, (CGFloat(destination.height) - my * 2) / bounds.height)
            guard scale >= 0.05 else { throw WorkspaceFailure.oversizedImport }
            let transform = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(CGAffineTransform(translationX: mx, y: my))
            var moving = source.selectingObjects(ids, objects: sourceObjects)
            moving.renewObjectIDs()
            for i in moving.texts.indices {
                let value = moving.texts[i], point = CGPoint(x: value.x, y: value.y).applying(transform)
                moving.texts[i].x = point.x; moving.texts[i].y = point.y; moving.texts[i].width *= Double(scale)
                moving.texts[i].fontSize = max(1, value.fontSize * Double(scale))
                if scale != 1 {
                    let rich = NSMutableAttributedString(attributedString: RichText.attributed(value))
                    rich.enumerateAttribute(.font, in: NSRange(location: 0, length: rich.length)) { font, range, _ in
                        if let font = font as? UIFont { rich.addAttribute(.font, value: font.withSize(max(1, font.pointSize * scale)), range: range) }
                    }; moving.texts[i].rtf = RichText.data(rich)
                }
            }
            for i in moving.images.indices {
                let point = CGPoint(x: moving.images[i].x, y: moving.images[i].y).applying(transform)
                moving.images[i].x = point.x; moving.images[i].y = point.y; moving.images[i].width *= Double(scale); moving.images[i].height *= Double(scale)
            }
            if var shapes = moving.shapes {
                for i in shapes.indices {
                    let point = CGPoint(x: shapes[i].x, y: shapes[i].y).applying(transform)
                    shapes[i].x = point.x; shapes[i].y = point.y; shapes[i].width *= Double(scale); shapes[i].height *= Double(scale); shapes[i].lineWidth *= Double(scale)
                }; moving.shapes = shapes
            }
            if var tapes = moving.tapes {
                for i in tapes.indices {
                    let point = CGPoint(x: tapes[i].x, y: tapes[i].y).applying(transform)
                    tapes[i].x = point.x; tapes[i].y = point.y; tapes[i].width *= Double(scale); tapes[i].height *= Double(scale)
                }; moving.tapes = tapes
            }
            moving.connectors = moving.connectors?.map { edge in
                edge.transformed(scale: Double(scale), dx: Double(mx - bounds.minX * scale), dy: Double(my - bounds.minY * scale))
            }
            source.texts.removeAll { ids.contains($0.id) }; source.images.removeAll { ids.contains($0.id) }
            source.shapes?.removeAll { ids.contains($0.id) }; source.tapes?.removeAll { ids.contains($0.id) }; source.pruneObjectReferences()
            source.connectors?.removeAll { ids.contains($0.id) }; source.pruneObjectReferences()
            destination.texts += moving.texts; destination.images += moving.images
            destination.shapes = (destination.shapes ?? []) + (moving.shapes ?? [])
            destination.tapes = (destination.tapes ?? []) + (moving.tapes ?? [])
            destination.connectors = (destination.connectors ?? []) + (moving.connectors ?? [])
            destination.objectOrder = destination.orderedObjectIDs.filter { !moving.objectIDs.contains($0) } + moving.orderedObjectIDs
            destination.aboveInkObjects = (destination.aboveInkObjects ?? []) + (moving.aboveInkObjects ?? [])
            let keptIndices = originalInk.strokes.indices.filter { !selectedInk.contains($0) }
            let movedIndices = originalInk.strokes.indices.filter { selectedInk.contains($0) }
            let remaining = PKDrawing(strokes: keptIndices.map { originalInk.strokes[$0] })
            let appended = PKDrawing(strokes: destinationInk.strokes + movedIndices.map { i in
                let stroke = originalInk.strokes[i]
                return PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform.concatenating(transform), mask: stroke.mask)
            })
            let oldSignatures = EditorInkSignatures.make(originalInk), keptSignatures = EditorInkSignatures.make(remaining), appendedSignatures = EditorInkSignatures.make(appended)
            let anchors = Dictionary(grouping: source.anchors, by: \.signature)
            source.anchors = keptIndices.enumerated().flatMap { offset, oldIndex in
                (anchors[oldSignatures[oldIndex]] ?? []).map { anchor in var value = anchor; value.signature = keptSignatures[offset]; return value }
            }
            for (offset, oldIndex) in movedIndices.enumerated() {
                destination.anchors += (anchors[oldSignatures[oldIndex]] ?? []).map { anchor in
                    StrokeAnchor(signature: appendedSignatures[destinationInk.strokes.count + offset], audioSessionID: anchor.audioSessionID, seconds: anchor.seconds)
                }
            }
            let after = [EditorContentState(page: source, drawing: remaining.dataRepresentation()), EditorContentState(page: destination, drawing: appended.dataRepresentation())]
            let cost = (before + after).reduce(0) { $0 + ($1.drawing?.count ?? 0) + ((try? JSONEncoder().encode($1.page).count) ?? 0) }
            guard cost <= 48 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
            try await workspace.applyPageBatch(after.map { PageMutation(page: $0.page, expectedRevision: $0.page.revision, drawing: $0.drawing!) })
            history.record(.pages(before, after, source.id, destination.id), label: "Sposta selezione tra pagine", cost: cost)
            pages = try await workspace.pages()
            if let target = pages.first(where: { $0.id == pageID }) { try await load(target) }
            selectedIDs = Set(moving.objectIDs); selectionIncludesInk = false; selectedStrokeIndices = nil
            scheduleMaintenance()
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor
enum EditorInkSignatures {
    static func make(_ drawing: PKDrawing) -> [String] {
        var occurrences: [String: Int] = [:]
        return drawing.strokes.map { stroke in
            let base = String(stroke.path.creationDate.timeIntervalSince1970), count = occurrences[base, default: 0]
            occurrences[base] = count + 1; return "\(base):\(count)"
        }
    }
}

@MainActor
struct MoveSelectionMenu: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        Menu {
            ForEach(Array(model.pages.enumerated()).filter { $0.element.id != model.page?.id }, id: \.element.id) { row in
                Button(row.element.title.map { "\(row.offset + 1) · \($0)" } ?? "Pagina \(row.offset + 1)") { Task { await model.moveSelection(to: row.element.id) } }
            }
        } label: { Label("Sposta in un’altra pagina", systemImage: "doc.on.doc") }
        .disabled(model.pages.count < 2 || (model.selectedIDs.isEmpty && !model.selectionIncludesInk))
    }
}
