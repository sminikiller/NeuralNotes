import UIKit
import NeuralNotesCore

struct DiagramLabelEditTarget: Identifiable {
    let pageID: UUID, objectID: UUID
    var id: UUID { objectID }
}

@MainActor
extension EditorViewModel {
    var selectedConnector: ConnectorElement? {
        guard selectedIDs.count == 1, !selectionIncludesInk, let id = selectedObjectID else { return nil }
        return page?.connectors?.first { $0.id == id }
    }
    func editDiagramLabel(_ id: UUID) {
        guard hasLease, !loading, !navigating, !interactionBusy, let page,
              !(page.lockedObjects ?? []).contains(id),
              page.shapes?.contains(where: { $0.id == id }) == true || page.connectors?.contains(where: { $0.id == id }) == true else { return }
        selectedObjectID = id; diagramLabelEditor = .init(pageID: page.id, objectID: id)
    }
    func saveDiagramLabel(_ target: DiagramLabelEditTarget, text: TextElement, autoFit: Bool) {
        guard page?.id == target.pageID, !(page?.lockedObjects ?? []).contains(target.objectID), text.text.count <= 100_000,
              (text.rtf?.count ?? 0) <= 2 * 1024 * 1024 else { return }
        mutatePage("Modifica etichetta") { value in
            if let index = value.shapes?.firstIndex(where: { $0.id == target.objectID }) {
                value.shapes?[index].label = text.text; value.shapes?[index].labelRTF = text.rtf
                value.shapes?[index].labelFontSize = min(200, max(6, text.fontSize)); value.shapes?[index].labelAutoFit = autoFit
            } else if let index = value.connectors?.firstIndex(where: { $0.id == target.objectID }) {
                value.connectors?[index].label = text.text; value.connectors?[index].labelRTF = text.rtf
                value.connectors?[index].labelFontSize = min(200, max(6, text.fontSize))
            }
        }
    }
    func changeConnector(_ connector: ConnectorElement, label: String = "Modifica connettore") {
        guard hasLease, !loading, !navigating, !interactionBusy, connector.isValid,
              page?.connectors?.contains(where: { $0.id == connector.id }) == true,
              !(page?.lockedObjects ?? []).contains(connector.id) else { return }
        mutatePage(label) { value in
            if let index = value.connectors?.firstIndex(where: { $0.id == connector.id }) { value.connectors?[index] = connector }
        }
    }
    func setConnectorRouting(_ routing: ConnectorRouting) {
        guard var connector = selectedConnector else { return }
        connector.routing = routing; connector.controlPoints = nil; changeConnector(connector, label: "Tracciato \(routing.title.lowercased())")
    }
    @discardableResult
    func createDiagramBlock(from id: UUID, side: DiagramSide, at drop: StrokeSample? = nil) -> UUID? {
        guard hasLease, !interactionBusy, !loading, !navigating, let page else { return nil }
        let objects = DiagramObjects.make(page)
        guard let source = objects[id], !source.locked, source.connectionPoints.indices.contains(side.rawValue),
              page.shapes?.contains(where: { $0.id == id }) == true || page.texts.contains(where: { $0.id == id }) else { return nil }
        let box = source.bounds
        let pageBox = SnapRect(x: 0, y: 0, width: page.width, height: page.height)
        let obstacles = objects.values.map(\.bounds)
        let destination: SnapRect?
        if let drop { destination = QuickDiagramLayout.atDrop(drop, size: box, page: pageBox, obstacles: obstacles) }
        else {
            let p = source.connectionPoints[side.rawValue]
            let direction = StrokeSample(x: p.x - source.rect.midX, y: p.y - source.rect.midY)
            destination = QuickDiagramLayout.duplicate(box, direction: direction, page: pageBox, obstacles: obstacles)
        }
        guard let destination else { status = "Non c’è spazio per un nuovo blocco in questa zona."; return nil }
        let dx = destination.x - box.x, dy = destination.y - box.y
        var changed = page
        let newID: UUID
        if var shape = page.shapes?.first(where: { $0.id == id }) {
            shape.id = UUID(); shape.x += dx; shape.y += dy; shape.audioAnchor = newDiagramAnchor(id: shape.id, prefix: "shape")
            newID = shape.id; var shapes = changed.shapes ?? []; shapes.append(shape); changed.shapes = shapes
        } else if var text = page.texts.first(where: { $0.id == id }) {
            text.id = UUID(); text.x += dx; text.y += dy; newID = text.id; changed.texts.append(text)
        } else { return nil }
        let updatedObjects = DiagramObjects.make(changed)
        guard let target = updatedObjects[newID], source.connectionPoints.indices.contains(side.rawValue),
              let end = target.closest(source.connectionPoints[side.rawValue], zoom: canvas.zoomScale, magnet: true) else { return nil }
        var connector = ConnectorElement(from: source.end(at: source.connectionPoints[side.rawValue]), to: end)
        connector.audioAnchor = newDiagramAnchor(id: connector.id, prefix: "connector")
        var edges = changed.connectors ?? []; edges.append(connector); changed.connectors = edges
        changed.objectOrder = [connector.id] + page.orderedObjectIDs + [newID]
        let before = captureEdit(); self.page = changed
        refreshDiagramFallbacks(); recordEdit(before, label: "Crea blocco collegato"); drawingChanged()
        selectedObjectID = newID; return newID
    }
    func addDiagramConnector(_ connector: ConnectorElement) {
        guard hasLease, !loading, !navigating, !interactionBusy, let page, connector.isValid,
              !page.objectIDs.contains(connector.id) else { return }
        var value = connector; value.audioAnchor = newDiagramAnchor(id: value.id, prefix: "connector")
        mutatePage("Crea connettore") { page in
            let order = page.orderedObjectIDs
            var edges = page.connectors ?? []; edges.append(value); page.connectors = edges; page.objectOrder = [value.id] + order
        }; selectedObjectID = value.id
    }
    func refreshDiagramFallbacks() {
        guard var value = page, value.connectors?.isEmpty == false else { return }
        let objects = DiagramObjects.make(value)
        value.refreshConnectorFallbacks(objects: objects); value.detachMissingConnectorTargets(); page = value
    }
    func settleDiagramReferences(from before: PageSnapshot) {
        guard var value = page, value.connectors?.isEmpty == false else { return }
        let targets = value.connectorTargetIDs, oldObjects = DiagramObjects.make(before)
        let oldEdges = Dictionary((before.connectors ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var edges = value.connectors ?? []
        for i in edges.indices {
            guard let old = oldEdges[edges[i].id] else { continue }
            if let id = old.from.objectID, !targets.contains(id), edges[i].from.objectID == nil || edges[i].from.objectID == id {
                let p = ConnectorGeometry.resolve(old.from, objects: oldObjects)
                edges[i].from = .init(x: p.x, y: p.y)
            }
            if let id = old.to.objectID, !targets.contains(id), edges[i].to.objectID == nil || edges[i].to.objectID == id {
                let p = ConnectorGeometry.resolve(old.to, objects: oldObjects)
                edges[i].to = .init(x: p.x, y: p.y)
            }
        }
        value.connectors = edges
        let objects = DiagramObjects.make(value)
        value.refreshConnectorFallbacks(objects: objects); value.detachMissingConnectorTargets(); page = value
    }
    func newDiagramAnchor(id: UUID, prefix: String) -> StrokeAnchor? {
        guard let (session, seconds) = audio?.recordingAnchor else { return nil }
        return StrokeAnchor(signature: "\(prefix):\(id)", audioSessionID: session, seconds: seconds)
    }
}
