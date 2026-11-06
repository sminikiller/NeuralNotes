import Foundation
import CoreGraphics
import CryptoKit

/// A streaming PDF container for existing vector forms. Quartz fixes its
/// transparency groups to Generic RGB even when an sRGB output intent is set.
/// We assemble pages without repainting those forms, so owned groups can use
/// sRGB while imported paper/PDF groups keep their original color spaces.
final class PDFVectorArchive {
    private let file: FileHandle
    private var position: UInt64 = 0
    private var offsets: [UInt64?] = [nil]
    private var pages: [Int] = []
    private var streamCache: [String: Int] = [:]
    private var closed = false
    private var pagesID = 0
    private(set) var colorSpaceID = 0
    private var profileID = 0

    init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        file = try FileHandle(forWritingTo: url)
        try append(Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37, 0x0A, 0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]))
        pagesID = try reserve()
        guard let profile = CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData() else { throw CocoaError(.fileWriteUnknown) }
        profileID = try stream(entries: "/N 3 /Alternate /DeviceRGB", data: profile as Data)
        colorSpaceID = try object("[/ICCBased \(profileID) 0 R]")
    }
    deinit { try? file.close() }
    func reserve() throws -> Int {
        guard offsets.count < 2_000_000 else { throw CocoaError(.fileWriteUnknown) }
        offsets.append(nil); return offsets.count - 1
    }
    func object(_ body: String) throws -> Int {
        let id = try reserve(); try writeObject(id, body: body); return id
    }
    func writeObject(_ id: Int, body: String) throws {
        try begin(id); try text(body + "\nendobj\n")
    }
    func stream(entries: String, data: Data) throws -> Int {
        // Font programs, ICC profiles and repeated photo streams can be shared
        // across pages. References in entries are part of the key, so masks or
        // resources with different identities can never be accidentally shared.
        let key = entries + ":" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let existing = streamCache[key] { return existing }
        let id = try reserve(); try writeStream(id, entries: entries, data: data)
        streamCache[key] = id; return id
    }
    func writeStream(_ id: Int, entries: String, data: Data) throws {
        try begin(id); try text("<< \(entries) /Length \(data.count) >>\nstream\n")
        try append(data); try text("\nendstream\nendobj\n")
    }
    func pageForm(_ page: CGPDFPage, normalizeOwnedGroups: Bool) throws -> Int {
        let clone = PDFVectorCloner(archive: self, normalizeOwnedGroups: normalizeOwnedGroups)
        guard let dictionary = page.dictionary else { throw CocoaError(.fileReadCorruptFile) }
        var resources: CGPDFObjectRef?
        let resourceText = CGPDFDictionaryGetObject(dictionary, "Resources", &resources) ? try clone.value(resources!) : "<< >>"
        let content = try PDFVectorCloner.pageContent(dictionary)
        let box = page.getBoxRect(.mediaBox)
        let bounds = [box.minX, box.minY, box.maxX, box.maxY].map { Self.number(Double($0)) }.joined(separator: " ")
        return try stream(entries: "/Type /XObject /Subtype /Form /FormType 1 /BBox [\(bounds)] /Resources \(resourceText)", data: content)
    }
    func addPage(width: Double, height: Double, forms: [Int]) throws {
        let content = forms.indices.map { "q /Part\($0) Do Q\n" }.joined()
        let contentID = try stream(entries: "", data: Data(content.utf8))
        let resources = forms.enumerated().map { "/Part\($0.offset) \($0.element) 0 R" }.joined(separator: " ")
        let page = try object("<< /Type /Page /Parent \(pagesID) 0 R /MediaBox [0 0 \(Self.number(width)) \(Self.number(height))] /Resources << /XObject << \(resources) >> >> /Contents \(contentID) 0 R /Group << /S /Transparency /CS \(colorSpaceID) 0 R /I true >> >>")
        pages.append(page)
    }
    func finish() throws {
        let children = pages.map { "\($0) 0 R" }.joined(separator: " ")
        try writeObject(pagesID, body: "<< /Type /Pages /Count \(pages.count) /Kids [\(children)] >>")
        let intent = try object("<< /Type /OutputIntent /S /GTS_PDFX /OutputConditionIdentifier (sRGB IEC61966-2.1) /DestOutputProfile \(profileID) 0 R >>")
        let root = try object("<< /Type /Catalog /Pages \(pagesID) 0 R /OutputIntents [\(intent) 0 R] >>")
        guard offsets.dropFirst().allSatisfy({ $0 != nil }) else { throw CocoaError(.fileWriteUnknown) }
        let crossReference = position
        try text("xref\n0 \(offsets.count)\n0000000000 65535 f \n")
        for offset in offsets.dropFirst() {
            guard let offset, offset < 10_000_000_000 else { throw CocoaError(.fileWriteUnknown) }
            try text(String(format: "%010llu 00000 n \n", offset))
        }
        try text("trailer\n<< /Size \(offsets.count) /Root \(root) 0 R >>\nstartxref\n\(crossReference)\n%%EOF\n")
        try file.synchronize(); try file.close(); closed = true
    }
    private func begin(_ id: Int) throws {
        guard !closed, offsets.indices.contains(id), offsets[id] == nil else { throw CocoaError(.fileWriteUnknown) }
        offsets[id] = position; try text("\(id) 0 obj\n")
    }
    private func text(_ value: String) throws { try append(Data(value.utf8)) }
    private func append(_ data: Data) throws {
        try file.write(contentsOf: data); position += UInt64(data.count)
    }
    static func number(_ value: Double) -> String {
        String(format: "%.15f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
