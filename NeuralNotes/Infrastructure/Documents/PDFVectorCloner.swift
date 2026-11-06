import Foundation
import CoreGraphics

/// Copies public CGPDF objects, including font maps and encoded image data.
/// It never parses PDF bytes or uses a private Core Graphics property.
final class PDFVectorCloner {
    private final class Entries { var values: [(Data, CGPDFObjectRef)] = [] }
    private let archive: PDFVectorArchive
    private let normalizeOwnedGroups: Bool
    private var references: [OpaquePointer: Int] = [:]
    private var depth = 0
    init(archive: PDFVectorArchive, normalizeOwnedGroups: Bool) {
        self.archive = archive; self.normalizeOwnedGroups = normalizeOwnedGroups
    }
    func value(_ object: CGPDFObjectRef) throws -> String {
        try Task.checkCancellation()
        guard depth < 128 else { throw CocoaError(.fileReadCorruptFile) }
        depth += 1; defer { depth -= 1 }
        switch CGPDFObjectGetType(object) {
        case .null: return "null"
        case .boolean:
            var value: CGPDFBoolean = 0; guard CGPDFObjectGetValue(object, .boolean, &value) else { throw invalid }
            return value == 0 ? "false" : "true"
        case .integer:
            var value: CGPDFInteger = 0; guard CGPDFObjectGetValue(object, .integer, &value) else { throw invalid }
            return String(value)
        case .real:
            var value: CGPDFReal = 0; guard CGPDFObjectGetValue(object, .real, &value), value.isFinite else { throw invalid }
            return PDFVectorArchive.number(Double(value))
        case .name:
            var name: UnsafePointer<CChar>?
            guard CGPDFObjectGetValue(object, .name, &name), let name else { throw invalid }
            return Self.name(Self.bytes(name))
        case .string:
            var string: CGPDFStringRef?
            guard CGPDFObjectGetValue(object, .string, &string), let string,
                  let bytes = CGPDFStringGetBytePtr(string) else { throw invalid }
            let data = Data(bytes: bytes, count: CGPDFStringGetLength(string))
            return "<" + data.map { String(format: "%02x", $0) }.joined() + ">"
        case .array:
            var array: CGPDFArrayRef?
            guard CGPDFObjectGetValue(object, .array, &array), let array else { throw invalid }
            if let known = references[array] { return "\(known) 0 R" }
            let id = try archive.reserve(); references[array] = id
            var entries: [String] = []
            for index in 0..<CGPDFArrayGetCount(array) {
                var item: CGPDFObjectRef?
                guard CGPDFArrayGetObject(array, index, &item), let item else { throw invalid }
                entries.append(try value(item))
            }
            try archive.writeObject(id, body: "[" + entries.joined(separator: " ") + "]")
            return "\(id) 0 R"
        case .dictionary:
            var dictionary: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(object, .dictionary, &dictionary), let dictionary else { throw invalid }
            if let known = references[dictionary] { return "\(known) 0 R" }
            let id = try archive.reserve(); references[dictionary] = id
            try archive.writeObject(id, body: "<< " + entries(dictionary) + " >>")
            return "\(id) 0 R"
        case .stream:
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream else { throw invalid }
            if let known = references[stream] { return "\(known) 0 R" }
            var format = CGPDFDataFormat.raw
            guard let copied = CGPDFStreamCopyData(stream, &format), CFDataGetLength(copied) <= 128 * 1024 * 1024 else { throw invalid }
            let skipped: Set<String> = format == .raw ? ["Length", "Filter", "DecodeParms", "F", "FFilter", "FDecodeParms"] : ["Length"]
            let body = try entries(CGPDFStreamGetDictionary(stream), skipping: skipped)
            let id = try archive.stream(entries: body, data: copied as Data); references[stream] = id
            return "\(id) 0 R"
        @unknown default: throw invalid
        }
    }
    private func entries(_ dictionary: CGPDFDictionaryRef, skipping: Set<String> = []) throws -> String {
        let entries = Entries()
        CGPDFDictionaryApplyFunction(dictionary, { key, object, info in
            guard let info else { return }
            Unmanaged<Entries>.fromOpaque(info).takeUnretainedValue().values.append((PDFVectorCloner.bytes(key), object))
        }, Unmanaged.passUnretained(entries).toOpaque())
        var kind: UnsafePointer<CChar>?
        let group = normalizeOwnedGroups && CGPDFDictionaryGetName(dictionary, "S", &kind) && kind.map { String(cString: $0) == "Transparency" } == true
        var result: [String] = []
        for (key, object) in entries.values.sorted(by: { $0.0.lexicographicallyPrecedes($1.0) }) {
            let label = String(decoding: key, as: UTF8.self)
            if skipping.contains(label) { continue }
            let copied = group && label == "CS" ? "\(archive.colorSpaceID) 0 R" : try value(object)
            result.append(Self.name(key) + " " + copied)
        }
        if group && !entries.values.contains(where: { $0.0 == Data("CS".utf8) }) { result.append("/CS \(archive.colorSpaceID) 0 R") }
        return result.joined(separator: " ")
    }
    static func pageContent(_ dictionary: CGPDFDictionaryRef) throws -> Data {
        var object: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(dictionary, "Contents", &object), let object else { return Data() }
        func decoded(_ object: CGPDFObjectRef) throws -> Data {
            var stream: CGPDFStreamRef?, format = CGPDFDataFormat.raw
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let data = CGPDFStreamCopyData(stream, &format), format == .raw,
                  CFDataGetLength(data) <= 128 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            return data as Data
        }
        if CGPDFObjectGetType(object) == .stream { return try decoded(object) }
        var array: CGPDFArrayRef?
        guard CGPDFObjectGetValue(object, .array, &array), let array else { throw CocoaError(.fileReadCorruptFile) }
        var result = Data()
        for index in 0..<CGPDFArrayGetCount(array) {
            var item: CGPDFObjectRef?
            guard CGPDFArrayGetObject(array, index, &item), let item else { throw CocoaError(.fileReadCorruptFile) }
            let data = try decoded(item)
            guard result.count + data.count <= 128 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            result.append(data); result.append(10)
        }
        return result
    }
    private static func bytes(_ pointer: UnsafePointer<CChar>) -> Data {
        var size = 0; while pointer[size] != 0 { size += 1 }
        return Data(bytes: pointer, count: size)
    }
    private static func name(_ data: Data) -> String {
        "/" + data.map { byte in
            if byte > 32 && byte < 127 && ![35, 37, 40, 41, 47, 60, 62, 91, 93, 123, 125].contains(byte) { return String(UnicodeScalar(byte)) }
            return String(format: "#%02X", byte)
        }.joined()
    }
    private var invalid: CocoaError { CocoaError(.fileReadCorruptFile) }
}
