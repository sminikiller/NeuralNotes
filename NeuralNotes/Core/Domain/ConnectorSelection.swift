import Foundation

public extension ConnectorGeometry {
    static func intersects(_ connector: ConnectorElement, objects: [UUID: ConnectorObject], selection: [StrokeSample]) -> Bool {
        guard selection.count >= 3, selection.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return false }
        let polygon = selection.count > 128 ? ShapeRecognitionMath.resample(selection + [selection[0]], count: 128) : selection
        let paths = [path(connector, objects: objects)] + arrowPaths(connector, objects: objects)
        for path in paths { for line in ShapeGeometry.polylines(path) {
            if line.contains(where: { ShapeGeometry.contains($0, polygon: polygon) }) { return true }
            for i in 1..<line.count { for j in polygon.indices {
                if crossing(line[i - 1], line[i], polygon[j], polygon[(j + 1) % polygon.count]) { return true }
            } }
        } }
        return false
    }
    private static func crossing(_ a: StrokeSample, _ b: StrokeSample, _ c: StrokeSample, _ d: StrokeSample) -> Bool {
        let ux = b.x - a.x, uy = b.y - a.y, vx = d.x - c.x, vy = d.y - c.y
        let denominator = ux * vy - uy * vx, dx = c.x - a.x, dy = c.y - a.y
        if abs(denominator) < 0.000001 {
            return ShapeGeometry.segmentDistance(c, a, b) < 0.001 || ShapeGeometry.segmentDistance(d, a, b) < 0.001 || ShapeGeometry.segmentDistance(a, c, d) < 0.001
        }
        let t = (dx * vy - dy * vx) / denominator, s = (dx * uy - dy * ux) / denominator
        return (-0.000001...1.000001).contains(t) && (-0.000001...1.000001).contains(s)
    }
}
