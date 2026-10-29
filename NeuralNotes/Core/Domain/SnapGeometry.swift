import Foundation

public struct SnapPreferences: Codable, Equatable, Sendable {
    public var objects: Bool?
    public var grid: Bool?
    public var guides: Bool?
    public var keepProportions: Bool?
    public init() { }
    public var objectsEnabled: Bool { objects ?? true }
    public var guidesEnabled: Bool { guides ?? true }
}

public struct SnapRect: Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var valid: Bool {
        [x, y, width, height].allSatisfy { $0.isFinite && abs($0) <= 1_000_000 } && width > 0 && height > 0
    }
    public func offset(x dx: Double, y dy: Double) -> Self { .init(x: x + dx, y: y + dy, width: width, height: height) }
}
public struct SnapObject: Sendable {
    public var id: UUID
    public var rect: SnapRect
    public var rotation: Double
    public var locked: Bool
    public init(id: UUID, rect: SnapRect, rotation: Double = 0, locked: Bool = false) {
        self.id = id; self.rect = rect; self.rotation = rotation; self.locked = locked
    }
}
public struct SnapGuide: Equatable, Sendable {
    public var from: StrokeSample, to: StrokeSample
    public var distance: Double?
    public init(_ from: StrokeSample, _ to: StrokeSample, distance: Double? = nil) {
        self.from = from; self.to = to; self.distance = distance
    }
}
public struct SnapResult: Sendable {
    public var rect: SnapRect
    public var guides: [SnapGuide] = []
    public var snapped: Bool = false
}
public struct SnapGrid: Sendable {
    public var step: Double
    public var origin: StrokeSample
    public var isometric: Bool
    public init(step: Double = 8, origin: StrokeSample = .init(x: 0, y: 0), isometric: Bool = false) {
        self.step = step; self.origin = origin; self.isometric = isometric
    }
    public static func forPaper(_ paper: PaperStyle, appearance: PaperAppearance?, enabled: Bool?) -> Self? {
        let patterned = [.grid, .dotted, .millimeter, .isometric].contains(paper)
        guard enabled ?? patterned else { return nil }
        let step = appearance?.spacing ?? 24
        switch paper {
        case .grid, .dotted: return .init(step: step, origin: .init(x: 24, y: 48))
        case .millimeter: return .init(step: step / 4)
        case .isometric: return .init(step: step, isometric: true)
        default: return .init()
        }
    }
    /// Intersections of the paper renderer's two oblique line families (±30°,
    /// hence 60° to one another). Existing paper rendering stays unchanged.
    public func nearest(_ point: StrokeSample) -> StrokeSample? {
        guard step.isFinite, step >= 1, step <= 1000, point.x.isFinite, point.y.isFinite, abs(point.x) <= 1_000_000, abs(point.y) <= 1_000_000,
              origin.x.isFinite, origin.y.isFinite else { return nil }
        let px = point.x - origin.x, py = point.y - origin.y
        if !isometric {
            return .init(x: origin.x + (px / step).rounded() * step, y: origin.y + (py / step).rounded() * step)
        }
        // An isometric lattice has offset rows. Search adjacent columns rather
        // than rounding x/y independently, which produces a rectangular grid.
        let columnWidth = step * sqrt(3.0) / 2
        let column = (px / columnWidth).rounded()
        var best: StrokeSample?, error = Double.infinity
        for offset in -1...1 {
            let index = column + Double(offset)
            let x = index * columnWidth
            let phase = index * step / 2
            let y = phase + ((py - phase) / step).rounded() * step
            let distance = hypot(x - px, y - py)
            if distance < error { error = distance; best = .init(x: x + origin.x, y: y + origin.y) }
        }
        return best
    }
}
