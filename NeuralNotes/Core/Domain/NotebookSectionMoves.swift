import Foundation

public extension NotebookSections {
    /// Move a complete subtree, preserving all page assignments. `before` is a
    /// sibling at the destination; nil appends after its last sibling subtree.
    static func moving(_ id: UUID, to parent: UUID?, before: UUID? = nil, in sections: [NotebookSection]) throws -> [NotebookSection] {
        try validate(sections)
        let rows = outline(sections)
        guard let start = rows.firstIndex(where: { $0.section.id == id }) else { throw LibraryFailure.missingItem }
        var subtree = [rows[start].section]
        for row in rows.dropFirst(start + 1) {
            if row.depth <= rows[start].depth { break }; subtree.append(row.section)
        }
        let movingIDs = Set(subtree.map(\.id))
        guard parent.map({ candidate in !movingIDs.contains(candidate) && sections.contains { $0.id == candidate } }) != false else { throw LibraryFailure.corruptDocument }
        guard before.map({ candidate in !movingIDs.contains(candidate) && sections.contains { $0.id == candidate && $0.parentID == parent } }) != false else { throw LibraryFailure.corruptDocument }
        var result = rows.map(\.section).filter { !movingIDs.contains($0.id) }
        subtree[0].parentID = parent
        let insertion: Int
        if let before { insertion = result.firstIndex { $0.id == before }! }
        else if let parent, let at = result.firstIndex(where: { $0.id == parent }) {
            let visible = outline(result), depth = visible.first { $0.section.id == parent }!.depth
            var end = at + 1
            while end < visible.count && visible[end].depth > depth { end += 1 }
            insertion = end
        } else { insertion = result.count }
        result.insert(contentsOf: subtree, at: insertion)
        try validate(result); return result
    }
    static func indenting(_ id: UUID, in sections: [NotebookSection]) throws -> [NotebookSection] {
        guard let section = sections.first(where: { $0.id == id }) else { throw LibraryFailure.missingItem }
        let siblings = outline(sections).map(\.section).filter { $0.parentID == section.parentID }
        guard let at = siblings.firstIndex(where: { $0.id == id }), at > 0 else { return sections }
        return try moving(id, to: siblings[at - 1].id, in: sections)
    }
    static func outdenting(_ id: UUID, in sections: [NotebookSection]) throws -> [NotebookSection] {
        guard let section = sections.first(where: { $0.id == id }) else { throw LibraryFailure.missingItem }
        guard let parentID = section.parentID, let parent = sections.first(where: { $0.id == parentID }) else { return sections }
        let siblings = outline(sections).map(\.section).filter { $0.parentID == parent.parentID }
        guard let at = siblings.firstIndex(where: { $0.id == parentID }) else { throw LibraryFailure.corruptDocument }
        return try moving(id, to: parent.parentID, before: at + 1 < siblings.count ? siblings[at + 1].id : nil, in: sections)
    }
    static func visibleOutline(_ sections: [NotebookSection], collapsed: Set<UUID>) -> [(section: NotebookSection, depth: Int)] {
        var hiddenBelow: Int?
        return outline(sections).filter { row in
            if let hiddenBelow, row.depth > hiddenBelow { return false }
            hiddenBelow = collapsed.contains(row.section.id) ? row.depth : nil
            return true
        }
    }
}
