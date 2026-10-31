import UIKit
import NeuralNotesCore

@MainActor
enum EraserObjectGeometry {
    static func regions(page: PageSnapshot, target: EraserTarget) -> [UUID: CGPath] {
        let locked = Set(page.lockedObjects ?? []), objects = page.connectors?.isEmpty == false ? DiagramObjects.make(page) : [:]
        var regions: [UUID: CGPath] = [:]
        if target == .all || target == .text {
            for text in page.texts where !locked.contains(text.id) && (target == .all || text.lensNote == nil) {
                let box = text.lensNote?.isCollapsed == true ? LensNotes.badge(x: text.x, y: text.y) : DiagramObjects.textBounds(text, pageHeight: page.height)
                var transform = text.lensNote?.isCollapsed == true ? CGAffineTransform.identity : RichText.rotation(text, pageHeight: page.height)
                regions[text.id] = CGPath(rect: box, transform: &transform)
            }
        }
        if target == .all || target == .images {
            for image in page.images where !locked.contains(image.id) {
                let box = CGRect(x: image.x, y: image.y, width: image.width, height: image.height)
                let angle = (image.rotation ?? 0).truncatingRemainder(dividingBy: 360), sideways = abs(angle.truncatingRemainder(dividingBy: 180)) == 90
                let size = sideways ? CGSize(width: box.height, height: box.width) : box.size
                var transform = CGAffineTransform(rotationAngle: angle * .pi / 180).concatenating(.init(translationX: box.midX, y: box.midY))
                regions[image.id] = CGPath(rect: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height), transform: &transform)
            }
        }
        if target == .all || target == .shapes {
            for shape in page.shapes ?? [] where !locked.contains(shape.id) { regions[shape.id] = shapeRegion(shape, page: page) }
            for edge in page.connectors ?? [] where !locked.contains(edge.id) { regions[edge.id] = connectorRegion(edge, objects: objects, page: page) }
        }
        if target == .all {
            for tape in page.tapes ?? [] where !locked.contains(tape.id) {
                let box = CGPath(rect: CGRect(x: tape.x, y: tape.y, width: tape.width, height: tape.height), transform: nil)
                regions[tape.id] = tape.revealed ? box.copy(strokingWithWidth: 1, lineCap: .round, lineJoin: .round, miterLimit: 1) : box
            }
        }
        for markup in page.pdfMarkups ?? [] where target == .all || (target == .marker && markup.kind == .highlight) || (target == .pen && markup.kind == .underline) {
            let box = CGRect(x: markup.x, y: markup.y, width: markup.width, height: markup.height)
            regions[markup.id] = CGPath(rect: markup.kind == .highlight ? box : CGRect(x: box.minX, y: box.maxY - 0.5, width: box.width, height: 1), transform: nil)
        }
        return regions
    }
    private static func shapeRegion(_ shape: ShapeElement, page: PageSnapshot) -> CGPath {
        let outline = ShapePathRendering.path(ShapeGeometry.path(for: shape))
        var region: CGPath = CGMutablePath()
        if (shape.strokeOpacity ?? 1) > 0 {
            region = stroked(outline, width: shape.lineWidth, dash: shape.dash ?? .solid)
            for head in ShapeGeometry.arrowPaths(for: shape) {
                let path = ShapePathRendering.path(head)
                region = region.union(path.copy(strokingWithWidth: shape.lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 1), using: .winding)
                if shape.arrowStyle == .filled { region = region.union(path, using: .winding) }
            }
        }
        if shape.fill != nil, (shape.fillOpacity ?? 0.25) > 0, !shape.kind.isOpen { region = region.union(outline, using: .winding) }
        if let label = DiagramLabels.shape(shape, page: page) {
            var transform = label.transform
            var text = CGPath(rect: label.box, transform: &transform)
            if !shape.kind.isOpen { text = text.intersection(outline, using: .winding) }
            region = region.union(text, using: .winding)
        }
        return region
    }
    private static func connectorRegion(_ edge: ConnectorElement, objects: [UUID: ConnectorObject], page: PageSnapshot) -> CGPath {
        let width = CGFloat(edge.effectiveStyle.width ?? 2), path = ShapePathRendering.path(ConnectorGeometry.path(edge, objects: objects))
        var region: CGPath = CGMutablePath()
        if (edge.effectiveStyle.strokeOpacity ?? 1) > 0 {
            region = stroked(path, width: Double(width), dash: edge.effectiveStyle.dash ?? .solid)
            for head in ConnectorGeometry.arrowPaths(edge, objects: objects) {
                let line = ShapePathRendering.path(head)
                region = region.union(line.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1), using: .winding)
                if edge.effectiveStyle.arrowStyle == .filled { region = region.union(line, using: .winding) }
            }
        }
        if let label = DiagramLabels.connector(edge, objects: objects, page: page) { region = region.union(CGPath(rect: label.box.insetBy(dx: -4, dy: -2), transform: nil), using: .winding) }
        return region
    }
    private static func stroked(_ path: CGPath, width: Double, dash: ShapeDash) -> CGPath {
        let lengths = dash.lengths(width: width).map { CGFloat($0) }
        let center = lengths.isEmpty ? path : path.copy(dashingWithPhase: 0, lengths: lengths)
        return center.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
    }
}
