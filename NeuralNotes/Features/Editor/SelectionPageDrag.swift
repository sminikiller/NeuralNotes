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
final class SelectionPageDragController: NSObject {
    private weak var host: CanvasHost?
    private weak var model: EditorViewModel?
    private let source = UIView()
    private var ticket: Data?
    private var lift: UIView?
    private var touchOrigin = CGPoint.zero
    init(host: CanvasHost, model: EditorViewModel) {
        self.host = host; self.model = model; super.init()
        source.backgroundColor = .clear; source.isOpaque = false; source.isHidden = true
        source.isAccessibilityElement = true; source.accessibilityIdentifier = "selectionDragSource"
        source.accessibilityLabel = "Selezione da trascinare"
        source.accessibilityHint = "Tieni premuto e trascina su una miniatura. Puoi anche toccare direttamente la destinazione."
        // PencilKit has its own drag interaction. A source above the selected
        // area receives this deliberate gesture without competing with it.
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(trackSelection(_:)))
        hold.minimumPressDuration = 0.28
        source.addGestureRecognizer(hold); host.addSubview(source)
    }
    func update() {
        guard let host, let model, model.selectionPageDragMode, !model.loading, !model.navigating,
              !model.selectionDropPending, model.hasLease, !model.selectionBounds.isNull, !model.selectionBounds.isEmpty else {
            source.isHidden = true; return
        }
        source.frame = host.surface.convert(model.selectionBounds, to: host)
        source.isHidden = false; host.bringSubviewToFront(source)
    }
    @objc private func trackSelection(_ gesture: UILongPressGestureRecognizer) {
        guard let host, let model, let window = source.window else { return }
        let point = gesture.location(in: window)
        switch gesture.state {
        case .began:
            guard let payload = model.makeSelectionPageDrag() else { return }
            ticket = try? JSONEncoder().encode(payload)
            touchOrigin = point
            let visible = source.frame.intersection(host.bounds)
            if !visible.isEmpty, let picture = host.resizableSnapshotView(from: visible, afterScreenUpdates: false, withCapInsets: .zero) {
                picture.frame = host.convert(visible, to: window)
                picture.alpha = 0.75; picture.isUserInteractionEnabled = false
                window.addSubview(picture); lift = picture
            }
        case .changed:
            lift?.transform = CGAffineTransform(translationX: point.x - touchOrigin.x, y: point.y - touchOrigin.y)
        case .ended:
            lift?.removeFromSuperview(); lift = nil
            let data = ticket; ticket = nil
            guard let data, !model.selectionDropPending,
                  let target = model.pages.first(where: { page in
                      guard page.id != model.page?.id, let view = model.pageDropTargets.object(forKey: page.id as NSUUID),
                            view.window === window, view.bounds.contains(view.convert(point, from: window)) else { return false }
                      var parent = view.superview
                      while let node = parent {
                          if node.isHidden || (node.clipsToBounds && !node.bounds.contains(node.convert(point, from: window))) { return false }
                          parent = node.superview
                      }
                      return true
                  }) else { model.activeSelectionPageDrag = nil; return }
            model.selectionDropPending = true
            let copy = model.selectionDragCopy
            Task {
                defer { model.selectionDropPending = false }
                do { try await model.completeSelectionPageDrop(data, to: target.id, copy: copy) }
                catch { if model.error == nil { model.error = error.localizedDescription } }
            }
        case .cancelled, .failed:
            lift?.removeFromSuperview(); lift = nil; ticket = nil; model.activeSelectionPageDrag = nil
        default: break
        }
    }
}
