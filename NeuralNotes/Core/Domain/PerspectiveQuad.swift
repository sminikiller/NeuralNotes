import Foundation

/// Image coordinates, after EXIF orientation, with the origin at the top left.
public struct PerspectivePoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}

public struct PerspectiveQuad: Codable, Equatable, Sendable {
    public var topLeft: PerspectivePoint
    public var topRight: PerspectivePoint
    public var bottomRight: PerspectivePoint
    public var bottomLeft: PerspectivePoint
    public init(topLeft: PerspectivePoint, topRight: PerspectivePoint, bottomRight: PerspectivePoint, bottomLeft: PerspectivePoint) {
        self.topLeft = topLeft; self.topRight = topRight; self.bottomRight = bottomRight; self.bottomLeft = bottomLeft
    }
    public var points: [PerspectivePoint] { [topLeft, topRight, bottomRight, bottomLeft] }
    public static let full = PerspectiveQuad(topLeft: .init(x: 0, y: 0), topRight: .init(x: 1, y: 0),
        bottomRight: .init(x: 1, y: 1), bottomLeft: .init(x: 0, y: 1))

    /// Canonical winding for four unordered corners. Validation deliberately
    /// checks the supplied winding, so corrupt/bow-tie documents aren't repaired silently.
    public func ordered() -> Self {
        guard points.allSatisfy(\.isValid) else { return self }
        let centerX = points.reduce(0) { $0 + $1.x } / 4
        let centerY = points.reduce(0) { $0 + $1.y } / 4
        let sorted = points.sorted { atan2($0.y - centerY, $0.x - centerX) < atan2($1.y - centerY, $1.x - centerX) }
        let start = sorted.indices.min { a, b in
            let sa = sorted[a].x + sorted[a].y, sb = sorted[b].x + sorted[b].y
            return sa == sb ? sorted[a].y < sorted[b].y : sa < sb
        } ?? 0
        let p = (0..<4).map { sorted[(start + $0) % 4] }
        return Self(topLeft: p[0], topRight: p[1], bottomRight: p[2], bottomLeft: p[3])
    }
    public var isConvex: Bool {
        let p = points
        guard p.allSatisfy(\.isValid) else { return false }
        var sign = 0.0
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            guard abs(cross) > 0.000001 else { return false }
            if sign == 0 { sign = cross }
            if sign * cross <= 0 { return false }
        }
        return true
    }
    public struct Size: Equatable, Sendable {
        public let width: Double
        public let height: Double
        public init(width: Double, height: Double) { self.width = width; self.height = height }
    }
    public func outputSize(for size: Size) -> Size? {
        guard isConvex, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        func distance(_ a: PerspectivePoint, _ b: PerspectivePoint) -> Double {
            hypot((b.x - a.x) * size.width, (b.y - a.y) * size.height)
        }
        let width = (distance(topLeft, topRight) + distance(bottomLeft, bottomRight)) / 2
        let height = (distance(topLeft, bottomLeft) + distance(topRight, bottomRight)) / 2
        guard width.isFinite, height.isFinite, width >= 1, height >= 1 else { return nil }
        return Size(width: width, height: height)
    }
}

/// All edits are metadata. Crop coordinates refer to the corrected, rotated image.
public struct PhotoAdjustment: Codable, Equatable, Sendable {
    public var crop: NormalizedCrop
    public var perspective: PerspectiveQuad?
    public var quarterTurns: Int
    public var enhanced: Bool
    public init(crop: NormalizedCrop = .full, perspective: PerspectiveQuad? = nil, quarterTurns: Int = 0, enhanced: Bool = false) {
        self.crop = crop; self.perspective = perspective; self.quarterTurns = quarterTurns; self.enhanced = enhanced
    }
}
