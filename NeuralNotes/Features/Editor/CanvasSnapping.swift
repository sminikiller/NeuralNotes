import UIKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    var snapPreferences: SnapPreferences { currentWorkspace.snapping ?? SnapPreferences() }
    func editSnapPreferences(_ edit: (inout SnapPreferences) -> Void) {
        editWorkspace { workspace in
            var value = workspace.snapping ?? SnapPreferences(); edit(&value); workspace.snapping = value
        }
    }
    func snapObjects(_ page: PageSnapshot) -> [SnapObject] {
        let locked = Set(page.lockedObjects ?? [])
        var values: [SnapObject] = []
        func append(_ id: UUID, _ rect: CGRect, _ rotation: Double = 0) {
            values.append(.init(id: id, rect: SnapRect(rect), rotation: rotation, locked: locked.contains(id)))
        }
        for text in page.texts { append(text.id, RichText.bounds(text, pageHeight: page.height), text.rotation ?? 0) }
        for image in page.images { append(image.id, CGRect(x: image.x, y: image.y, width: image.width, height: image.height), image.rotation ?? 0) }
        for shape in page.shapes ?? [] { append(shape.id, CGRect(x: shape.x, y: shape.y, width: shape.width, height: shape.height), shape.rotation ?? 0) }
        for tape in page.tapes ?? [] { append(tape.id, CGRect(x: tape.x, y: tape.y, width: tape.width, height: tape.height)) }
        return values
    }
    func snapEngine(excluding ids: Set<UUID>) -> SnapEngine? {
        guard let page else { return nil }
        return SnapEngine(objects: snapObjects(page), excluding: ids,
                          page: .init(x: 0, y: 0, width: page.width, height: page.height),
                          margin: page.appearance?.margin == true ? 64 : nil,
                          grid: SnapGrid.forPaper(page.paper, appearance: page.appearance, enabled: snapPreferences.grid))
    }
}
extension SnapRect {
    init(_ rect: CGRect) { self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height) }
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// Transient guides are UI only; they never enter thumbnails, files or PDF.
@MainActor
final class SnapGuidesView: UIView {
    weak var host: CanvasHost?
    private var guides: [SnapGuide] = []
    init(host: CanvasHost) {
        self.host = host; super.init(frame: host.bounds)
        backgroundColor = .clear; isOpaque = false; isUserInteractionEnabled = false
        accessibilityIdentifier = "snapGuides"
    }
    required init?(coder: NSCoder) { nil }
    func show(_ values: [SnapGuide]) {
        guides = values; frame = host?.bounds ?? .zero; setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        guard let host, let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(UIColor.systemTeal.cgColor)
        context.setLineWidth(1 / max(1, window?.screen.scale ?? 2))
        for guide in guides {
            let a = host.surface.convert(CGPoint(x: guide.from.x, y: guide.from.y), to: self)
            let b = host.surface.convert(CGPoint(x: guide.to.x, y: guide.to.y), to: self)
            context.move(to: a); context.addLine(to: b); context.strokePath()
            if let distance = guide.distance {
                let text = String(format: "= %.0f pt", distance) as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: UIColor.systemTeal, .backgroundColor: UIColor.secondarySystemBackground.withAlphaComponent(0.9)]
                text.draw(at: CGPoint(x: (a.x + b.x) / 2 + 3, y: (a.y + b.y) / 2 + 3), withAttributes: attributes)
            }
        }
    }
}
