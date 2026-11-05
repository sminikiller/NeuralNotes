import Foundation

/// Editable provenance of a merge. Native strokes stay in the owner's single
/// PKDrawing; these small references preserve the old content stages and group
/// opacity, which concatenating paths or multiplying each object's alpha loses.
/// New ink/objects not listed here form a normal final content stage.
public struct LayerComposition: Codable, Equatable, Sendable {
    public var opacity: Double
    public var children: [LayerComposition]?
    public var strokes: [String]?
    public var objects: [UUID]?
    public var markups: [UUID]?
    public init(opacity: Double = 1, children: [LayerComposition]? = nil,
                strokes: [String]? = nil, objects: [UUID]? = nil, markups: [UUID]? = nil) {
        self.opacity = opacity; self.children = children; self.strokes = strokes; self.objects = objects; self.markups = markups
    }
    public var strokeReferences: Set<String> { children.map { Set($0.flatMap { $0.strokeReferences }) } ?? Set(strokes ?? []) }
    public var objectReferences: Set<UUID> { children.map { Set($0.flatMap { $0.objectReferences }) } ?? Set(objects ?? []) }
    public var markupReferences: Set<UUID> { children.map { Set($0.flatMap { $0.markupReferences }) } ?? Set(markups ?? []) }

    public func validate(ownedObjects: Set<UUID>, ownedMarkups: Set<UUID>) throws {
        var nodes = 0, inkCount = 0, ink = Set<String>(), ids = Set<UUID>(), marks = Set<UUID>()
        func visit(_ node: Self, depth: Int) throws {
            nodes += 1
            guard nodes <= 128, depth <= 4, node.opacity.isFinite, (0...1).contains(node.opacity) else { throw LibraryFailure.corruptDocument }
            if let children = node.children {
                guard children.count <= 128, node.strokes == nil, node.objects == nil, node.markups == nil else { throw LibraryFailure.corruptDocument }
                for child in children { try visit(child, depth: depth + 1) }
            } else {
                let strokes = node.strokes ?? [], objects = node.objects ?? [], markups = node.markups ?? []
                inkCount += strokes.count
                guard inkCount <= 200_000, strokes.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }),
                      Set(objects).isSubset(of: ownedObjects), Set(markups).isSubset(of: ownedMarkups) else { throw LibraryFailure.corruptDocument }
                for key in strokes { guard ink.insert(key).inserted else { throw LibraryFailure.corruptDocument } }
                for key in objects { guard ids.insert(key).inserted else { throw LibraryFailure.corruptDocument } }
                for key in markups { guard marks.insert(key).inserted else { throw LibraryFailure.corruptDocument } }
            }
        }
        try visit(self, depth: 0)
    }
    public func remapping(objects objectMap: [UUID: UUID] = [:], markups markupMap: [UUID: UUID] = [:],
                          strokes strokeMap: [String: String] = [:]) -> Self {
        var value = self
        value.children = children?.map { $0.remapping(objects: objectMap, markups: markupMap, strokes: strokeMap) }
        value.objects = objects?.map { objectMap[$0] ?? $0 }; value.markups = markups?.map { markupMap[$0] ?? $0 }
        value.strokes = strokes?.map { strokeMap[$0] ?? $0 }; return value
    }
    public func pruning(objects: Set<UUID>, markups: Set<UUID>, strokes: Set<String>? = nil) -> Self {
        var value = self
        value.children = children?.map { $0.pruning(objects: objects, markups: markups, strokes: strokes) }
        value.objects = self.objects?.filter(objects.contains); value.markups = self.markups?.filter(markups.contains)
        if let strokes { value.strokes = self.strokes?.filter(strokes.contains) }
        return value.normalized
    }
    public func replacingStrokes(old: [String], new: [String], retainedIndices: [Int]) -> Self {
        guard new.count == retainedIndices.count, Set(retainedIndices).count == retainedIndices.count,
              retainedIndices.allSatisfy(old.indices.contains) else { return self }
        let mapping = Dictionary(zip(retainedIndices.map { old[$0] }, new), uniquingKeysWith: { first, _ in first })
        func replace(_ node: Self) -> Self {
            var value = node; value.children = node.children?.map(replace)
            value.strokes = node.strokes?.compactMap { mapping[$0] }; return value
        }
        return replace(self).normalized
    }
    public var normalized: Self {
        guard let children else { return self }
        var values: [Self] = []
        for child in children.map(\.normalized) {
            if let nested = child.children, child.opacity == 1 { values.append(contentsOf: nested) }
            else { values.append(child) }
        }
        if values.count == 1 {
            var single = values[0]; single.opacity *= opacity; return single
        }
        return Self(opacity: opacity, children: values)
    }
    /// Include edits made after a prior merge, without changing older groups.
    public static func capturing(_ existing: Self?, opacity: Double, strokes: [String], objects: [UUID], markups: [UUID]) -> Self {
        let old = existing?.pruning(objects: Set(objects), markups: Set(markups), strokes: Set(strokes))
        let ink = old?.strokeReferences ?? [], ids = old?.objectReferences ?? [], marks = old?.markupReferences ?? []
        let remainder = Self(strokes: strokes.filter { !ink.contains($0) }, objects: objects.filter { !ids.contains($0) }, markups: markups.filter { !marks.contains($0) })
        let hasRemainder = !(remainder.strokes ?? []).isEmpty || !(remainder.objects ?? []).isEmpty || !(remainder.markups ?? []).isEmpty
        var children: [Self] = old.map { [$0] } ?? []
        if hasRemainder || children.isEmpty { children.append(remainder) }
        return Self(opacity: opacity, children: children).normalized
    }
}
