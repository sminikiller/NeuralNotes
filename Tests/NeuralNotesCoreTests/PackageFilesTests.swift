import XCTest
@testable import NeuralNotesCore

final class PackageFilesTests: XCTestCase {
    private func fixture() throws -> (URL, NativeDocumentStore, DocumentManifest, Notebook) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Archivio con spazi è-\(UUID())", isDirectory: true)
        let store = try NativeDocumentStore(root: root.appendingPathComponent("Library", isDirectory: true))
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let metadata = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Fisica",
            createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
        return (root, store, manifest, metadata)
    }

    func testRelativeNamesAndBinaryBackupWithBothDirectoryURLForms() throws {
        let (root, store, manifest, metadata) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = store.packageURL(for: manifest.documentID)
        let nested = package.appendingPathComponent("audio/import-one/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data([0, 1, 127, 255]).write(to: nested.appendingPathComponent("lezione è.caf"))
        for isDirectory in [false, true] {
            let variant = URL(fileURLWithPath: package.path, isDirectory: isDirectory)
            let files = try PackageFiles.list(in: variant)
            XCTAssertEqual(files.map(\.path), ["audio/import-one/nested/lezione è.caf", "manifest.json"])
            let archive = root.appendingPathComponent("Test-\(isDirectory).nnbackup")
            try NativeArchive.write(package: variant, metadata: metadata, to: archive)
            let extracted = root.appendingPathComponent("Extracted-\(isDirectory).nnbook", isDirectory: true)
            try NativeArchive.extract(from: archive, to: extracted)
            XCTAssertEqual(try Data(contentsOf: extracted.appendingPathComponent("audio/import-one/nested/lezione è.caf")), Data([0, 1, 127, 255]))
            XCTAssertEqual(try NativePackageInspector.inspect(extracted).manifest.documentID, manifest.documentID)
        }
    }

    func testDarwinAliasesProduceTheSameArchiveEntryNames() throws {
        let (root, store, manifest, metadata) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = store.packageURL(for: manifest.documentID)
        let path = package.standardizedFileURL.resolvingSymlinksInPath().path
        let alias: String
        if path.hasPrefix("/private/var/") { alias = String(path.dropFirst("/private".count)) }
        else if path.hasPrefix("/var/") { alias = "/private" + path }
        else { throw XCTSkip("Host does not use Darwin /private/var aliases") }
        guard FileManager.default.fileExists(atPath: alias) else { throw XCTSkip("Alias unavailable on this host") }
        let aliased = URL(fileURLWithPath: alias, isDirectory: true)
        XCTAssertEqual(try PackageFiles.list(in: package).map(\.path), try PackageFiles.list(in: aliased).map(\.path))
        let archive = root.appendingPathComponent("Alias.nnbackup")
        try NativeArchive.write(package: aliased, metadata: metadata, to: archive)
        let copy = root.appendingPathComponent("Alias.nnbook", isDirectory: true)
        try NativeArchive.extract(from: archive, to: copy)
        XCTAssertEqual(try NativePackageInspector.inspect(copy).manifest.pageIDs, manifest.pageIDs)
    }

    func testFilesystemSidecarsAreExcludedWithoutRemovingOriginals() throws {
        let (root, store, manifest, metadata) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = store.packageURL(for: manifest.documentID)
        let sidecars = [".DS_Store", "._manifest.json", "images/._photo.png"]
        for name in sidecars { try Data([42]).write(to: package.appendingPathComponent(name)) }
        let archive = root.appendingPathComponent("Sidecars.nnbackup")
        try NativeArchive.write(package: package, metadata: metadata, to: archive)
        let output = root.appendingPathComponent("Sidecars.nnbook", isDirectory: true)
        try NativeArchive.extract(from: archive, to: output)
        for name in sidecars {
            XCTAssertTrue(FileManager.default.fileExists(atPath: package.appendingPathComponent(name).path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent(name).path))
        }
        XCTAssertEqual(try NativePackageInspector.inspect(output).metadata?.title, metadata.title)
    }

    func testSymlinksStillFailBeforeExportCreatesAnArchive() throws {
        let (root, store, manifest, metadata) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = store.packageURL(for: manifest.documentID)
        let outside = root.appendingPathComponent("Outside")
        try Data([42]).write(to: outside)
        try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("audio/link"), withDestinationURL: outside)
        let archive = root.appendingPathComponent("Bad.nnbackup")
        XCTAssertThrowsError(try NativeArchive.write(package: package, metadata: metadata, to: archive))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
        XCTAssertEqual(try Data(contentsOf: outside), Data([42]))
    }

    func testReaderAcceptsIndependentCRC32ReferenceVector() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Standard CRC-32/ISO-HDLC check value for ASCII "123456789".
        let header = Data("{\"version\":1,\"entries\":[{\"path\":\"manifest.json\",\"size\":9,\"checksum\":3421780262}]}".utf8)
        var bytes = Data("NNBOOK01".utf8)
        let length = UInt64(header.count)
        bytes.append(contentsOf: (0..<8).map { UInt8(truncatingIfNeeded: length >> ($0 * 8)) })
        bytes.append(header); bytes.append(Data("123456789".utf8))
        let archive = root.appendingPathComponent("Reference.nnbackup"), output = root.appendingPathComponent("Reference.nnbook")
        try bytes.write(to: archive)
        try NativeArchive.extract(from: archive, to: output)
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("manifest.json")), Data("123456789".utf8))
    }
}
