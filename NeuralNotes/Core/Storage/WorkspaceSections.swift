import Foundation

public extension DocumentWorkspace {
    func saveSection(_ input: NotebookSection) throws {
        var section = input; section.title = try LibraryName.validated(input.title)
        var catalog = try catalog(), sections = catalog.sections ?? []
        // Assignment is a separate operation: a rename cannot overwrite pages
        // assigned by an earlier action while its form was open.
        if let index = sections.firstIndex(where: { $0.id == input.id }) {
            section.pageIDs = sections[index].pageIDs; sections[index] = section
        } else {
            guard input.pageIDs.isEmpty else { throw LibraryFailure.corruptDocument }
            sections.append(section)
        }
        try NotebookSections.validate(sections); catalog.sections = sections
        try write(catalog, "catalog.json")
    }

    func assignPages(_ pageIDs: Set<UUID>, toSection sectionID: UUID?) throws {
        let live = Set(try manifest().pageIDs)
        guard !pageIDs.isEmpty, pageIDs.isSubset(of: live) else { throw LibraryFailure.missingItem }
        var catalog = try catalog(), sections = catalog.sections ?? []
        if let sectionID, !sections.contains(where: { $0.id == sectionID }) { throw LibraryFailure.missingItem }
        for i in sections.indices {
            sections[i].pageIDs.removeAll { pageIDs.contains($0) }
            if sections[i].id == sectionID { sections[i].pageIDs += pageIDs.sorted { $0.uuidString < $1.uuidString } }
        }
        try NotebookSections.validate(sections); catalog.sections = sections
        try write(catalog, "catalog.json")
    }

    func removeSection(_ sectionID: UUID) throws {
        var catalog = try catalog(), sections = catalog.sections ?? []
        guard let section = sections.first(where: { $0.id == sectionID }) else { throw LibraryFailure.missingItem }
        let live = Set(try manifest().pageIDs)
        guard !sections.contains(where: { $0.parentID == sectionID }), live.isDisjoint(with: section.pageIDs) else { throw LibraryFailure.nonEmptyFolder }
        sections.removeAll { $0.id == sectionID }; catalog.sections = sections
        try write(catalog, "catalog.json")
    }
}
