import Foundation
import UIKit
import PencilKit
import NeuralNotesCore

/// Kept internal until rendering and every editing tool use the same owner
/// scope. Metadata and immutable vectors travel through the existing journal;
/// no array of sixteen PKDrawing archives is retained in the editor history.
enum EditorLayerOperation {
    case add(String), duplicate(UUID, String), rename(UUID, String)
    case visibility(UUID, Bool), lock(UUID, Bool), opacity(UUID, Double)
    case order([UUID]), clear(UUID), remove(UUID), merge(UUID)

    var title: String {
        switch self {
        case .add: return "Nuovo livello"
        case .duplicate: return "Duplica livello"
        case .rename: return "Rinomina livello"
        case .visibility: return "Visibilità livello"
        case .lock: return "Blocco livello"
        case .opacity: return "Opacità livello"
        case .order: return "Ordine livelli"
        case .clear: return "Svuota livello"
        case .remove: return "Elimina livello"
        case .merge: return "Unisci livelli"
        }
    }
}

@MainActor
extension EditorViewModel {
    @discardableResult
    func performLayerOperation(_ operation: EditorLayerOperation) async -> Bool {
        guard hasLease, !loading, !navigating, !hasActiveStroke else { return false }
        navigating = true; defer { navigating = false }
        closeZoomWriting()
        (pagePresenter as? CanvasHost)?.textInput?.view.resignFirstResponder()
        endTextEdit()
        (pagePresenter as? CanvasHost)?.textInput?.refresh()
        guard await flush(), let current = page else { return false }
        do {
            let previousOwner = drawingLayerID ?? current.id
            var owner = previousOwner
            let next: PageSnapshot
            switch operation {
            case .add(let name):
                let result = try PageLayerEditing.adding(to: current, name: name)
                next = result.page; owner = result.layerID
            case .duplicate(let id, let name):
                let result = try await workspace.prepareLayerDuplicate(pageID: current.id, layerID: id, name: name)
                guard result.page.revision == current.revision else { throw WorkspaceFailure.staleRevision }
                next = result.page; owner = result.layerID
            case .rename(let id, let name): next = try PageLayerEditing.renaming(id, to: name, in: current)
            case .visibility(let id, let visible): next = try PageLayerEditing.visibility(id, visible: visible, in: current)
            case .lock(let id, let locked): next = try PageLayerEditing.lock(id, locked: locked, in: current)
            case .opacity(let id, let value): next = try PageLayerEditing.opacity(id, value: value, in: current)
            case .order(let ids): next = try PageLayerEditing.reordering(ids, in: current)
            case .clear(let id): next = try PageLayerEditing.clearing(id, in: current)
            case .remove(let id): next = try PageLayerEditing.removing(id, in: current)
            case .merge(let id):
                let layers = PageLayers.ordered(in: current)
                guard let index = layers.firstIndex(where: { $0.id == id }), index > 0 else { throw LayerMergeFailure.bottom }
                let targetID = layers[index - 1].id
                let target = try await LayerDrawingReader.read(page: current, layerID: targetID, workspace: workspace)
                let source = try await LayerDrawingReader.read(page: current, layerID: id, workspace: workspace)
                let merged = PKDrawing(strokes: target.drawing.strokes + source.drawing.strokes)
                let plan = try LayerMergePlan.make(page: current, sourceID: id, targetStrokes: EditorInkSignatures.make(target.drawing),
                    sourceStrokes: EditorInkSignatures.make(source.drawing), mergedStrokes: EditorInkSignatures.make(merged))
                next = try await workspace.preparingLayerDrawing(merged.dataRepresentation(), in: plan.page,
                    layerID: targetID, recoveredFromPrevious: target.recoveredFromPrevious)
                owner = targetID
            }
            guard next != current else { return true }
            if !PageLayers.editable(owner, page: next) {
                owner = PageLayers.ordered(in: next).first(where: { PageLayers.editable($0.id, page: next) })?.id ?? next.id
            }
            let order = try await workspace.manifest().pageIDs
            let before = try PageEditSnapshotBuilder(documentID: workspace.documentID, preservingBaseReferences: true)
            let after = try PageEditSnapshotBuilder(documentID: workspace.documentID, preservingBaseReferences: true)
            try await before.append(current, drawing: nil, sourcePackage: workspace.package)
            try await after.append(next, drawing: nil, sourcePackage: workspace.package)
            let oldState = try await before.finish(), newState = try await after.finish()
            let change = EditorDiskChange(before: oldState, after: newState, beforeOrder: order,
                afterOrder: order, beforePage: current.id, afterPage: current.id,
                beforeLayerID: previousOwner, afterLayerID: owner)
            try Task.checkCancellation()
            try await applyDiskChange(change, label: operation.title)
            status = "\(operation.title) · Annulla per ripristinare"
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
