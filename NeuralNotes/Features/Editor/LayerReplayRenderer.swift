import UIKit
import PencilKit
import NeuralNotesCore

/// Replay has a separate, bounded read-only cache. A clock tick compares small
/// signature/occurrence timelines; unchanged owners reuse their blend maps.
/// Native archives are loaded sequentially only when their visible ink changes.
@MainActor
final class LayerReplayRenderer {
    static let budget = 32 << 20
    private struct Entry {
        let source: String
        let signatures: [String]
        let visible: [Int]
        let hot: [Int]
        let hiddenIDs: Set<UUID>
        let maps: LayerBlendCompositor.Maps
    }
    private var pageKey: PageSnapshot?
    private var entries: [UUID: Entry] = [:]
    private var scale: CGFloat = 0
    private(set) var nativeReads = 0
    private var frameImage: UIImage?
    private var framePDFVersion = -1
    private var frameDimension: CGFloat = 0
    var cachedBytes: Int { entries.values.reduce(0) { $0 + $1.maps.byteCost } }
    func clear() { entries = [:]; pageKey = nil; scale = 0; frameImage = nil; framePDFVersion = -1 }

    func image(page: PageSnapshot, workspace: DocumentWorkspace, live: PKDrawing, owner: UUID,
               generation: UUID, sessionID: UUID, seconds: Double, mode: AudioReplayMode,
               hiding: Set<UUID>, maxDimension: CGFloat = 1600) async throws -> UIImage {
        try PageValidation.validate(page)
        let groups = try LayerRenderPlan.make(page: page, selection: .visible).filter { $0.opacity > 0 }
        let bounds = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        let maps = max(1, groups.count * 2), pixels = bounds.width * bounds.height
        let nextScale = min(2, maxDimension / max(bounds.width, bounds.height),
            sqrt(CGFloat(Self.budget) * 0.8 / (CGFloat(maps) * 4 * pixels)),
            sqrt(4_000_000 / pixels), 8192 / max(bounds.width, bounds.height))
        let metadata = LayerScene.fingerprint(page, owner: owner)
        var changed = pageKey != metadata || scale != nextScale
        if pageKey != metadata || scale != nextScale { entries = [:]; pageKey = metadata; scale = nextScale }
        let ids = Set(groups.map { $0.layer.id })
        for id in Array(entries.keys) where !ids.contains(id) { entries[id] = nil }
        for group in groups {
            try Task.checkCancellation()
            let id = group.layer.id
            let source = id == owner ? "live|\(generation)" : "\(group.drawingFile ?? "empty")|\(group.previousDrawingFile ?? "empty")"
            let previous = entries[id]
            var drawing: PKDrawing?
            let signatures: [String]
            if previous?.source == source { signatures = previous!.signatures }
            else {
                drawing = try await read(page: page, layerID: id, owner: owner, live: live, workspace: workspace)
                signatures = EditorInkSignatures.make(drawing!)
            }
            let visible = mode == .showAll ? Array(signatures.indices) : LayerStrokeTimeline.visible(signatures: signatures,
                anchors: page.anchors, pageID: page.id, layerID: id, sessionID: sessionID, seconds: seconds)
            let hot = mode == .showAll ? LayerStrokeTimeline.current(signatures: signatures, anchors: page.anchors,
                pageID: page.id, layerID: id, sessionID: sessionID, seconds: seconds) : []
            if let previous, previous.source == source, previous.visible == visible, previous.hot == hot, previous.hiddenIDs == hiding { continue }
            if drawing == nil { drawing = try await read(page: page, layerID: id, owner: owner, live: live, workspace: workspace) }
            let value = try autoreleasepool { () throws -> Entry in
                let native = drawing!
                let owner = PreparedLayerOwner(group: group, page: page, package: workspace.package,
                    drawing: PKDrawing(strokes: visible.map { native.strokes[$0] }), bounds: bounds, scale: scale,
                    signatures: visible.map { signatures[$0] }, hot: Set(hot.map { signatures[$0] }), hiding: hiding)
                guard let result = LayerBlendCompositor.maps(opacity: group.opacity, bounds: bounds, scale: scale,
                    content: { owner.draw(in: $0) }) else { throw WorkspaceFailure.oversizedImport }
                return Entry(source: source, signatures: signatures, visible: visible, hot: hot, hiddenIDs: hiding, maps: result)
            }
            entries[id] = value; drawing = nil; changed = true
            guard cachedBytes <= Self.budget else { clear(); throw WorkspaceFailure.oversizedImport }
            await Task.yield()
        }
        try Task.checkCancellation()
        let pdfVersion = PDFRasterCache.shared.version(page: page, package: workspace.package)
        if !changed, pdfVersion == framePDFVersion, maxDimension == frameDimension, let frameImage { return frameImage }
        let format = UIGraphicsImageRendererFormat(); format.opaque = true; format.scale = min(2, maxDimension / max(bounds.width, bounds.height))
        let result = UIGraphicsImageRenderer(bounds: bounds, format: format).image { renderer in
            PageRenderer.drawPaper(page, package: workspace.package, in: renderer.cgContext, pdfMode: .interactive)
            for group in groups { entries[group.layer.id]?.maps.draw(in: renderer.cgContext, bounds: bounds) }
        }
        frameImage = result; framePDFVersion = pdfVersion; frameDimension = maxDimension
        return result
    }
    private func read(page: PageSnapshot, layerID: UUID, owner: UUID, live: PKDrawing, workspace: DocumentWorkspace) async throws -> PKDrawing {
        if layerID == owner { return live }
        nativeReads += 1
        return try await LayerDrawingReader.read(page: page, layerID: layerID, workspace: workspace).drawing
    }
}
