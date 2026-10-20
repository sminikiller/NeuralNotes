import Foundation
import XCTest
@testable import NeuralNotesCore

final class NativeDocumentStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    func testManifestSurvivesNewStoreInstance() throws {
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID(),
                                        createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try NativeDocumentStore(root: root).create(manifest)
        let reopened = try NativeDocumentStore(root: root)
        XCTAssertEqual(try reopened.read(documentID: manifest.documentID, notebookID: manifest.notebookID), manifest)
        for name in ["pages", "drawings", "images", "audio", "attachments"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: reopened.packageURL(for: manifest.documentID)
                .appendingPathComponent(name).path))
        }
    }

    func testCreationNeverOverwritesExistingDocument() throws {
        let store = try NativeDocumentStore(root: root)
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        XCTAssertThrowsError(try store.create(manifest))
        XCTAssertEqual(try store.read(documentID: manifest.documentID, notebookID: manifest.notebookID).notebookID,
                       manifest.notebookID)
    }

    func testWrongIdentityAndMalformedManifestAreRejected() throws {
        let store = try NativeDocumentStore(root: root)
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        XCTAssertThrowsError(try store.read(documentID: manifest.documentID, notebookID: UUID()))
        try Data("{truncated".utf8).write(to: store.packageURL(for: manifest.documentID)
            .appendingPathComponent("manifest.json"), options: .atomic)
        XCTAssertThrowsError(try store.read(documentID: manifest.documentID, notebookID: manifest.notebookID))
    }

    func testFutureSchemaIsRejectedBeforeDecodingOtherFields() throws {
        let store = try NativeDocumentStore(root: root)
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let url = store.packageURL(for: manifest.documentID).appendingPathComponent("manifest.json")
        try Data("{\"schemaVersion\":99}".utf8).write(to: url, options: .atomic)
        XCTAssertThrowsError(try store.read(documentID: manifest.documentID, notebookID: manifest.notebookID)) { error in
            guard case LibraryFailure.unsupportedVersion(99) = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testOrphanRecoveryPreservesOriginalFiles() throws {
        let store = try NativeDocumentStore(root: root)
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        XCTAssertEqual(try store.unreferencedPackages(referencedDocumentIDs: []).count, 1)
        XCTAssertEqual(try store.unreferencedPackages(referencedDocumentIDs: [manifest.documentID]).count, 0)
        XCTAssertNoThrow(try store.read(documentID: manifest.documentID, notebookID: manifest.notebookID))
    }

    func testDuplicatePageIDsAreRejected() throws {
        let store = try NativeDocumentStore(root: root)
        let page = UUID()
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID(), pageIDs: [page, page])
        try store.create(manifest)
        XCTAssertThrowsError(try store.read(documentID: manifest.documentID, notebookID: manifest.notebookID))
    }
}
