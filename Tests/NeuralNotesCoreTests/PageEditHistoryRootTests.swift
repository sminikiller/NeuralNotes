import Foundation
import XCTest
@testable import NeuralNotesCore

final class PageEditHistoryRootTests: XCTestCase {
    func testCleanupOnlyRemovesOldOwnedUUIDDirectoriesAndDoesNotFollowLinks() async throws {
        let manager = FileManager.default, root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let history = root.appendingPathComponent("history"), outside = root.appendingPathComponent("notebooks")
        try manager.createDirectory(at: history, withIntermediateDirectories: true)
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        let notebook = outside.appendingPathComponent("notes.json"); try Data([1, 2, 3]).write(to: notebook)
        let owned = history.appendingPathComponent("edit-\(UUID())")
        try manager.createDirectory(at: owned, withIntermediateDirectories: false)
        try Data([4]).write(to: owned.appendingPathComponent("snapshot"))
        let foreign = history.appendingPathComponent("edit-not-a-uuid")
        try manager.createDirectory(at: foreign, withIntermediateDirectories: false)
        let ordinary = history.appendingPathComponent("edit-\(UUID())"); try Data([5]).write(to: ordinary)
        let link = history.appendingPathComponent("edit-\(UUID())")
        try manager.createSymbolicLink(at: link, withDestinationURL: outside)
        let stale = try PageEditHistoryRoot.orphanCandidates(in: history)
        XCTAssertEqual(stale.map(\.lastPathComponent), [owned.lastPathComponent])
        // A new snapshot created after the startup scan is active, not stale.
        let active = history.appendingPathComponent("edit-\(UUID())")
        try manager.createDirectory(at: active, withIntermediateDirectories: false)
        await Task.detached { PageEditHistoryRoot.discard(stale + [link, outside], in: history) }.value
        XCTAssertFalse(manager.fileExists(atPath: owned.path))
        XCTAssertTrue(manager.fileExists(atPath: active.path)); XCTAssertTrue(manager.fileExists(atPath: foreign.path))
        XCTAssertTrue(manager.fileExists(atPath: ordinary.path)); XCTAssertEqual(try Data(contentsOf: notebook), Data([1, 2, 3]))
        XCTAssertNoThrow(try manager.destinationOfSymbolicLink(atPath: link.path))
    }
    func testInjectedHistoryParentNeverCleansAnotherLiveSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("package")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let parent = root.appendingPathComponent("undo"), page = PageSnapshot(), documentID = UUID()
        let first = try PageEditSnapshotBuilder(documentID: documentID, parent: parent)
        try await first.append(page, drawing: Data([1]), sourcePackage: package)
        let snapshot = try await first.finish()
        let second = try PageEditSnapshotBuilder(documentID: documentID, parent: parent)
        try await second.append(page, drawing: Data([2]), sourcePackage: package)
        let other = try await second.finish()
        XCTAssertEqual(try snapshot.page(page.id), page); XCTAssertEqual(try other.page(page.id), page)
        XCTAssertNotEqual(snapshot.directory, other.directory)
    }
}
