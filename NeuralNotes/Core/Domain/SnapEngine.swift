import Foundation

/// Built once at gesture start. Axis cells index edges/centres even when the
/// matching object is far away on the other axis. Queries never sort the page.
public struct SnapEngine: Sendable {
    private struct Reference: Sendable { var value: Double }
    private var xCells: [Int: [Reference]] = [:], yCells: [Int: [Reference]] = [:]
    private var objects: [SnapRect] = []
    private var left: [SnapRect] = [], right: [SnapRect] = [], top: [SnapRect] = [], bottom: [SnapRect] = []
    public var page: SnapRect
    public var grid: SnapGrid?
    public init(objects: [SnapObject], excluding: Set<UUID> = [], page: SnapRect, margin: Double? = nil, grid: SnapGrid? = nil) {
        self.page = page; self.grid = grid
        self.objects = objects.prefix(100_000).filter {
            !excluding.contains($0.id) && !$0.locked && $0.rect.valid && $0.rotation.isFinite &&
            abs($0.rotation.truncatingRemainder(dividingBy: 360)) < 0.001
        }.map(\.rect)
        var references = self.objects
        if page.valid { references.append(page) }
        for rect in references {
            for value in [rect.x, rect.midX, rect.maxX] { xCells[Int(floor(value / 64)), default: []].append(.init(value: value)) }
            for value in [rect.y, rect.midY, rect.maxY] { yCells[Int(floor(value / 64)), default: []].append(.init(value: value)) }
        }
        if let margin, margin.isFinite, margin > 0, margin < page.width {
            xCells[Int(floor(margin / 64)), default: []].append(.init(value: margin))
        }
        left = self.objects.sorted { $0.maxX < $1.maxX }; right = self.objects.sorted { $0.x < $1.x }
        top = self.objects.sorted { $0.maxY < $1.maxY }; bottom = self.objects.sorted { $0.y < $1.y }
    }
    public func snap(_ source: SnapRect, zoom: Double, preferences: SnapPreferences = .init(),
                     resizing: Bool = false, suspended: Bool = false) -> SnapResult {
        var result = SnapResult(rect: source)
        guard source.valid, zoom.isFinite, zoom > 0, !suspended else { return result }
        let threshold = 6 / max(0.05, zoom)
        let xs = resizing ? [source.maxX] : [source.x, source.midX, source.maxX]
        let ys = resizing ? [source.maxY] : [source.y, source.midY, source.maxY]
        var dx: Double?, dy: Double?, gx: Double?, gy: Double?
        if preferences.objectsEnabled {
            (dx, gx) = nearest(xs, cells: xCells, radius: threshold)
            (dy, gy) = nearest(ys, cells: yCells, radius: threshold)
        }
        if preferences.grid != false, let grid, let point = grid.nearest(.init(x: resizing ? source.maxX : source.x, y: resizing ? source.maxY : source.y)) {
            let x = point.x - (resizing ? source.maxX : source.x), y = point.y - (resizing ? source.maxY : source.y)
            if grid.isometric {
                if hypot(x, y) <= threshold, dx == nil, dy == nil { dx = x; dy = y }
            } else {
                if abs(x) <= threshold, dx == nil { dx = x }
                if abs(y) <= threshold, dy == nil { dy = y }
            }
        }
        if !resizing, preferences.objectsEnabled {
            if dx == nil, let gap = equalGap(source, horizontal: true, radius: threshold) {
                dx = gap.0; result.guides += gap.1
            }
            if dy == nil, let gap = equalGap(source, horizontal: false, radius: threshold) {
                dy = gap.0; result.guides += gap.1
            }
        }
        let x = dx ?? 0, y = dy ?? 0
        if resizing {
            result.rect.width = max(1, source.width + x); result.rect.height = max(1, source.height + y)
        } else { result.rect = source.offset(x: x, y: y) }
        result.snapped = dx != nil || dy != nil
        if let gx { result.guides.append(.init(.init(x: gx, y: page.y), .init(x: gx, y: page.maxY))) }
        if let gy { result.guides.append(.init(.init(x: page.x, y: gy), .init(x: page.maxX, y: gy))) }
        if !preferences.guidesEnabled { result.guides = [] }
        return result
    }
    public func snapPoint(_ point: StrokeSample, zoom: Double, preferences: SnapPreferences = .init(), suspended: Bool = false)
        -> (point: StrokeSample, guides: [SnapGuide], snapped: Bool) {
        // A virtual box keeps the endpoint correction symmetric: a one-point
        // box would clamp negative corrections as an invalid resize.
        let source = SnapRect(x: point.x - 512, y: point.y - 512, width: 512, height: 512)
        let result = snap(source, zoom: zoom, preferences: preferences, resizing: true, suspended: suspended)
        return (.init(x: result.rect.maxX, y: result.rect.maxY), result.guides, result.snapped)
    }
    private func nearest(_ values: [Double], cells: [Int: [Reference]], radius: Double) -> (Double?, Double?) {
        var best: Double?, guide: Double?
        for value in values {
            let lower = Int(floor((value - radius) / 64)), upper = Int(floor((value + radius) / 64))
            for cell in lower...upper {
                for target in cells[cell] ?? [] {
                    let delta = target.value - value
                    if abs(delta) <= radius, best == nil || abs(delta) < abs(best!) { best = delta; guide = target.value }
                }
            }
        }
        return (best, guide)
    }
    private func equalGap(_ rect: SnapRect, horizontal: Bool, radius: Double) -> (Double, [SnapGuide])? {
        let low = horizontal ? rect.x : rect.y, high = horizontal ? rect.maxX : rect.maxY
        let preceding = horizontal ? left : top, following = horizontal ? right : bottom
        func overlaps(_ other: SnapRect) -> Bool {
            horizontal ? other.y < rect.maxY && other.maxY > rect.y : other.x < rect.maxX && other.maxX > rect.x
        }
        func end(_ r: SnapRect) -> Double { horizontal ? r.maxX : r.maxY }
        func start(_ r: SnapRect) -> Double { horizontal ? r.x : r.y }
        let beforeIndex = boundary(preceding) { end($0) <= low }
        let afterIndex = boundary(following) { start($0) < high }
        // A bounded local neighbour query also keeps sparse, heavily overlapping
        // pages responsive. No quadratic search or whole-page scan per frame.
        let a = preceding[max(0, beforeIndex - 32)..<beforeIndex].reversed().first(where: overlaps)
        let b = following[afterIndex..<min(following.count, afterIndex + 32)].first(where: overlaps)
        guard let a, let b else { return nil }
        let delta = ((start(b) - high) - (low - end(a))) / 2
        guard abs(delta) <= radius else { return nil }
        let distance = low + delta - end(a), middle = horizontal ? rect.midY : rect.midX
        func p(_ value: Double) -> StrokeSample { horizontal ? .init(x: value, y: middle) : .init(x: middle, y: value) }
        return (delta, [.init(p(end(a)), p(low + delta), distance: distance), .init(p(high + delta), p(start(b)), distance: distance)])
    }
    private func boundary(_ values: [SnapRect], _ before: (SnapRect) -> Bool) -> Int {
        var low = 0, high = values.count
        while low < high { let mid = (low + high) / 2; if before(values[mid]) { low = mid + 1 } else { high = mid } }
        return low
    }
    public static func rotation(_ degrees: Double, suspended: Bool = false) -> Double {
        guard degrees.isFinite, !suspended else { return degrees }
        let angle = degrees.truncatingRemainder(dividingBy: 360)
        let cardinal = (angle / 90).rounded() * 90
        if abs(cardinal - angle) <= 3 { return cardinal }
        let regular = (angle / 15).rounded() * 15
        return abs(regular - angle) <= 2 ? regular : angle
    }
}
