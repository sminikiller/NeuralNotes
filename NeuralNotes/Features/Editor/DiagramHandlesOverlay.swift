import UIKit
import NeuralNotesCore

enum DiagramHandle: Hashable { case create(DiagramSide), from, to, bend }

@MainActor
final class DiagramHandlesOverlay: UIView {
    weak var host: CanvasHost?
    weak var model: EditorViewModel?
    var session: DiagramHandleSession?
    var buttons: [DiagramHandleButton] = []
    var objects: [UUID: ConnectorObject] = [:]
    private lazy var diagramSummary: UIAccessibilityElement = {
        let value = UIAccessibilityElement(accessibilityContainer: self)
        value.accessibilityIdentifier = "diagramSummary"
        value.accessibilityLabel = "Diagramma"
        value.accessibilityTraits = .staticText
        return value
    }()
    var isInteracting: Bool { session != nil }
    init(host: CanvasHost, model: EditorViewModel) {
        self.host = host; self.model = model; super.init(frame: host.bounds)
        backgroundColor = .clear; isOpaque = false
    }
    required init?(coder: NSCoder) { nil }
    func update() {
        guard let host, let model, let page = model.page else { cancel(); isHidden = true; return }
        frame = host.bounds
        let blocks = (page.shapes ?? []).filter { !$0.kind.isOpen }.count + page.texts.filter { $0.lensNote == nil }.count
        diagramSummary.accessibilityValue = "\(blocks) blocchi, \(page.connectors?.count ?? 0) collegamenti"
        diagramSummary.accessibilityFrameInContainerSpace = CGRect(x: 4, y: 4, width: 1, height: 1)
        if model.movingObjects && session == nil { hideControls(); return }
        guard !model.selectionPageDragMode, model.hasLease, !model.loading, !model.navigating, model.tool == .objects, model.selectedIDs.count == 1, !model.selectionIncludesInk,
              let id = model.selectedObjectID, !(page.lockedObjects ?? []).contains(id) else { hideControls(); return }
        objects = session?.objects ?? DiagramObjects.make(page)
        var positions: [(DiagramHandle, StrokeSample)] = []
        if session?.isCreating != true, let edge = session?.draft ?? model.selectedConnector {
            positions = [(.from, ConnectorGeometry.resolve(edge.from, objects: objects)), (.to, ConnectorGeometry.resolve(edge.to, objects: objects)),
                         (.bend, edge.routing == .elbow ? edge.controlPoints?.first ?? ConnectorGeometry.midpoint(edge, objects: objects) : ConnectorGeometry.midpoint(edge, objects: objects))]
        } else if let object = objects[id], object.connectionPoints.count == 4,
                  page.shapes?.contains(where: { $0.id == id && !$0.kind.isOpen }) == true || page.texts.contains(where: { $0.id == id && $0.lensNote == nil }) {
            positions = zip(DiagramSide.allCases, object.connectionPoints).map { (.create($0.0), $0.1) }
        }
        isHidden = false
        if buttons.map(\.handle) != positions.map(\.0) {
            buttons.forEach { $0.removeFromSuperview() }; buttons = positions.map { button($0.0) }; buttons.forEach { addSubview($0) }
        }
        for (button, entry) in zip(buttons, positions) {
            let at = host.surface.convert(CGPoint(x: entry.1.x, y: entry.1.y), to: self)
            button.frame = CGRect(x: at.x - 8, y: at.y - 8, width: 16, height: 16)
        }
        accessibilityElements = [diagramSummary] + buttons
        setNeedsDisplay()
    }
    private func hideControls() {
        cancel(); buttons.forEach { $0.removeFromSuperview() }; buttons = []
        accessibilityElements = [diagramSummary]
        isHidden = model?.page?.connectors?.isEmpty != false
    }
    private func button(_ handle: DiagramHandle) -> DiagramHandleButton {
        let button = DiagramHandleButton(handle: handle)
        button.backgroundColor = .systemBlue; button.layer.cornerRadius = 8; button.layer.borderWidth = 2; button.layer.borderColor = UIColor.white.cgColor
        switch handle {
        case .create(let side): button.accessibilityLabel = "Crea blocco collegato \(side.title.lowercased())"; button.accessibilityIdentifier = "diagramCreate-\(side.rawValue)"
        case .from: button.accessibilityLabel = "Estremo iniziale del connettore"
        case .to: button.accessibilityLabel = "Estremo finale del connettore"
        case .bend: button.accessibilityLabel = "Curvatura del connettore"
        }
        button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
        let pan = SnapPanGestureRecognizer(target: self, action: #selector(panned(_:))); pan.maximumNumberOfTouches = 2; button.addGestureRecognizer(pan)
        if case .create = handle {} else {
            button.accessibilityCustomActions = [("Sposta a destra", 10.0, 0.0), ("Sposta a sinistra", -10.0, 0.0), ("Sposta in alto", 0.0, -10.0), ("Sposta in basso", 0.0, 10.0)].map { title, dx, dy in
                UIAccessibilityCustomAction(name: title) { [weak self] _ in self?.adjust(handle, dx: dx, dy: dy) ?? false }
            }
        }
        return button
    }
    @objc private func tapped(_ button: DiagramHandleButton) {
        guard session == nil, let id = model?.selectedObjectID, case .create(let side) = button.handle else { return }
        _ = model?.createDiagramBlock(from: id, side: side); host?.synchronizePage(); update()
    }
    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard let host, let model, let button = gesture.view as? DiagramHandleButton else { return }
        if gesture.state == .began {
            guard !model.interactionBusy, model.hasLease, !model.loading, !model.navigating,
                  let next = DiagramHandleSession(overlay: self, handle: button.handle) else { return }
            session = next; model.cancelMaintenance(); model.movingObjects = true
            host.canvas.panGestureRecognizer.isEnabled = false
        }
        guard let session else { return }
        if gesture.state == .cancelled || gesture.state == .failed { cancel(); update(); return }
        let at = gesture.location(in: host.surface)
        let suspended = (gesture as? SnapPanGestureRecognizer)?.suspendsSnapping == true || gesture.modifierFlags.contains(.alternate)
        session.move(.init(x: at.x, y: at.y), suspended: suspended); update()
        if gesture.state == .ended { session.finish(); update() }
    }
    private func adjust(_ handle: DiagramHandle, dx: Double, dy: Double) -> Bool {
        guard let host, let model, !model.interactionBusy, let next = DiagramHandleSession(overlay: self, handle: handle) else { return false }
        session = next; model.movingObjects = true
        let current: StrokeSample
        switch handle {
        case .from: current = ConnectorGeometry.resolve(next.draft.from, objects: next.objects)
        case .to: current = ConnectorGeometry.resolve(next.draft.to, objects: next.objects)
        default: current = ConnectorGeometry.midpoint(next.draft, objects: next.objects)
        }
        next.move(.init(x: current.x + dx, y: current.y + dy), suspended: true); next.finish(); host.synchronizePage(); update(); return true
    }
    func cancel() {
        guard let session else { return }
        session.cancel(); self.session = nil; model?.movingObjects = false
        if let host {
            host.surface.interactionHiddenObjectIDs.subtract([session.draft.id]); host.paperDetail.update(from: host); host.foregroundObjects.update(host)
            PaperInk.configureNavigation(host.canvas, fingerDrawing: model?.fingerDrawing ?? false)
        }; setNeedsDisplay()
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, let closest = buttons.min(by: { distance(point, $0.center) < distance(point, $1.center) }),
              closest.frame.insetBy(dx: -14, dy: -14).contains(point) else { return false }
        if let other = host?.shapeHandles, !other.isHidden {
            for control in other.subviews where control is UIControl {
                let at = other.convert(control.center, to: self)
                if distance(point, at) < distance(point, closest.center), control.frame.insetBy(dx: -13, dy: -13).contains(other.convert(point, from: self)) { return false }
            }
        }
        return true
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, alpha > 0.01, self.point(inside: point, with: event) else { return nil }
        return buttons.min(by: { distance(point, $0.center) < distance(point, $1.center) })
    }
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    override func draw(_ rect: CGRect) {
        guard let host, let session, let page = model?.page, let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState(); context.translateBy(x: host.surface.frame.minX, y: host.surface.frame.minY)
        context.scaleBy(x: host.canvas.zoomScale, y: host.canvas.zoomScale)
        ConnectorRendering.draw(session.draft, objects: session.objects, page: page, context: context)
        if let target = session.targetID.flatMap({ session.objects[$0] }) {
            let outline = target.outline
            context.setStrokeColor(UIColor.systemBlue.cgColor); context.setLineWidth(2 / host.canvas.zoomScale)
            if let first = outline.first {
                context.move(to: CGPoint(x: first.x, y: first.y))
                for p in outline.dropFirst() { context.addLine(to: CGPoint(x: p.x, y: p.y)) }; context.strokePath()
            }
        }
        let message: String
        if session.handle == .bend { message = "Modifica curva" }
        else if session.freeEnd { message = "Estremo libero" }
        else if session.targetID != nil { message = "Collega al blocco" }
        else { message = session.isCreating ? "Rilascia per un nuovo blocco · trattieni per un estremo libero" : "Estremo libero" }
        (message as NSString).draw(at: CGPoint(x: session.lastPoint.x + 10 / host.canvas.zoomScale, y: session.lastPoint.y + 12 / host.canvas.zoomScale),
            withAttributes: [.font: UIFont.systemFont(ofSize: 11 / host.canvas.zoomScale), .foregroundColor: UIColor.systemBlue, .backgroundColor: UIColor.secondarySystemBackground.withAlphaComponent(0.95)])
        context.restoreGState()
    }
}

@MainActor
final class DiagramHandleButton: UIButton {
    let handle: DiagramHandle
    init(handle: DiagramHandle) { self.handle = handle; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { bounds.insetBy(dx: -14, dy: -14).contains(point) }
}
