import UIKit
import NeuralNotesCore

@MainActor
final class DiagramHandleSession {
    weak var overlay: DiagramHandlesOverlay?
    let handle: DiagramHandle
    let pageID: UUID
    let sourceID: UUID
    let objects: [UUID: ConnectorObject]
    let index: ConnectorTargetIndex
    let original: ConnectorElement
    var draft: ConnectorElement
    var lastPoint = StrokeSample(x: 0, y: 0)
    var targetID: UUID?
    var freeEnd = false
    var heldFree = false
    private var hold: Task<Void, Never>?
    var isCreating: Bool { if case .create = handle { return true }; return false }
    init?(overlay: DiagramHandlesOverlay, handle: DiagramHandle) {
        guard let model = overlay.model, let page = model.page, let selected = model.selectedObjectID else { return nil }
        let objectMap = DiagramObjects.make(page)
        var boxes: [UUID: SnapRect] = [:]
        for (id, object) in objectMap where !object.locked { boxes[id] = object.bounds }
        let connector: ConnectorElement
        if case .create(let side) = handle {
            guard let source = objectMap[selected], source.connectionPoints.indices.contains(side.rawValue) else { return nil }
            let p = source.connectionPoints[side.rawValue]
            connector = ConnectorElement(from: source.end(at: p), to: .init(x: p.x, y: p.y))
        } else {
            guard let value = model.selectedConnector else { return nil }; connector = value
        }
        self.overlay = overlay; self.handle = handle; pageID = page.id; sourceID = selected
        objects = objectMap; index = ConnectorTargetIndex(boxes: boxes, order: page.orderedObjectIDs)
        original = connector; draft = connector
        lastPoint = ConnectorGeometry.resolve(handle == .from ? connector.from : connector.to, objects: objectMap)
        if !isCreating, let host = overlay.host {
            host.surface.interactionHiddenObjectIDs.insert(original.id); host.paperDetail.update(from: host); host.foregroundObjects.update(host)
        }
    }
    func move(_ point: StrokeSample, suspended: Bool) {
        guard let overlay, let host = overlay.host, overlay.model?.page?.id == pageID else { return }
        let moved = hypot(point.x - lastPoint.x, point.y - lastPoint.y) > 3 / max(0.05, host.canvas.zoomScale)
        lastPoint = point
        if handle == .bend {
            targetID = nil; freeEnd = false
            if original.routing == .elbow { draft.controlPoints = [point] }
            else {
                var value = original; value.routing = .curved
                let center = ConnectorGeometry.midpoint(value, objects: objects), dx = point.x - center.x, dy = point.y - center.y
                if let command = ConnectorGeometry.path(value, objects: objects).commands.last, case .cubic(let a, let b, _) = command {
                    draft.routing = .curved; draft.controlPoints = [.init(x: a.x + dx, y: a.y + dy), .init(x: b.x + dx, y: b.y + dy)]
                }
            }; return
        }
        if moved {
            hold?.cancel(); heldFree = false
            hold = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
                guard let self, let owner = self.overlay, owner.session === self else { return }
                self.heldFree = true; self.freeEnd = true; self.targetID = nil; self.installEnd(.init(x: self.lastPoint.x, y: self.lastPoint.y))
                owner.update(); UIAccessibility.post(notification: .announcement, argument: "Estremo libero")
            }
        }
        freeEnd = heldFree || suspended
        let target = freeEnd ? nil : target(at: point, zoom: host.canvas.zoomScale)
        targetID = target?.objectID
        installEnd(target ?? .init(x: point.x, y: point.y))
    }
    private func installEnd(_ end: ConnectorEnd) {
        if handle == .from { draft.from = end } else { draft.to = end }
    }
    private func target(at point: StrokeSample, zoom: Double) -> ConnectorEnd? {
        for id in index.candidates(at: point, zoom: zoom) {
            guard let object = objects[id], !object.locked else { continue }
            let outline = object.outline
            guard outline.count >= 2 else { continue }
            let inside = ShapeGeometry.contains(point, polygon: outline)
            var close = false
            for i in 1..<outline.count where ShapeGeometry.segmentDistance(point, outline[i - 1], outline[i]) <= 12 / max(0.05, zoom) { close = true; break }
            if inside || close { return object.closest(point, zoom: zoom, magnet: overlay?.model?.snapPreferences.objectsEnabled ?? true) }
        }
        return nil
    }
    func finish() {
        guard let overlay, let model = overlay.model, model.page?.id == pageID else { self.overlay?.cancel(); return }
        let value = draft, target = targetID, free = freeEnd, at = lastPoint
        overlay.cancel()
        if case .create(let side) = handle {
            if free || target != nil { model.addDiagramConnector(value) }
            else { _ = model.createDiagramBlock(from: sourceID, side: side, at: at) }
        } else { model.changeConnector(value) }
        overlay.host?.synchronizePage()
    }
    func cancel() { hold?.cancel(); hold = nil }
}
