import XCTest
@testable import NeuralNotesCore

final class SelectionSnapshotTests: XCTestCase {
    func testCopiedMediaIsIndependentDeduplicatedAndReleasedWithItsSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("images"), withIntermediateDirectories: true)
        let bytes = Data([1, 2, 3]), source = root.appendingPathComponent("images/one.png"); try bytes.write(to: source)
        var page = PageSnapshot(); page.images = [ImageElement(file: "images/one.png", width: 80, height: 80), ImageElement(file: "images/one.png", width: 100, height: 100)]
        var snapshot: SelectionSnapshot? = try SelectionSnapshot(page: page, drawing: Data([42]), source: root, maximumBytes: 100_000)
        let owned = try XCTUnwrap(snapshot?.package), copied = try XCTUnwrap(snapshot?.page.images.first?.file)
        XCTAssertNotEqual(owned, root); XCTAssertEqual(snapshot?.page.images[1].file, copied)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: owned.appendingPathComponent("images").path).count, 1)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: owned.appendingPathComponent(copied)), bytes)
        XCTAssertEqual(snapshot?.drawing, Data([42])); XCTAssertEqual(page.images[0].file, "images/one.png")
        snapshot = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
    }
    func testOversizeMissingAndEscapingAssetsCannotProduceACuttableSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("images"), withIntermediateDirectories: true)
        let source = root.appendingPathComponent("images/one.png"), bytes = Data(count: 200_000); try bytes.write(to: source)
        var page = PageSnapshot(); page.images = [ImageElement(file: "images/one.png", width: 80, height: 80)]
        XCTAssertThrowsError(try SelectionSnapshot(page: page, drawing: nil, source: root, maximumBytes: 100_000))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        try FileManager.default.removeItem(at: source)
        XCTAssertThrowsError(try SelectionSnapshot(page: page, drawing: nil, source: root, maximumBytes: 300_000))
        page.images[0].file = "../escaped.png"
        XCTAssertThrowsError(try SelectionSnapshot(page: page, drawing: nil, source: root, maximumBytes: 300_000))
    }
}
