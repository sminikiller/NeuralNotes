import Foundation

/// Stable document coordinates. The active PKCanvas still stores page-local ink.
public struct ContinuousPageLayout: Equatable, Sendable {
    public struct Frame: Equatable, Sendable {
        public let id: UUID
        public let x: Double, y: Double, width: Double, height: Double
        public var maxY: Double { y + height }
    }
    public let frames: [Frame]
    public let width: Double, height: Double, maximumPageHeight: Double
    public let gap: Double
    public init(pages: [PageSnapshot], gap: Double = 12) {
        let valid = pages.filter { $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0 }
        let spacing = gap.isFinite ? max(0, min(40, gap)) : 12
        let width = valid.map(\.width).max() ?? 1
        var y = 0.0, frames: [Frame] = []
        for page in valid {
            frames.append(Frame(id: page.id, x: (width - page.width) / 2, y: y, width: page.width, height: page.height))
            y += page.height + spacing
        }
        self.frames = frames; self.width = width; self.height = max(0, y - (valid.isEmpty ? 0 : spacing))
        self.maximumPageHeight = valid.map(\.height).max() ?? 1; self.gap = spacing
    }
    public func frame(_ id: UUID) -> Frame? { frames.first { $0.id == id } }
    public func page(atX x: Double, y: Double) -> UUID? {
        frames.first { x >= $0.x && x <= $0.x + $0.width && y >= $0.y && y <= $0.maxY }?.id
    }
    public func mostVisible(top: Double, height: Double) -> UUID? {
        guard top.isFinite, height.isFinite, height > 0 else { return nil }
        return frames.max { a, b in
            max(0, min(a.maxY, top + height) - max(a.y, top)) < max(0, min(b.maxY, top + height) - max(b.y, top))
        }.flatMap { min($0.maxY, top + height) > max($0.y, top) ? $0.id : nil }
    }
}
