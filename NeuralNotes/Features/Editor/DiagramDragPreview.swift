import UIKit
import NeuralNotesCore

/// Replaces only affected edge pictures while objects use their drag snapshot.
/// No document mutation or file write occurs during this preview.
@MainActor
final class DiagramDragPreview: UIView {
    weak var host: CanvasHost?
    private var page: PageSnapshot?
    private var objects: [UUID: ConnectorObject] = [:]
    private var originalObjects: [UUID: ConnectorObject] = [:]
    private var edges: [ConnectorElement] = []
    private var hiddenEdgeIDs = Set<UUID>()
    init(host: CanvasHost) {
        self.host = host; super.init(frame: host.bounds)
        isUserInteractionEnabled = false; isOpaque = false; backgroundColor = .clear; isHidden = true
    }
    required init?(coder: NSCoder) { nil }
    func start(page: PageSnapshot, moving: Set<UUID>) {
        reset(); guard let host else { return }
        edges = (page.connectors ?? []).filter { edge in
            moving.contains(edge.id) || edge.from.objectID.map { moving.contains($0) } == true || edge.to.objectID.map { moving.contains($0) } == true
        }
        guard !edges.isEmpty else { return }
        self.page = page; originalObjects = DiagramObjects.make(page); objects = originalObjects
        hiddenEdgeIDs = Set(edges.map(\.id)); host.surface.interactionHiddenObjectIDs.formUnion(hiddenEdgeIDs)
        host.paperDetail.update(from: host); host.foregroundObjects.update(host)
        frame = host.bounds; isHidden = false; setNeedsDisplay()
    }
    func update(objects overrides: [UUID: ConnectorObject], edges: [ConnectorElement]? = nil) {
        guard !hiddenEdgeIDs.isEmpty, let host else { return }
        objects = originalObjects.merging(overrides, uniquingKeysWith: { _, next in next })
        if let edges { self.edges = edges.filter { hiddenEdgeIDs.contains($0.id) } }
        frame = host.bounds; setNeedsDisplay()
    }
    func endpoint(of id: UUID, fromStart: Bool) -> StrokeSample? {
        guard let edge = edges.first(where: { $0.id == id }) else { return nil }
        return ConnectorGeometry.resolve(fromStart ? edge.from : edge.to, objects: objects)
    }
    func updateMoving(frames: [UUID: CGRect], dx: Double, dy: Double, resizing: Bool, keepRatio: Bool) {
        guard let page, !hiddenEdgeIDs.isEmpty else { return }
        let selected = Set(frames.keys)
        var overrides: [UUID: ConnectorObject] = [:]
        for (id, frame) in frames {
            if var shape = page.shapes?.first(where: { $0.id == id }) {
                shape.x += dx; shape.y += dy; overrides[id] = ConnectorObject(shape: shape)
            } else if let source = page.texts.first(where: { $0.id == id }) {
                var text = source
                if resizing {
                    text.width = max(24, min(page.width - source.x, frame.width + dx))
                    if keepRatio { text = RichText.scaled(source, by: text.width / max(1, source.width)) }
                } else { text.x += dx; text.y += dy }
                overrides[id] = DiagramObjects.textObject(text, rect: SnapRect(DiagramObjects.textBounds(text, pageHeight: page.height)))
            } else if var image = page.images.first(where: { $0.id == id }) {
                if resizing {
                    let ratio = image.height / max(1, image.width)
                    let available = min(max(1, page.width - image.x), max(1, page.height - image.y) / max(0.01, ratio))
                    image.width = max(min(24, available), min(available, frame.width + dx)); image.height = image.width * ratio
                } else { image.x += dx; image.y += dy }
                let angle = image.rotation ?? 0, sideways = abs(angle.truncatingRemainder(dividingBy: 180)) == 90
                let w = sideways ? image.height : image.width, h = sideways ? image.width : image.height
                let rect = SnapRect(x: image.x + (image.width - w) / 2, y: image.y + (image.height - h) / 2, width: w, height: h)
                overrides[id] = ConnectorObject(id: id, rect: rect, rotation: angle)
            }
        }
        let updated = (page.connectors ?? []).map { edge -> ConnectorElement in
            guard selected.contains(edge.id) else { return edge }
            var copy = edge.transformed(dx: dx, dy: dy)
            if let id = copy.from.objectID, !selected.contains(id) { copy.from.objectID = nil }
            if let id = copy.to.objectID, !selected.contains(id) { copy.to.objectID = nil }
            return copy
        }
        update(objects: overrides, edges: updated)
    }
    func reset() {
        if let host, !hiddenEdgeIDs.isEmpty {
            host.surface.interactionHiddenObjectIDs.subtract(hiddenEdgeIDs)
            host.paperDetail.update(from: host); host.foregroundObjects.update(host)
        }
        page = nil; objects = [:]; originalObjects = [:]; edges = []; hiddenEdgeIDs = []; isHidden = true; layer.contents = nil
    }
    override func draw(_ rect: CGRect) {
        guard let host, let page, let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState(); context.translateBy(x: host.surface.frame.minX, y: host.surface.frame.minY)
        context.scaleBy(x: host.canvas.zoomScale, y: host.canvas.zoomScale)
        for edge in edges { ConnectorRendering.draw(edge, objects: objects, page: page, context: context) }
        context.restoreGState()
    }
}
