import UIKit
import PencilKit
import NeuralNotesCore

/// One gesture, one cached spatial index and visible outline per touched
/// stroke. Pointer updates only change memory; persistence starts after lift.
@MainActor
final class SelectiveEraseSession {
    private weak var model: EditorViewModel?
    private let before: EditorContentState?, original: PKDrawing, originalPage: PageSnapshot?
    private let pageID: UUID?, target: EraserTarget, width: Double, whole: Bool, includeObjects: Bool
    private var native: [UUID: PKStroke] = [:], visible: [UUID: CGPath] = [:]
    private var order: [UUID] = [], originalIndices: [UUID: Int] = [:]
    private var objectRegions: [UUID: CGPath] = [:], boxes: [UUID: SnapRect] = [:]
    private var index = EraserSpatialIndex(boxes: [:])
    private var queued: [StrokeSample] = [], tail: StrokeSample?
    private var frame: Task<Void, Never>?
    private var changed = false
    private var finished = false
    private(set) var outlineBuilds = 0
    init(model: EditorViewModel) {
        self.model = model; before = model.captureEdit(ink: true); original = model.canvas.drawing; originalPage = model.page; pageID = model.page?.id
        target = model.writingOptions.effectiveEraserTarget; width = model.writingOptions.eraserWidth; whole = model.writingOptions.eraser == .stroke
        includeObjects = model.writingOptions.erasesObjects
        if let page = model.page { objectRegions = EraserObjectGeometry.regions(page: page, target: target, includeObjects: includeObjects) }
        for (id, path) in objectRegions { boxes[id] = SnapRect(path.boundingBoxOfPath.insetBy(dx: -0.5, dy: -0.5)) }
        for (offset, stroke) in original.strokes.enumerated() {
            var id = UUID(); while boxes[id] != nil || native[id] != nil { id = UUID() }
            native[id] = stroke; order.append(id); originalIndices[id] = offset
            if target.includesInk && (target == .all || (target == .marker) == (stroke.ink.inkType == .marker)) {
                boxes[id] = SnapRect(stroke.renderBounds.insetBy(dx: -1, dy: -1))
            }
        }
        index = EraserSpatialIndex(boxes: boxes)
        model.eraserCompositionToken = UUID(); model.drawingShape = true
    }
    func append(_ samples: [StrokeSample]) {
        guard !finished else { return }; queued += samples
        guard frame == nil else { return }
        frame = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            self?.process(); self?.frame = nil
        }
    }
    private func process() {
        guard let model, model.page?.id == pageID, !queued.isEmpty else { return }
        let samples = tail.map { [$0] + queued } ?? queued; tail = queued.last; queued = []
        guard let area = EraserStrokeGeometry.area(samples: samples, width: width) else { return }
        let candidates = index.candidates(in: SnapRect(area.boundingBoxOfPath.insetBy(dx: -0.5, dy: -0.5)))
        var removed = Set<UUID>(), inkChanged = false
        for id in candidates {
            if let stroke = native[id] {
                let region: CGPath
                if let cached = visible[id] { region = cached }
                else { region = EraserStrokeGeometry.visible(stroke); visible[id] = region; outlineBuilds += 1 }
                if let result = EraserStrokeGeometry.cut(stroke, visible: region, area: area, whole: whole) {
                    native[id] = result.stroke; visible[id] = result.visible; inkChanged = true
                }
            } else if let region = objectRegions[id], !region.intersection(area, using: .winding).isEmpty { removed.insert(id) }
        }
        guard inkChanged || !removed.isEmpty else { return }; changed = true
        if !removed.isEmpty, var page = model.page {
            if page.connectors?.isEmpty == false { page.refreshConnectorFallbacks(objects: DiagramObjects.make(page)) }
            page.texts.removeAll { removed.contains($0.id) }; page.images.removeAll { removed.contains($0.id) }
            page.shapes?.removeAll { removed.contains($0.id) }; page.connectors?.removeAll { removed.contains($0.id) }
            page.tapes?.removeAll { removed.contains($0.id) }; page.pdfMarkups?.removeAll { removed.contains($0.id) }
            page.pruneObjectReferences(); model.page = page
            // Detaching an end can change its route. Refresh object geometry
            // only after a deletion, not for every coalesced pointer sample.
            for id in objectRegions.keys { boxes[id] = nil }
            objectRegions = EraserObjectGeometry.regions(page: page, target: target, includeObjects: includeObjects)
            for (id, region) in objectRegions { boxes[id] = SnapRect(region.boundingBoxOfPath.insetBy(dx: -0.5, dy: -0.5)) }
            index = EraserSpatialIndex(boxes: boxes)
        }
        if inkChanged { model.canvas.drawing = PKDrawing(strokes: order.compactMap { native[$0] }) }
    }
    func finish(cancelled: Bool) {
        guard !finished else { return }; finished = true; frame?.cancel(); frame = nil
        guard let model else { return }
        defer { model.eraserCompositionToken = nil; model.drawingShape = false; model.configureTool() }
        guard model.page?.id == pageID else { return }
        if cancelled { model.page = originalPage; model.installNativeInk(original); return }
        process()
        model.drawingShape = false
        if changed {
            let drawing = PKDrawing(strokes: order.compactMap { native[$0] })
            let oldKeys = EditorInkSignatures.make(original), newKeys = EditorInkSignatures.make(drawing)
            let anchors = Dictionary(grouping: originalPage?.anchors ?? [], by: \.signature)
            let retained = order.filter { native[$0] != nil }
            model.page?.anchors = retained.enumerated().flatMap { offset, id in
                guard let originalIndex = originalIndices[id] else { return [] as [StrokeAnchor] }
                return (anchors[oldKeys[originalIndex]] ?? []).map { anchor in var value = anchor; value.signature = newKeys[offset]; return value }
            }
            model.installNativeInk(drawing); model.selectedIDs.formIntersection(model.page?.objectIDs ?? [])
            model.recordEdit(before, label: "Gomma · \(target.title)"); model.drawingChanged(preservingRecognizedWords: target == .marker)
        }
        if model.writingOptions.returnToPen { model.chooseTool(.pen) }
    }
}
