import UIKit
import PencilKit
import NeuralNotesCore

@MainActor
final class ProtractorInkSession {
    private weak var host: CanvasHost?
    private weak var model: EditorViewModel?
    private let pageID: UUID, guide: ProtractorGuide, mode: ProtractorGuide.Mode, measuring: Bool
    private let before: PKDrawing
    private let preview = CAShapeLayer()
    private var points: [StrokeSample] = []
    private var lastAngle = 0.0, sweep = 0.0
    init?(host: CanvasHost, model: EditorViewModel, start: StrokeSample) {
        guard model.protractorActive else { return nil }
        host.protractorGuide?.update()
        guard model.tool == .pen || model.tool == .marker,
              let page = model.page, let mode = model.protractorGuide.mode(at: start, zoom: Double(host.canvas.zoomScale)),
              !model.protractorMeasure || mode == .ray else { return nil }
        self.host = host; self.model = model; pageID = page.id; guide = model.protractorGuide; self.mode = mode
        before = model.canvas.drawing; measuring = model.protractorMeasure
        if !measuring { model.strokeBegan() }
        model.protractorDrawing = true; model.drawingShape = true; model.configureTool()
        preview.fillColor = nil; preview.lineCap = .round; preview.lineJoin = .round
        lastAngle = guide.angle(at: start) ?? 0
        move([CGPoint(x: start.x, y: start.y)])
    }
    func move(_ samples: [CGPoint]) {
        guard let host, let model, model.page?.id == pageID else { return }
        for sample in samples {
            guard let point = guide.project(.init(x: sample.x, y: sample.y), mode: mode),
                  host.surface.bounds.contains(CGPoint(x: point.x, y: point.y)) else { continue }
            let angle = guide.angle(at: point) ?? lastAngle
            if mode == .ray {
                points = [.init(x: guide.x, y: guide.y), point]
                model.guideReadout = String(format: "%.0f°", angle * 180 / .pi)
            } else {
                var delta = angle - lastAngle
                if delta > .pi { delta -= 2 * .pi }; if delta < -.pi { delta += 2 * .pi }
                sweep += delta; points.append(point)
                if points.count > 2000 { points = points.enumerated().filter { $0.offset % 2 == 0 || $0.offset == points.count - 1 }.map(\.element) }
                model.guideReadout = String(format: "Arco %.0f°", abs(sweep) * 180 / .pi)
            }
            lastAngle = angle
        }
        host.protractorGuide?.update()
        let path = UIBezierPath()
        for (index, point) in points.enumerated() {
            let at = host.surface.convert(CGPoint(x: point.x, y: point.y), to: host)
            if index == 0 { path.move(to: at) } else { path.addLine(to: at) }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        preview.path = path.cgPath
        preview.strokeColor = measuring ? UIColor.systemOrange.cgColor : PaperInk.color(model.ink).cgColor
        preview.lineWidth = CGFloat(measuring ? 2 : model.tool == .marker ? model.markerWidth : model.thickness) * host.canvas.zoomScale
        preview.opacity = model.tool == .marker && !measuring ? 0.4 : 1
        preview.removeFromSuperlayer(); host.layer.addSublayer(preview); CATransaction.commit()
    }
    func finish(cancelled: Bool) {
        preview.removeFromSuperlayer()
        guard let model else { return }
        defer { model.protractorDrawing = false; model.drawingShape = false; model.configureTool(); host?.protractorGuide?.update() }
        guard model.page?.id == pageID else { return }
        guard !cancelled, let first = points.first, let last = points.last, points.count > 1,
              mode == .arc || hypot(last.x - first.x, last.y - first.y) >= 2 else { model.cancelGuidedInk(before); return }
        if measuring {
            if model.protractorRays.count >= 2 { model.protractorRays = [] }
            model.protractorRays.append(lastAngle)
            if model.protractorRays.count == 2, let angle = ProtractorGuide.difference(model.protractorRays[0], model.protractorRays[1]) {
                model.guideReadout = String(format: "Angolo %.0f°", angle * 180 / .pi)
            }
            model.cancelGuidedInk(before); return
        }
        let width = model.tool == .marker ? model.markerWidth : model.thickness
        let controls = points.enumerated().map { index, point in
            PKStrokePoint(location: CGPoint(x: point.x, y: point.y), timeOffset: Double(index) * 0.01,
                size: CGSize(width: width, height: width), opacity: model.tool == .marker ? 0.4 : 1,
                force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let ink = PKInk(model.tool == .marker ? .marker : model.writingOptions.pen.native, color: PaperInk.color(model.ink))
        let stroke = PKStroke(ink: ink, path: PKStrokePath(controlPoints: controls, creationDate: Date()))
        model.installNativeInk(PKDrawing(strokes: before.strokes + [stroke]))
        model.drawingShape = false; model.strokeEnded(); model.finishInkGesture()
    }
}
