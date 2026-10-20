import Foundation

public extension DocumentWorkspace {
    func saveGlossaryEntry(_ entry: GlossaryEntry) throws {
        guard entry.isValid else { throw LibraryFailure.invalidName }
        var value = try catalog(), entries = value.glossary ?? []
        entries.removeAll { $0.id == entry.id || $0.term.localizedCaseInsensitiveCompare(entry.term) == .orderedSame }
        guard entries.count < 1000 else { throw WorkspaceFailure.oversizedImport }
        entries.append(entry); value.glossary = entries; try write(value, "catalog.json")
    }
    func removeGlossaryEntry(_ id: UUID) throws {
        var value = try catalog(); value.glossary?.removeAll { $0.id == id }; try write(value, "catalog.json")
    }
    func cacheLensAnswer(key: String, artifact: AIArtifact) throws {
        guard key.count == 64, key.allSatisfy(\.isHexDigit), artifact.text.count <= 16000 else { return }
        var value = try catalog(), entries = value.lensCache ?? []
        entries.removeAll { $0.key == key }; entries.append(CachedLensAnswer(key: key, artifact: artifact))
        value.lensCache = Array(entries.suffix(32)); try write(value, "catalog.json")
    }
    func cachedLensAnswer(key: String) throws -> AIArtifact? { try catalog().lensCache?.first(where: { $0.key == key })?.artifact }
    func setOrganization(_ organization: NotebookOrganization) throws {
        guard organization.isValid else { throw LibraryFailure.invalidName }
        var value = try catalog(); value.organization = organization; try write(value, "catalog.json")
    }
}
