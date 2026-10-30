import SwiftUI
import PencilKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    var selectionBounds: CGRect {
        guard let page else { return .null }
        var result = selectionIncludesInk ? selectedInkBounds : .null
        for text in page.texts where selectedIDs.contains(text.id) {
            result = result.union(RichText.bounds(text, pageHeight: page.height).applying(RichText.rotation(text, pageHeight: page.height)))
        }
        for image in page.images where selectedIDs.contains(image.id) { result = result.union(CGRect(x: image.x, y: image.y, width: image.width, height: image.height)) }
        for tape in page.tapes ?? [] where selectedIDs.contains(tape.id) { result = result.union(CGRect(x: tape.x, y: tape.y, width: tape.width, height: tape.height)) }
        for shape in page.shapes ?? [] where selectedIDs.contains(shape.id) {
            let box = ShapeGeometry.bounds(shape)
            result = result.union(CGRect(x: box.x, y: box.y, width: box.width, height: box.height))
            if let label = DiagramLabels.shape(shape, page: page) { result = result.union(label.box.applying(label.transform)) }
        }
        if page.connectors?.isEmpty == false {
            let objects = DiagramObjects.make(page)
            for edge in page.connectors ?? [] where selectedIDs.contains(edge.id) {
                result = result.union(ConnectorGeometry.bounds(edge, objects: objects).cgRect)
                if let label = DiagramLabels.connector(edge, objects: objects, page: page) { result = result.union(label.box) }
            }
        }
        return result
    }
    func transformSelection(scale: CGFloat = 1, degrees: CGFloat = 0) {
        finishInkGesture(); endTextEdit()
        guard hasLease, !interactionBusy, !loading, !navigating, var page, (0.2...5).contains(scale), degrees.isFinite else { return }
        selectedIDs = page.includingInternalConnectors(selectedIDs)
        let bounds = selectionBounds; guard !bounds.isNull else { return }
        let before = captureEdit(ink: selectionIncludesInk)
        let cx = bounds.midX, cy = bounds.midY
        let transform = CGAffineTransform(translationX: -cx, y: -cy).concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(rotationAngle: degrees * .pi / 180)).concatenating(CGAffineTransform(translationX: cx, y: cy))
        func center(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGPoint { CGPoint(x: x + w / 2, y: y + h / 2).applying(transform) }
        for i in page.images.indices where selectedIDs.contains(page.images[i].id) {
            let image = page.images[i], at = center(image.x, image.y, image.width, image.height)
            page.images[i].width *= Double(scale); page.images[i].height *= Double(scale)
            page.images[i].x = at.x - page.images[i].width / 2; page.images[i].y = at.y - page.images[i].height / 2
            page.images[i].rotation = (image.rotation ?? 0) + Double(degrees)
        }
        for i in page.texts.indices where selectedIDs.contains(page.texts[i].id) {
            let text = page.texts[i], box = RichText.bounds(text, pageHeight: page.height)
            let at = CGPoint(x: box.midX, y: box.midY).applying(transform)
            let attributed = NSMutableAttributedString(attributedString: RichText.attributed(text))
            attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
                if let font = value as? UIFont { attributed.addAttribute(.font, value: font.withSize(min(1000, max(1, font.pointSize * scale))), range: range) }
            }
            page.texts[i].x = at.x - box.width * scale / 2; page.texts[i].y = at.y - box.height * scale / 2; page.texts[i].width *= Double(scale)
            page.texts[i].fontSize = min(1000, max(1, text.fontSize * Double(scale))); page.texts[i].rotation = (text.rotation ?? 0) + Double(degrees)
            page.texts[i].rtf = RichText.data(attributed)
        }
        if var shapes = page.shapes {
            for i in shapes.indices where selectedIDs.contains(shapes[i].id) {
                let shape = shapes[i], at = center(shape.x, shape.y, shape.width, shape.height)
                shapes[i].width *= Double(scale); shapes[i].height *= Double(scale)
                shapes[i].x = at.x - shapes[i].width / 2; shapes[i].y = at.y - shapes[i].height / 2
                shapes[i].lineWidth = min(200, shape.lineWidth * Double(scale)); shapes[i].rotation = (shape.rotation ?? 0) + Double(degrees)
                let maximumRadius = min(shapes[i].width, shapes[i].height) / 2
                shapes[i].cornerRadius = shape.cornerRadius.map { min($0 * Double(scale), maximumRadius) }
                shapes[i] = DiagramLabels.scaling(shapes[i], by: Double(scale))
            }; page.shapes = shapes
        }
        if var tapes = page.tapes {
            for i in tapes.indices where selectedIDs.contains(tapes[i].id) {
                let tape = tapes[i], at = center(tape.x, tape.y, tape.width, tape.height)
                tapes[i].width *= Double(scale); tapes[i].height *= Double(scale)
                tapes[i].x = at.x - tapes[i].width / 2; tapes[i].y = at.y - tapes[i].height / 2
            }; page.tapes = tapes
        }
        page.connectors = page.connectors?.map { edge in
            guard selectedIDs.contains(edge.id) else { return edge }
            var value = edge.transformed(scale: Double(scale), radians: Double(degrees) * .pi / 180, origin: .init(x: cx, y: cy))
            if let id = value.from.objectID, !selectedIDs.contains(id) { value.from.objectID = nil }
            if let id = value.to.objectID, !selectedIDs.contains(id) { value.to.objectID = nil }
            return DiagramLabels.scaling(value, by: Double(scale))
        }
        self.page = page
        if selectionIncludesInk {
            canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes.enumerated().map { index, stroke in
                guard selectedStrokeIndices == nil || selectedStrokeIndices?.contains(index) == true else { return stroke }
                return PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform.concatenating(transform), mask: stroke.mask)
            })
        }
        recordEdit(before, label: degrees == 0 ? "Ridimensiona selezione" : "Ruota selezione"); drawingChanged()
    }
    func recolorSelection(_ color: InkColor) {
        finishInkGesture(); guard hasLease, !interactionBusy, color.isValid else { return }
        let before = captureEdit(ink: selectionIncludesInk)
        if selectionIncludesInk {
            canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes.enumerated().map { index, stroke in
                guard selectedStrokeIndices == nil || selectedStrokeIndices?.contains(index) == true else { return stroke }
                return PKStroke(ink: PKInk(stroke.ink.inkType, color: PaperInk.color(color.color)), path: stroke.path, transform: stroke.transform, mask: stroke.mask)
            })
        }
        if var shapes = page?.shapes {
            for i in shapes.indices where selectedIDs.contains(shapes[i].id) { shapes[i].red = color.red; shapes[i].green = color.green; shapes[i].blue = color.blue }; page?.shapes = shapes
        }
        if var edges = page?.connectors {
            for i in edges.indices where selectedIDs.contains(edges[i].id) { var style = edges[i].effectiveStyle; style.color = color; edges[i].style = style }
            page?.connectors = edges
        }
        if var texts = page?.texts {
            for i in texts.indices where selectedIDs.contains(texts[i].id) {
                let value = NSMutableAttributedString(attributedString: RichText.attributed(texts[i]))
                value.addAttribute(.foregroundColor, value: PaperInk.color(color.color), range: NSRange(location: 0, length: value.length)); texts[i].rtf = RichText.data(value)
            }; page?.texts = texts
        }
        recordEdit(before, label: "Colore selezione"); drawingChanged()
    }
    func changeSelectionWidth(_ width: Double) {
        finishInkGesture()
        guard hasLease, !interactionBusy, !navigating, !loading, width.isFinite, (0.5...40).contains(width) else { return }
        let before = captureEdit(ink: selectionIncludesInk)
        if selectionIncludesInk {
            canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes.enumerated().map { index, stroke in
                guard selectedStrokeIndices == nil || selectedStrokeIndices?.contains(index) == true else { return stroke }
                let points = Array(stroke.path), peak = max(0.1, points.map { $0.size.width }.max() ?? 1)
                let scale = max(0.001, hypot(stroke.transform.a, stroke.transform.b))
                let ratio = CGFloat(width) / (peak * scale)
                let resized = points.map { point in PKStrokePoint(location: point.location, timeOffset: point.timeOffset,
                    size: CGSize(width: point.size.width * ratio, height: point.size.height * ratio), opacity: point.opacity,
                    force: point.force, azimuth: point.azimuth, altitude: point.altitude) }
                return PKStroke(ink: stroke.ink, path: PKStrokePath(controlPoints: resized, creationDate: stroke.path.creationDate), transform: stroke.transform, mask: stroke.mask)
            })
        }
        if var shapes = page?.shapes {
            for i in shapes.indices where selectedIDs.contains(shapes[i].id) { shapes[i].lineWidth = width }; page?.shapes = shapes
        }
        if var edges = page?.connectors {
            for i in edges.indices where selectedIDs.contains(edges[i].id) { var style = edges[i].effectiveStyle; style.width = width; edges[i].style = style }
            page?.connectors = edges
        }
        recordEdit(before, label: "Spessore selezione"); drawingChanged()
    }
}
