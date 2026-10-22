import UIKit
import NeuralNotesCore

/// On-screen helpers for Lens notes, never exported: the round control that
/// reduces an open note to 💡, the dashed link to the text it explains (with the
/// Lens tool or when the note is selected), the outline after a jump and the
/// highlight of the words the Lens is working on.
@MainActor
final class LensNotesOverlay: UIView {
    private var page = PageSnapshot()
    private var links = false
    private var selected: Set<UUID> = []
    private var focus: LensNoteFocus?
    private var hidden: UUID?
    private var marked: [CGRect] = []
    private var signature = ""

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false; isOpaque = false; backgroundColor = .clear; isHidden = true
        accessibilityIdentifier = "lensNotesOverlay"
    }
    required init?(coder: NSCoder) { nil }

    func update(_ host: CanvasHost) {
        guard let model = host.model else { isHidden = true; return }
        let current = host.surface.page
        let notes = current.texts.filter { $0.lensNote != nil }
        let shownFocus = model.lensNoteFocus.flatMap { $0.pageID == current.id ? $0 : nil }
        let highlight = model.lensHighlight.flatMap { $0.pageID == current.id ? $0.rects : nil } ?? []
        guard !notes.isEmpty || shownFocus != nil || !highlight.isEmpty else {
            if !isHidden { isHidden = true; layer.contents = nil; signature = "" }
            return
        }
        isHidden = false
        bounds = host.surface.bounds; transform = host.surface.transform; center = host.surface.center
        let maximum: CGFloat = sqrt(8_000_000 / max(1, CGFloat(current.width * current.height)))
        let scale = min(maximum, max(1, host.canvas.zoomScale * (host.window?.screen.scale ?? UIScreen.main.scale)))
        if abs(contentScaleFactor - scale) > 0.15 { contentScaleFactor = scale; setNeedsDisplay() }
        let showLinks = model.tool == .lens
        let chosen = model.selectedIDs.filter { id in notes.contains { $0.id == id } }
        let shape = notes.map { "\($0.id)|\($0.x)|\($0.y)|\($0.width)|\($0.text.count)|\($0.lensNote?.isCollapsed == true)" }.joined(separator: ";")
        let dragged = host.surface.hiddenObjectID
        let marks = highlight.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" }.joined(separator: ";")
        let key = "\(current.id)|\(shape)|\(showLinks)|\(chosen.map(\.uuidString).sorted())|\(shownFocus?.id.uuidString ?? "")|\(dragged?.uuidString ?? "")|\(marks)"
        guard key != signature else { return }
        signature = key; page = current; links = showLinks; selected = chosen; focus = shownFocus; hidden = dragged; marked = highlight
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        if !marked.isEmpty {
            context.saveGState()
            context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.38).cgColor)
            for rect in marked { context.addPath(UIBezierPath(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 3).cgPath) }
            context.fillPath()
            context.restoreGState()
        }
        for text in page.texts {
            guard let note = text.lensNote, !note.isCollapsed, text.id != hidden else { continue }
            let box = RichText.bounds(text, pageHeight: page.height)
            if links || selected.contains(text.id), let source = note.source, source.pageID == page.id {
                context.saveGState()
                context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.22).cgColor)
                context.addPath(UIBezierPath(roundedRect: source.rect.insetBy(dx: -2, dy: -2), cornerRadius: 4).cgPath); context.fillPath()
                if let link = LensNotes.connector(note: box, source: source.rect) {
                    context.setStrokeColor(UIColor.systemOrange.withAlphaComponent(0.75).cgColor)
                    context.setLineWidth(1.5); context.setLineDash(phase: 0, lengths: [5, 4]); context.setLineCap(.round)
                    context.move(to: link.from); context.addLine(to: link.to); context.strokePath()
                    context.setFillColor(UIColor.systemOrange.withAlphaComponent(0.85).cgColor)
                    context.fillEllipse(in: CGRect(x: link.to.x - 3, y: link.to.y - 3, width: 6, height: 6))
                }
                context.restoreGState()
            }
            let control = LensNotes.reduceControl(note: box, pageWidth: page.width, pageHeight: page.height).insetBy(dx: 2, dy: 2)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.25).cgColor)
            context.setFillColor(UIColor.white.cgColor); context.fillEllipse(in: control)
            context.restoreGState()
            context.saveGState()
            context.setStrokeColor(UIColor.systemOrange.cgColor); context.setLineWidth(1.2); context.strokeEllipse(in: control)
            context.setLineWidth(2); context.setLineCap(.round)
            // A chevron pointing down: "reduce".
            let mid = CGPoint(x: control.midX, y: control.midY), arm = control.width * 0.22
            context.move(to: CGPoint(x: mid.x - arm, y: mid.y - arm * 0.5)); context.addLine(to: CGPoint(x: mid.x, y: mid.y + arm * 0.6))
            context.addLine(to: CGPoint(x: mid.x + arm, y: mid.y - arm * 0.5)); context.strokePath()
            context.restoreGState()
        }
        if let focus {
            context.saveGState()
            context.setStrokeColor(UIColor.systemOrange.cgColor); context.setLineWidth(3)
            context.addPath(UIBezierPath(roundedRect: focus.rect.insetBy(dx: -10, dy: -10), cornerRadius: 10).cgPath); context.strokePath()
            context.restoreGState()
        }
    }
}
