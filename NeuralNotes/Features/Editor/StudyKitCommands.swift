import SwiftUI
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    func beginStudyReview() {
        guard !studyReview, !interactionBusy else { return }
        endTextEdit(); studyToolBeforeReview = tool; tool = .audioLink; studyReview = true
        setStudyTapes(revealed: false); configureTool()
    }
    func endStudyReview() { studyReview = false; tool = studyToolBeforeReview; configureTool() }
    func setStudyTapes(revealed: Bool) {
        guard let current = page else { return }
        let allowed = PageLayers.editableObjectIDs(in: current, layerID: activeLayerID ?? current.id)
        mutatePage(revealed ? "Scopri risposte" : "Copri risposte") { page in
            page.tapes = page.tapes?.map { var tape = $0; if allowed.contains(tape.id) { tape.revealed = revealed }; return tape }
        }
    }
    func revealNextStudyTape() {
        guard let page else { return }
        let allowed = PageLayers.editableObjectIDs(in: page, layerID: activeLayerID ?? page.id)
        let next = (page.tapes ?? []).filter { !$0.revealed && allowed.contains($0.id) }
            .sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }.first
        if let next { toggleTape(next.id) }
    }
    func styleStudyTape(id: UUID, color: StudyColor, style: StudyTapeStyle, width: Double, height: Double) {
        guard let current = page, PageLayers.editableObjectIDs(in: current, layerID: activeLayerID ?? current.id).contains(id), width.isFinite, height.isFinite else { return }
        mutatePage("Modifica scotch") { page in
            guard let i = page.tapes?.firstIndex(where: { $0.id == id }) else { return }
            page.tapes?[i].color = color; page.tapes?[i].style = style
            page.tapes?[i].width = max(12, min(page.width, width)); page.tapes?[i].height = max(12, min(page.height, height))
        }
    }
    func insertStudyNote(text: String, kind: StudyNoteKind, color: StudyColor) {
        guard canEditActiveLayer else { return }
        var note = TextElement(text: text.isEmpty ? kind.title : String(text.prefix(20_000)))
        note.studyNote = StudyNoteInfo(kind: kind); note.background = color.ink
        note.fontSize = 20; note.width = min(260, max(40, (page?.width ?? 768) - 96))
        mutatePage("Inserisci post-it") { $0.texts.append(note) }
        tool = .objects; selectedObjectID = note.id; configureTool()
    }
    func studyNoteHit(at point: CGPoint) -> UUID? {
        guard let page else { return nil }
        let visible = Set(PageLayers.ordered(in: page).filter { $0.isVisible }.map(\.id))
        return page.texts.reversed().first { text in
            text.studyNote != nil && visible.contains(text.layerID ?? page.id) &&
            RichText.bounds(text, pageHeight: page.height).contains(point.applying(RichText.rotation(text, pageHeight: page.height).inverted()))
        }?.id
    }
    func toggleStudyNote(_ id: UUID) {
        guard let current = page, PageLayers.editableObjectIDs(in: current, layerID: activeLayerID ?? current.id).contains(id) else { return }
        mutatePage("Apri o richiudi post-it") { page in
            if let i = page.texts.firstIndex(where: { $0.id == id }) { page.texts[i].studyNote?.collapsed.toggle() }
        }
    }
    func insertStudyDiagram(_ template: StudyDiagramTemplate, labels: [String]? = nil, parents: [Int]? = nil, color: StudyColor, oval: Bool) {
        guard canEditActiveLayer, let page,
              let diagram = StudyDiagrams.make(template, labels: labels, width: page.width, height: page.height, parents: parents, color: color, oval: oval) else { return }
        mutatePage("Inserisci \(template.title.lowercased())") { value in
            let order = value.orderedObjectIDs
            value.shapes = (value.shapes ?? []) + diagram.shapes
            value.connectors = (value.connectors ?? []) + diagram.connectors
            value.objectOrder = diagram.connectors.map(\.id) + order + diagram.shapes.map(\.id)
        }
        tool = .objects; selectedObjectID = diagram.shapes.first?.id; configureTool()
    }
    func insertStudyList(_ content: String, title: String, kind: Int, color: StudyColor) {
        let lines = Array(content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(80))
        guard canEditActiveLayer, !lines.isEmpty else { return }
        let output = NSMutableAttributedString(string: "")
        if !title.isEmpty {
            output.append(NSAttributedString(string: String(title.prefix(200)) + "\n", attributes: [.font: UIFont.boldSystemFont(ofSize: 26), .foregroundColor: UIColor.black]))
        }
        for (index, line) in lines.enumerated() {
            let leading = line.prefix { $0 == " " || $0 == "\t" }.count
            let level = min(4, leading / 2)
            let prefix = kind == 1 ? "\(index + 1). " : kind == 2 ? "☐ " : "• "
            let paragraph = NSMutableParagraphStyle(); paragraph.paragraphSpacing = 9; paragraph.lineSpacing = 3
            paragraph.firstLineHeadIndent = CGFloat(level * 22); paragraph.headIndent = CGFloat(level * 22 + 24)
            let text = String(repeating: "  ", count: level) + prefix + line.trimmingCharacters(in: .whitespaces) + (index == lines.count - 1 ? "" : "\n")
            output.append(NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.black, .paragraphStyle: paragraph]))
        }
        var element = TextElement(text: output.string); element.rtf = RichText.data(output); element.fontSize = 20
        element.width = min(440, max(40, (page?.width ?? 768) - 96)); element.background = color.ink
        mutatePage("Inserisci elenco") { $0.texts.append(element) }
        tool = .objects; selectedObjectID = element.id; configureTool()
    }
}

@MainActor
enum StudyNoteRendering {
    static func drawBadge(_ text: TextElement, context: CGContext) {
        let box = RichText.bounds(text, pageHeight: 20000)
        context.saveGState(); defer { context.restoreGState() }
        context.concatenate(RichText.rotation(text, pageHeight: 20000))
        context.setFillColor((text.background ?? StudyColor.yellow.ink).studyUIColor.cgColor)
        context.addPath(UIBezierPath(roundedRect: box, cornerRadius: 8).cgPath); context.fillPath()
        let label = text.studyNote?.kind.title ?? "Post-it"
        LayerPDFText.draw(NSAttributedString(string: label, attributes: [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.black]),
                          in: box.insetBy(dx: 8, dy: 8), context: context)
    }
    static func drawTape(_ tape: StudyTape, context: CGContext) {
        let box = CGRect(x: tape.x, y: tape.y, width: tape.width, height: tape.height)
        let color = (tape.color ?? .yellow).ink.studyUIColor
        context.saveGState(); defer { context.restoreGState() }
        if tape.revealed {
            context.setStrokeColor(color.cgColor); context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 3]); context.stroke(box); return
        }
        let path = UIBezierPath(roundedRect: box, cornerRadius: min(5, box.height / 4)).cgPath
        context.addPath(path); context.clip()
        context.setFillColor(color.withAlphaComponent(tape.style == .translucent ? 0.55 : 1).cgColor); context.fill(box)
        if tape.style == .striped {
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.28).cgColor); context.setLineWidth(3)
            var x = box.minX - box.height
            while x < box.maxX { context.move(to: CGPoint(x: x, y: box.minY)); context.addLine(to: CGPoint(x: x + box.height, y: box.maxY)); x += 16 }
            context.strokePath()
        }
        if box.width > 100 && box.height > 28 {
            LayerPDFText.draw(NSAttributedString(string: "Tocca per scoprire", attributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.darkGray]),
                              in: box.insetBy(dx: 8, dy: 6), context: context)
        }
    }
}

private extension InkColor {
    var studyUIColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }
}
