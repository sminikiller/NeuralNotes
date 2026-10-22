import XCTest
@testable import NeuralNotesCore

final class CRC32Tests: XCTestCase {
    /// Bit by bit reference: the archive format must keep exactly these values.
    private func reference(_ bytes: [UInt8]) -> UInt32 {
        var crc = UInt32.max
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
        }
        return crc ^ UInt32.max
    }

    func testKnownVectorsAndEmptyInput() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(CRC32.checksum(Data()), 0)
        XCTAssertEqual(CRC32.checksum(Data("The quick brown fox jumps over the lazy dog".utf8)), 0x414F_A339)
    }

    func testSlicedAndChunkedChecksumsMatchTheReferenceAtEveryLengthAndOffset() {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<4096).map { _ in UInt8.random(in: 0...255, using: &generator) }
        for length in [0, 1, 7, 8, 9, 15, 16, 17, 63, 64, 65, 255, 1000, 4093] {
            for offset in [0, 1, 3] {
                let slice = Array(bytes[offset..<(offset + length)])
                XCTAssertEqual(CRC32.checksum(Data(slice)), reference(slice), "length \(length) offset \(offset)")
                let data = Data(bytes)[offset..<(offset + length)]
                XCTAssertEqual(CRC32.checksum(data), reference(slice), "Data slice \(length) \(offset)")
            }
        }
        var running = UInt32.max
        for start in stride(from: 0, to: bytes.count, by: 333) { running = CRC32.update(running, Data(bytes[start..<min(bytes.count, start + 333)])) }
        XCTAssertEqual(running ^ UInt32.max, reference(bytes))
    }

    func testArchiveOfAnUnchangedLargeFileUsesTheSameChecksumAgain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("big.bin"), payload = Data((0..<(3 * 1024 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try payload.write(to: file)
        let values = try file.resourceValues(forKeys: [.contentModificationDateKey])
        let start = Date(); let first = CRC32.checksum(payload)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "3 MB must not take seconds even in debug builds")
        ArchiveChecksumCache.shared.store(first, path: file.path, size: UInt64(payload.count), modified: values.contentModificationDate)
        XCTAssertEqual(ArchiveChecksumCache.shared.checksum(path: file.path, size: UInt64(payload.count), modified: values.contentModificationDate), first)
        XCTAssertNil(ArchiveChecksumCache.shared.checksum(path: file.path, size: UInt64(payload.count) + 1, modified: values.contentModificationDate))
        XCTAssertNil(ArchiveChecksumCache.shared.checksum(path: file.path, size: UInt64(payload.count), modified: nil))
    }

    func testChecksumTableSurvivesARestartThroughItsFile() throws {
        let table = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("checksums.json")
        defer { try? FileManager.default.removeItem(at: table.deletingLastPathComponent()) }
        let modified = Date(timeIntervalSinceReferenceDate: 812_345_678.123_456_7)
        let first = ArchiveChecksumCache(file: table)
        first.store(0xCBF4_3926, path: "/package/attachments/a.pdf", size: 9, modified: modified); first.persist()
        let restarted = ArchiveChecksumCache(file: table)
        XCTAssertEqual(restarted.checksum(path: "/package/attachments/a.pdf", size: 9, modified: modified), 0xCBF4_3926)
        XCTAssertNil(restarted.checksum(path: "/package/attachments/a.pdf", size: 9, modified: modified.addingTimeInterval(1)))
        try Data("rotto".utf8).write(to: table)
        XCTAssertNil(ArchiveChecksumCache(file: table).checksum(path: "/package/attachments/a.pdf", size: 9, modified: modified))
    }
}
