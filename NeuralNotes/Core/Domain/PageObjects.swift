import Foundation

public struct StudyTape: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var x: Double, y: Double, width: Double, height: Double
    public var revealed = false
    public init(x: Double = 48, y: Double = 120, width: Double = 320, height: Double = 56) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var isValid: Bool { [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0 && width <= 20000 && height <= 20000 }
}

public extension PageSnapshot {
    var objectIDs: [UUID] { images.map(\.id) + (shapes ?? []).map(\.id) + texts.map(\.id) + (tapes ?? []).map(\.id) }
    var orderedObjectIDs: [UUID] {
        let valid = Set(objectIDs); var seen = Set<UUID>()
        return ((objectOrder ?? []) + objectIDs).filter { valid.contains($0) && seen.insert($0).inserted }
    }
    mutating func pruneObjectReferences() {
        let valid = Set(objectIDs)
        objectOrder = objectOrder?.filter { valid.contains($0) }
        lockedObjects = lockedObjects?.filter { valid.contains($0) }
        aboveInkObjects = aboveInkObjects?.filter { valid.contains($0) }
    }
    @discardableResult mutating func renewObjectIDs() -> [UUID: UUID] {
        var map: [UUID: UUID] = [:]
        for i in texts.indices { let old = texts[i].id; texts[i].id = UUID(); map[old] = texts[i].id }
        for i in images.indices { let old = images[i].id; images[i].id = UUID(); map[old] = images[i].id }
        if var values = shapes { for i in values.indices { let old = values[i].id; values[i].id = UUID(); map[old] = values[i].id }; shapes = values }
        if var values = tapes { for i in values.indices { let old = values[i].id; values[i].id = UUID(); map[old] = values[i].id }; tapes = values }
        objectOrder = objectOrder.map { $0.compactMap { map[$0] } }
        lockedObjects = lockedObjects.map { $0.compactMap { map[$0] } }
        aboveInkObjects = aboveInkObjects.map { $0.compactMap { map[$0] } }
        return map
    }
}
