import Foundation

public enum MindMapLayout {
    /// Arrange the actual outline lines into editable native objects. This does
    /// not infer new facts, generate hidden summaries or flatten a bitmap.
    public static func page(from artifact: AIArtifact, width: Double = 1024, height: Double = 1024) -> PageSnapshot? {
        guard width.isFinite, height.isFinite, (640...20000).contains(width), (640...20000).contains(height) else { return nil }
        let lines = artifact.text.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t#*-•")).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }
        let leaves = Array(lines.dropFirst().prefix(8))
        var page = PageSnapshot(); page.width = width; page.height = height; page.paper = .plain
        page.title = String(("Mappa · " + lines[0]).prefix(120)).replacingOccurrences(of: "\n", with: " ")
        let nodeWidth = min(240.0, width * 0.24), nodeHeight = min(120.0, height * 0.12)
        var root = TextElement(text: String(lines[0].prefix(120)))
        root.fontSize = 21; root.width = nodeWidth; root.x = (width - nodeWidth) / 2; root.y = (height - nodeHeight) / 2
        root.background = InkColor(0.75, 0.93, 0.89); page.texts = [root]
        var shapes: [ShapeElement] = []
        let citation = try? NSRegularExpression(pattern: "\\[(\\d+)\\]")
        for (index, line) in leaves.enumerated() {
            let left = index % 2 == 0, row = index / 2, rows = max(1, (leaves.count + 1) / 2)
            let x = left ? width * 0.04 : width - nodeWidth - width * 0.04
            let y = height * 0.06 + Double(row) * (height * 0.88 - nodeHeight) / Double(max(1, rows - 1))
            var node = TextElement(text: String(line.prefix(160))); node.fontSize = 16; node.width = nodeWidth; node.x = x; node.y = y
            node.background = InkColor(0.94, 0.95, 1)
            if let match = citation?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let range = Range(match.range(at: 1), in: line),
               let number = Int(line[range]), artifact.references.indices.contains(number - 1), let pageID = artifact.references[number - 1].pageID {
                node.pageLink = PageLinkTarget(documentID: artifact.references[number - 1].documentID, pageID: pageID)
            }
            if let connector = ShapeElement.dragged(kind: .line,
                from: StrokeSample(x: left ? root.x : root.x + nodeWidth, y: root.y + nodeHeight / 2),
                to: StrokeSample(x: left ? x + nodeWidth : x, y: y + nodeHeight / 2), color: .blue, lineWidth: 1.5) { shapes.append(connector) }
            page.texts.append(node)
        }
        page.shapes = shapes; page.objectOrder = shapes.map(\.id) + page.texts.map(\.id)
        return (try? PageValidation.validate(page)) == nil ? nil : page
    }
}
