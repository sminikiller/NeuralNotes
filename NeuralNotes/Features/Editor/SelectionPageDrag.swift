import UIKit
import UniformTypeIdentifiers
import NeuralNotesCore

struct SelectionPageDragPayload: Codable, Equatable, Sendable {
    static let type = UTType(exportedAs: "com.lorenzominichilli.neuralnotes.selection-drag", conformingTo: .data)
    let ticket: UUID, documentID: UUID, pageID: UUID, owner: UUID, generation: UUID
    let expires: Double
}
struct SelectionPageDragRecord {
    let payload: SelectionPageDragPayload
    let objects: Set<UUID>, includesInk: Bool, strokeIndices: Set<Int>?
}
enum SelectionPageDragFailure: LocalizedError {
    case stale, incomplete
    var errorDescription: String? {
        switch self {
        case .stale: return "La selezione è cambiata o il trascinamento è scaduto. Riseleziona gli elementi e trascinali di nuovo."
        case .incomplete: return "Il trasferimento non è stato completato."
        }
    }
}

@MainActor
extension EditorViewModel {
    func makeSelectionPageDrag() -> SelectionPageDragPayload? {
        finishInkGesture(); endTextEdit()
        guard selectionPageDragMode, hasLease, !loading, !navigating, !hasActiveStroke, !selectionDropPending,
              tool == .objects || tool == .lasso, let page,
              !selectedIDs.subtracting(page.lockedObjects ?? []).isEmpty || selectionIncludesInk,
              !selectionBounds.isNull, !selectionBounds.isEmpty else { return nil }
        let payload = SelectionPageDragPayload(ticket: UUID(), documentID: workspace.documentID, pageID: page.id,
            owner: selectionDragOwner, generation: inkDisplayGeneration, expires: Date().timeIntervalSince1970 + 60)
        activeSelectionPageDrag = .init(payload: payload, objects: selectedIDs, includesInk: selectionIncludesInk, strokeIndices: selectedStrokeIndices)
        return payload
    }
    func receiveSelectionPageDrop(_ providers: [NSItemProvider], to destination: UUID) -> Bool {
        guard selectionPageDragMode, !selectionDropPending, destination != page?.id,
              let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(SelectionPageDragPayload.type.identifier) }) else { return false }
        selectionDropPending = true
        let copy = selectionDragCopy
        Task {
            defer { selectionDropPending = false }
            do {
                let data: Data = try await withCheckedThrowingContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: SelectionPageDragPayload.type.identifier) { data, error in
                        if let error { continuation.resume(throwing: error) }
                        else if let data { continuation.resume(returning: data) }
                        else { continuation.resume(throwing: SelectionPageDragFailure.stale) }
                    }
                }
                try await completeSelectionPageDrop(data, to: destination, copy: copy)
            } catch { activeSelectionPageDrag = nil; if self.error == nil { self.error = error.localizedDescription } }
        }
        return true
    }
    func completeSelectionPageDrop(_ data: Data, to destination: UUID, copy: Bool) async throws {
        defer { activeSelectionPageDrag = nil }
        guard data.count <= 4096, let payload = try? JSONDecoder().decode(SelectionPageDragPayload.self, from: data),
              let record = activeSelectionPageDrag, payload == record.payload,
              selectionPageDragMode, hasLease, !loading, !navigating, !hasActiveStroke,
              payload.documentID == workspace.documentID, payload.owner == selectionDragOwner,
              payload.pageID == page?.id, payload.generation == inkDisplayGeneration,
              payload.expires.isFinite, payload.expires >= Date().timeIntervalSince1970,
              record.objects == selectedIDs, record.includesInk == selectionIncludesInk, record.strokeIndices == selectedStrokeIndices,
              destination != payload.pageID, pages.contains(where: { $0.id == destination }),
              tool == .objects || tool == .lasso else { throw SelectionPageDragFailure.stale }
        await transferSelection(to: destination, copy: copy)
        guard page?.id == destination else { throw SelectionPageDragFailure.incomplete }
        selectionPageDragMode = false
    }
}

@MainActor
final class SelectionPageDragController: NSObject, UIDragInteractionDelegate {
    private weak var host: CanvasHost?
    private weak var model: EditorViewModel?
    init(host: CanvasHost, model: EditorViewModel) {
        self.host = host; self.model = model; super.init()
        let interaction = UIDragInteraction(delegate: self); interaction.isEnabled = true; host.addInteraction(interaction)
    }
    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        guard let host, let model, model.selectionBounds.contains(session.location(in: host.surface)),
              let payload = model.makeSelectionPageDrag(), let data = try? JSONEncoder().encode(payload) else { return [] }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: SelectionPageDragPayload.type.identifier, visibility: .ownProcess) { completion in completion(data, nil); return nil }
        let item = UIDragItem(itemProvider: provider); item.localObject = payload
        if let image = try? model.selectionImage() {
            let preview = UIImageView(image: image), factor = min(1, 240 / max(image.size.width, image.size.height))
            preview.frame = CGRect(origin: .zero, size: CGSize(width: image.size.width * factor, height: image.size.height * factor))
            let parameters = UIDragPreviewParameters(); parameters.backgroundColor = .clear
            item.previewProvider = { UIDragPreview(view: preview, parameters: parameters) }
        }
        return [item]
    }
    func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }
}
