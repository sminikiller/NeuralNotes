import SwiftUI
import PencilKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    var arrangementCount: Int {
        guard let page else { return 0 }
        return snapObjects(page).filter { selectedIDs.contains($0.id) && !$0.locked }.count + (selectionIncludesInk ? 1 : 0)
    }
    func arrangeSelection(_ action: SelectionArrangement) {
        finishInkGesture(); endTextEdit()
        guard hasLease, !interactionBusy, !loading, !navigating, var page else { return }
        var originals = Dictionary(uniqueKeysWithValues: snapObjects(page).filter { selectedIDs.contains($0.id) && !$0.locked }.map { ($0.id, $0.rect) })
        let inkID = UUID(), inkBounds = selectedInkBounds
        if selectionIncludesInk, !inkBounds.isNull, !inkBounds.isEmpty { originals[inkID] = SnapRect(inkBounds) }
        guard originals.count >= action.minimumCount else { return }
        let arranged = action.applying(originals), before = captureEdit(ink: selectionIncludesInk)
        for i in page.images.indices {
            guard let r = arranged[page.images[i].id] else { continue }
            page.images[i].x = r.x; page.images[i].y = r.y; page.images[i].width = r.width; page.images[i].height = r.height
        }
        if var shapes = page.shapes {
            for i in shapes.indices {
                guard let r = arranged[shapes[i].id] else { continue }
                shapes[i].x = r.x; shapes[i].y = r.y; shapes[i].width = r.width; shapes[i].height = r.height
                if [.star, .polygon, .arc].contains(shapes[i].kind) {
                    if action == .width { shapes[i].height = r.width }
                    if action == .height { shapes[i].width = r.height }
                }
                if let radius = shapes[i].cornerRadius { shapes[i].cornerRadius = min(radius, min(r.width, r.height) / 2) }
            }; page.shapes = shapes
        }
        if var tapes = page.tapes {
            for i in tapes.indices {
                guard let r = arranged[tapes[i].id] else { continue }
                tapes[i].x = r.x; tapes[i].y = r.y; tapes[i].width = r.width; tapes[i].height = r.height
            }; page.tapes = tapes
        }
        for i in page.texts.indices {
            let id = page.texts[i].id
            guard let r = arranged[id], let original = originals[id] else { continue }
            page.texts[i].x = r.x; page.texts[i].y = r.y; page.texts[i].width = r.width
            if action == .height {
                let scale = r.height / original.height
                let attributed = NSMutableAttributedString(attributedString: RichText.attributed(page.texts[i]))
                attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
                    if let font = value as? UIFont { attributed.addAttribute(.font, value: font.withSize(min(1000, max(1, font.pointSize * scale))), range: range) }
                }
                page.texts[i].width = original.width * scale
                page.texts[i].fontSize = min(1000, max(1, page.texts[i].fontSize * scale))
                page.texts[i].rtf = RichText.data(attributed)
            }
        }
        self.page = page
        if let target = arranged[inkID] {
            let sx = target.width / inkBounds.width, sy = target.height / inkBounds.height
            let transform = CGAffineTransform(translationX: -inkBounds.minX, y: -inkBounds.minY)
                .concatenating(CGAffineTransform(scaleX: sx, y: sy)).concatenating(CGAffineTransform(translationX: target.x, y: target.y))
            canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes.enumerated().map { index, stroke in
                guard selectedStrokeIndices == nil || selectedStrokeIndices?.contains(index) == true else { return stroke }
                return PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform.concatenating(transform), mask: stroke.mask)
            })
        }
        recordEdit(before, label: action.title); drawingChanged()
    }
}

@MainActor
struct SelectionAlignmentMenu: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        Menu {
            ForEach(SelectionArrangement.allCases, id: \.self) { action in
                Button(action.title) { model.arrangeSelection(action) }.disabled(model.arrangementCount < action.minimumCount)
            }
        } label: { Image(systemName: "align.horizontal.left") }
            .accessibilityLabel("Allinea e distribuisci").accessibilityIdentifier("selectionAlignment")
            .disabled(model.arrangementCount < 2)
    }
}
