import Foundation

public extension PageSnapshot {
    var connectorTargetIDs: Set<UUID> {
        var ids = Set(texts.map(\.id)); ids.formUnion(images.map(\.id)); ids.formUnion((shapes ?? []).map(\.id)); return ids
    }
    mutating func detachMissingConnectorTargets() {
        let valid = connectorTargetIDs
        guard var values = connectors else { return }
        for i in values.indices {
            if let id = values[i].from.objectID, !valid.contains(id) { values[i].from.objectID = nil }
            if let id = values[i].to.objectID, !valid.contains(id) { values[i].to.objectID = nil }
        }; connectors = values
    }
    mutating func refreshConnectorFallbacks(objects: [UUID: ConnectorObject]) {
        guard var values = connectors else { return }
        for i in values.indices {
            let a = ConnectorGeometry.resolve(values[i].from, objects: objects), b = ConnectorGeometry.resolve(values[i].to, objects: objects)
            values[i].from.x = a.x; values[i].from.y = a.y; values[i].to.x = b.x; values[i].to.y = b.y
        }; connectors = values
    }
    /// Core-only callers may override these rectangles with native text metrics.
    func connectorObjects(textRects: [UUID: SnapRect] = [:]) -> [UUID: ConnectorObject] {
        let locked = Set(lockedObjects ?? [])
        var result: [UUID: ConnectorObject] = [:]
        for shape in shapes ?? [] { result[shape.id] = ConnectorObject(shape: shape, locked: locked.contains(shape.id)) }
        for text in texts {
            let rect = textRects[text.id] ?? SnapRect(x: text.x, y: text.y, width: text.width, height: text.fontSize + 4)
            result[text.id] = ConnectorObject(id: text.id, rect: rect, rotation: text.rotation ?? 0, locked: locked.contains(text.id))
        }
        for image in images {
            let angle = image.rotation ?? 0, sideways = abs(angle.truncatingRemainder(dividingBy: 180)) == 90
            let w = sideways ? image.height : image.width, h = sideways ? image.width : image.height
            let rect = SnapRect(x: image.x + (image.width - w) / 2, y: image.y + (image.height - h) / 2, width: w, height: h)
            result[image.id] = ConnectorObject(id: image.id, rect: rect, rotation: angle, locked: locked.contains(image.id))
        }
        return result
    }
    /// Connected edges belong to a moved/copied group when both targets do.
    func includingInternalConnectors(_ ids: Set<UUID>) -> Set<UUID> {
        let locked = Set(lockedObjects ?? [])
        var result = ids
        for value in connectors ?? [] where !locked.contains(value.id) {
            if let a = value.from.objectID, let b = value.to.objectID, ids.contains(a), ids.contains(b) { result.insert(value.id) }
        }
        return result
    }
    func selectingObjects(_ ids: Set<UUID>, objects: [UUID: ConnectorObject]) -> Self {
        let selected = includingInternalConnectors(ids)
        var copy = self; copy.refreshConnectorFallbacks(objects: objects)
        copy.texts.removeAll { !selected.contains($0.id) }; copy.images.removeAll { !selected.contains($0.id) }
        copy.shapes = copy.shapes?.filter { selected.contains($0.id) }; copy.tapes = copy.tapes?.filter { selected.contains($0.id) }
        copy.connectors = copy.connectors?.filter { selected.contains($0.id) }; copy.pruneObjectReferences()
        return copy
    }
}

public extension ConnectorElement {
    func transformed(scale: Double = 1, radians: Double = 0, origin: StrokeSample = .init(x: 0, y: 0), dx: Double = 0, dy: Double = 0) -> Self {
        guard [scale, radians, origin.x, origin.y, dx, dy].allSatisfy(\.isFinite), scale > 0 else { return self }
        func point(_ p: StrokeSample) -> StrokeSample {
            let x = (p.x - origin.x) * scale, y = (p.y - origin.y) * scale
            return .init(x: origin.x + x * cos(radians) - y * sin(radians) + dx, y: origin.y + x * sin(radians) + y * cos(radians) + dy)
        }
        var value = self
        let a = point(from.point), b = point(to.point)
        value.from.x = a.x; value.from.y = a.y; value.to.x = b.x; value.to.y = b.y
        value.controlPoints = controlPoints?.map(point)
        if var style { style.width = min(200, (style.width ?? 2) * scale); value.style = style }
        return value
    }
}
