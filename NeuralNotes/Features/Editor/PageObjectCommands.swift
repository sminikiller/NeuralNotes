import SwiftUI
import UIKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    func addStickyNote(_ label: String = "Nuovo post-it") {
        var text = TextElement(text: label); text.width = min(260, max(40, (page?.width ?? 768) - 96)); text.fontSize = 20
        text.background = InkColor(1, 0.94, 0.55); text.studyNote = StudyNoteInfo()
        mutatePage("Inserisci post-it") { $0.texts.append(text) }
        tool = .objects; selectedObjectID = text.id; configureTool()
    }
    func addStudyTape(color: StudyColor? = nil, style: StudyTapeStyle? = nil, width: Double? = nil, height: Double? = nil) {
        guard canEditActiveLayer else { return }
        let bounds = selectionBounds
        var tape = bounds.isNull || bounds.width < 4 ? StudyTape(width: min(320, max(40, (page?.width ?? 768) - 96)))
            : StudyTape(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(24, bounds.height))
        tape.color = color; tape.style = style
        if let width { tape.width = max(12, min(page?.width ?? 768, width)) }
        if let height { tape.height = max(12, min(page?.height ?? 1024, height)) }
        mutatePage("Copri risposta") { $0.tapes = ($0.tapes ?? []) + [tape] }
        tool = .objects; selectedObjectID = tape.id; configureTool()
    }
    func tapeHit(at point: CGPoint) -> UUID? {
        guard let page else { return nil }
        let allowed = PageLayers.editableObjectIDs(in: page, layerID: activeLayerID ?? page.id)
        return page.tapes?.reversed().first { allowed.contains($0.id) && CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height).contains(point) }?.id
    }
    func toggleTape(_ id: UUID) {
        mutatePage("Scopri o copri risposta") { page in if let i = page.tapes?.firstIndex(where: { $0.id == id }) { page.tapes?[i].revealed.toggle() } }
    }
    func arrangeSelection(front: Bool) {
        let selected = selectedIDs
        mutatePage(front ? "Porta davanti" : "Porta dietro") { page in
            let current = page.orderedObjectIDs, group = current.filter { selected.contains($0) }, rest = current.filter { !selected.contains($0) }
            page.objectOrder = front ? rest + group : group + rest
            let above = Set(page.aboveInkObjects ?? [])
            page.aboveInkObjects = Array(front ? above.union(selected) : above.subtracting(selected))
        }
    }
    func lockSelection() {
        let selected = selectedIDs
        mutatePage("Blocca oggetti") { $0.lockedObjects = Array(Set($0.lockedObjects ?? []).union(selected)) }
        selectedObjectID = nil
    }
    func unlockObjects() { mutatePage("Sblocca oggetti") { $0.lockedObjects = nil } }
}

@MainActor
final class ForegroundObjectsView: UIView {
    var page = PageSnapshot() { didSet { if oldValue != page { setNeedsDisplay() } } }
    var package = URL(fileURLWithPath: "/")
    var hiddenTextID: UUID?
    var hiddenObjectID: UUID?
    private var replayHiddenObjectIDs = Set<UUID>()
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        PageRenderer.drawForeground(page, package: package, in: context, hidingTextID: hiddenTextID, hidingObjectID: hiddenObjectID, hidingObjectIDs: replayHiddenObjectIDs)
    }
    func update(_ host: CanvasHost) {
        if host.surface.page.layers != nil { isHidden = true; layer.contents = nil; return }
        isHidden = (host.surface.page.aboveInkObjects ?? []).isEmpty && (host.surface.page.tapes ?? []).isEmpty
        guard !isHidden else { layer.contents = nil; return }
        isOpaque = false; backgroundColor = .clear; isUserInteractionEnabled = false
        page = host.surface.page; package = host.surface.package
        if replayHiddenObjectIDs != host.surface.allHiddenObjectIDs { replayHiddenObjectIDs = host.surface.allHiddenObjectIDs; setNeedsDisplay() }
        if hiddenTextID != host.surface.hiddenTextID { hiddenTextID = host.surface.hiddenTextID; setNeedsDisplay() }
        if hiddenObjectID != host.surface.hiddenObjectID { hiddenObjectID = host.surface.hiddenObjectID; setNeedsDisplay() }
        bounds = host.surface.bounds; transform = host.surface.transform; center = host.surface.center
        let maximum: CGFloat = sqrt(8_000_000 / max(1, CGFloat(page.width * page.height)))
        contentScaleFactor = min(maximum, max(1, host.canvas.zoomScale * (host.window?.screen.scale ?? UIScreen.main.scale)))
    }
}
