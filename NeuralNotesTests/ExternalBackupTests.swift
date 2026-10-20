import XCTest
@testable import NeuralNotes

final class ExternalBackupTests: XCTestCase {
    func testExternalRotationKeepsFiveCopiesAndOtherDocumentsAndDoesNotRotateOnFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let document = UUID(), other = UUID()
        let otherDirectory = target.appendingPathComponent("NeuralNotesBackups/\(other)")
        try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)
        let preserved = otherDirectory.appendingPathComponent("keep.nnbackup"); try Data([42]).write(to: preserved)
        var latest: URL?
        for i in 0..<7 {
            let file = source.appendingPathComponent("backup-\(i).nnbackup"); try Data([UInt8(i)]).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(i))], ofItemAtPath: file.path)
            latest = try ExternalBackupWriter.write(file, documentID: document, folder: target)
        }
        let directory = target.appendingPathComponent("NeuralNotesBackups/\(document)")
        let copies = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(copies.count, 5); XCTAssertTrue(copies.contains(try XCTUnwrap(latest)))
        XCTAssertEqual(try Data(contentsOf: preserved), Data([42]))
        let missing = source.appendingPathComponent("backup-missing.nnbackup")
        XCTAssertThrowsError(try ExternalBackupWriter.write(missing, documentID: document, folder: target))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 5)
    }
    func testExternalBackupRejectsSymlinkDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside"); try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("NeuralNotesBackups"), withDestinationURL: outside)
        let source = root.appendingPathComponent("backup-fixture.nnbackup"); try Data([1]).write(to: source)
        XCTAssertThrowsError(try ExternalBackupWriter.write(source, documentID: UUID(), folder: root))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
}
