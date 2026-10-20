import SwiftUI
import PencilKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    var selectionBounds: CGRect {
        guard let page else { return .null }
        var result = selectionIncludesInk ? selectedInkBounds : .null
        for text in page.texts where selectedIDs.contains(text.id) {
            let size = RichText.attributed(text).boundingRect(with: CGSize(width: text.width, height: page.height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            result = result.union(CGRect(x: text.x, y: text.y, width: text.width, height: max(text.fontSize, size.height)))
        }
        for image in page.images where selectedIDs.contains(image.id) { result = result.union(CGRect(x: image.x, y: image.y, width: image.width, height: image.height)) }
        for shape in page.shapes ?? [] where selectedIDs.contains(shape.id) { result = result.union(CGRect(x: shape.x, y: shape.y, width: shape.width, height: shape.height)) }
        return result
    }
    func transformSelection(scale: CGFloat = 1, degrees: CGFloat = 0) {
        finishInkGesture(); endTextEdit()
        guard hasLease, !interactionBusy, !loading, !navigating, var page, (0.2...5).contains(scale), degrees.isFinite else { return }
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
            let text = page.texts[i], at = CGPoint(x: text.x, y: text.y).applying(transform)
            let attributed = NSMutableAttributedString(attributedString: RichText.attributed(text))
            attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
                if let font = value as? UIFont { attributed.addAttribute(.font, value: font.withSize(min(1000, max(1, font.pointSize * scale))), range: range) }
            }
            page.texts[i].x = at.x; page.texts[i].y = at.y; page.texts[i].width *= Double(scale)
            page.texts[i].fontSize = min(1000, max(1, text.fontSize * Double(scale))); page.texts[i].rotation = (text.rotation ?? 0) + Double(degrees)
            page.texts[i].rtf = RichText.data(attributed)
        }
        if var shapes = page.shapes {
            for i in shapes.indices where selectedIDs.contains(shapes[i].id) {
                let shape = shapes[i], at = center(shape.x, shape.y, shape.width, shape.height)
                shapes[i].width *= Double(scale); shapes[i].height *= Double(scale)
                shapes[i].x = at.x - shapes[i].width / 2; shapes[i].y = at.y - shapes[i].height / 2
                shapes[i].lineWidth = min(200, shape.lineWidth * Double(scale)); shapes[i].rotation = (shape.rotation ?? 0) + Double(degrees)
            }; page.shapes = shapes
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
        if var texts = page?.texts {
            for i in texts.indices where selectedIDs.contains(texts[i].id) {
                let value = NSMutableAttributedString(attributedString: RichText.attributed(texts[i]))
                value.addAttribute(.foregroundColor, value: PaperInk.color(color.color), range: NSRange(location: 0, length: value.length)); texts[i].rtf = RichText.data(value)
            }; page?.texts = texts
        }
        recordEdit(before, label: "Colore selezione"); drawingChanged()
    }
}
