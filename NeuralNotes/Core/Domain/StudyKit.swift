import Foundation

public enum StudyColor: String, Codable, CaseIterable, Sendable {
    case yellow, mint, blue, pink, lavender, orange
    public var title: String {
        switch self { case .yellow: return "Giallo"; case .mint: return "Menta"; case .blue: return "Azzurro"
        case .pink: return "Rosa"; case .lavender: return "Lavanda"; case .orange: return "Arancio" }
    }
    public var ink: InkColor {
        switch self { case .yellow: return InkColor(1, 0.9, 0.48); case .mint: return InkColor(0.65, 0.9, 0.76)
        case .blue: return InkColor(0.65, 0.82, 1); case .pink: return InkColor(1, 0.72, 0.8)
        case .lavender: return InkColor(0.82, 0.75, 1); case .orange: return InkColor(1, 0.78, 0.53) }
    }
}
public enum StudyTapeStyle: String, Codable, CaseIterable, Sendable {
    case solid, translucent, striped
    public var title: String { switch self { case .solid: return "Copertura piena"; case .translucent: return "Trasparente"; case .striped: return "A righe" } }
}
public enum StudyNoteKind: String, Codable, CaseIterable, Sendable {
    case important, review, question, example
    public var title: String { switch self { case .important: return "Importante"; case .review: return "Da ripassare"; case .question: return "Dubbio"; case .example: return "Esempio" } }
    public var icon: String { switch self { case .important: return "star"; case .review: return "repeat"; case .question: return "questionmark.circle"; case .example: return "lightbulb" } }
}
public struct StudyNoteInfo: Codable, Equatable, Sendable {
    public var kind: StudyNoteKind
    public var collapsed: Bool
    public init(kind: StudyNoteKind = .important, collapsed: Bool = false) { self.kind = kind; self.collapsed = collapsed }
}
public enum StudyTapeExport: String, CaseIterable, Sendable {
    case current, covered, answers
    public var title: String { switch self { case .current: return "Come sul foglio"; case .covered: return "Risposte coperte"; case .answers: return "Senza scotch" } }
    public func applying(to page: PageSnapshot) -> PageSnapshot {
        var result = page
        switch self {
        case .current: break
        case .covered: result.tapes = page.tapes?.map { var tape = $0; tape.revealed = false; tape.style = .solid; return tape }
        case .answers: result.tapes = []; result.pruneObjectReferences()
        }
        return result
    }
}

public enum StudyDiagramTemplate: String, CaseIterable, Sendable {
    case mindMap, sequence, comparison, hierarchy, question, nursing
    public var title: String {
        switch self { case .mindMap: return "Mappa concettuale"; case .sequence: return "Causa e conseguenza"
        case .comparison: return "Confronto"; case .hierarchy: return "Albero gerarchico"
        case .question: return "Domanda e risposta"; case .nursing: return "Scheda infermieristica" }
    }
    public var labels: [String] {
        switch self { case .mindMap: return ["Concetto", "Idea 1", "Idea 2", "Idea 3"]
        case .sequence: return ["Causa", "Processo", "Conseguenza"]
        case .comparison: return ["Confronto", "Concetto A", "Concetto B"]
        case .hierarchy: return ["Argomento", "Categoria A", "Categoria B", "Dettaglio A", "Dettaglio B"]
        case .question: return ["Domanda", "Risposta"]
        case .nursing: return ["Argomento", "Definizione", "Sintomi", "Interventi", "Attenzione"] }
    }
}
public struct StudyDiagram: Sendable {
    public var shapes: [ShapeElement]
    public var connectors: [ConnectorElement]
}
public enum StudyDiagrams {
    /// Bounded layout in page coordinates; no pixel images, all nodes stay editable.
    public static func make(_ template: StudyDiagramTemplate, labels input: [String]? = nil,
                            width: Double, height: Double, parents: [Int]? = nil, color: StudyColor = .blue, oval: Bool = false) -> StudyDiagram? {
        guard width.isFinite, height.isFinite, width >= 240, height >= 320 else { return nil }
        let labels = Array((input ?? template.labels).prefix(16)).map { String($0.prefix(400)) }
        guard !labels.isEmpty else { return nil }
        let w = min(210, (width - 72) / 2), h = min(72, (height - 80) / Double(labels.count + 1))
        let gap = min(36, h / 2)
        var shapes: [ShapeElement] = []
        for (i, label) in labels.enumerated() {
            let vertical = template == .sequence || template == .question
            let column = vertical || i == 0 ? 0.5 : Double((i - 1) % 2)
            let row = vertical ? i : (i == 0 ? 0 : (i + 1) / 2)
            let x = 24 + column * (width - 48 - w)
            let y = 40 + Double(row) * (h + gap)
            var shape = ShapeElement(kind: oval ? .ellipse : .rectangle, x: x, y: y, width: w, height: h,
                                     red: 0.18, green: 0.28, blue: 0.4, lineWidth: 2)
            shape.fill = color.ink; shape.fillOpacity = 1; shape.cornerRadius = oval ? 0 : min(12, h / 2)
            shape.label = label; shape.labelFontSize = 18; shape.labelAutoFit = true
            shapes.append(shape)
        }
        var connectors: [ConnectorElement] = []
        for i in shapes.indices.dropFirst() {
            let parent: Int
            if let parents, parents.indices.contains(i), parents[i] >= 0, parents[i] < i { parent = parents[i] }
            else if template == .sequence || template == .question { parent = i - 1 }
            else if template == .hierarchy && i > 2 { parent = i - 2 }
            else { parent = 0 }
            let a = shapes[parent], b = shapes[i]
            let from = ConnectorEnd(objectID: a.id, anchor: .init(x: 0.5, y: 1), x: a.x + a.width / 2, y: a.y + a.height)
            let to = ConnectorEnd(objectID: b.id, anchor: .init(x: 0.5, y: 0), x: b.x + b.width / 2, y: b.y)
            connectors.append(ConnectorElement(from: from, to: to, routing: .elbow))
        }
        return StudyDiagram(shapes: shapes, connectors: connectors)
    }
    public static func outline(_ text: String, title: String) -> (labels: [String], parents: [Int]) {
        var labels = [title.isEmpty ? "Concetti" : String(title.prefix(400))], parents = [0]
        var stack: [(depth: Int, index: Int)] = [(-1, 0)]
        for line in text.components(separatedBy: .newlines) {
            guard let label = listLabels(line).first, labels.count < 16 else { continue }
            let spaces = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
            let depth = min(8, spaces / 2)
            while stack.count > 1 && stack.last!.depth >= depth { stack.removeLast() }
            parents.append(stack.last!.index); labels.append(label); stack.append((depth, labels.count - 1))
        }
        return (labels, parents)
    }
    public static func listLabels(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).compactMap { line in
            let clean = line.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "^(?:[•●◦\\-☐☑]|[0-9]+[.)])\\s*", with: "", options: .regularExpression)
            return clean.isEmpty ? nil : String(clean.prefix(400))
        }
    }
}
