import Foundation

public enum DiagramSide: Int, CaseIterable, Hashable, Sendable {
    case top, right, bottom, left
    public var title: String {
        switch self { case .top: return "Sopra"; case .right: return "A destra"; case .bottom: return "Sotto"; case .left: return "A sinistra" }
    }
    public var opposite: Self { Self(rawValue: (rawValue + 2) % 4)! }
}

public enum QuickDiagramLayout {
    /// Keeps the 48pt edge gap. Try perpendicular offsets when the ideal place
    /// is occupied, then other directions; never place a block outside the page.
    public static func duplicate(_ source: SnapRect, side: DiagramSide, page: SnapRect, obstacles: [SnapRect]) -> SnapRect? {
        guard source.valid, page.valid, source.width <= page.width - 16, source.height <= page.height - 16 else { return nil }
        let directions = [side] + DiagramSide.allCases.filter { $0 != side }
        for direction in directions {
            var ideal = source
            switch direction {
            case .top: ideal.y -= source.height + 48
            case .right: ideal.x += source.width + 48
            case .bottom: ideal.y += source.height + 48
            case .left: ideal.x -= source.width + 48
            }
            for index in [0, 1, -1, 2, -2, 3, -3] {
                var candidate = ideal
                if direction == .left || direction == .right { candidate.y += Double(index) * (source.height + 24) }
                else { candidate.x += Double(index) * (source.width + 24) }
                guard candidate.x >= page.x + 8, candidate.y >= page.y + 8,
                      candidate.maxX <= page.maxX - 8, candidate.maxY <= page.maxY - 8 else { continue }
                if !obstacles.contains(where: { overlaps(candidate, $0, gap: 8) }) { return candidate }
            }
        }
        return nil
    }
    public static func atDrop(_ point: StrokeSample, size: SnapRect, page: SnapRect, obstacles: [SnapRect]) -> SnapRect? {
        guard point.x.isFinite, point.y.isFinite, size.valid, page.valid, size.width <= page.width - 16, size.height <= page.height - 16 else { return nil }
        let x = min(page.maxX - size.width - 8, max(page.x + 8, point.x - size.width / 2))
        let y = min(page.maxY - size.height - 8, max(page.y + 8, point.y - size.height / 2))
        let box = SnapRect(x: x, y: y, width: size.width, height: size.height)
        if !obstacles.contains(where: { overlaps(box, $0, gap: 8) }) { return box }
        return duplicate(box, side: .bottom, page: page, obstacles: obstacles)
    }
    private static func overlaps(_ a: SnapRect, _ b: SnapRect, gap: Double) -> Bool {
        a.x < b.maxX + gap && a.maxX > b.x - gap && a.y < b.maxY + gap && a.maxY > b.y - gap
    }
}
