import UIKit
import CryptoKit

/// Script metrics are stored in a standard ignorable RTF group, alongside the
/// ordinary font and baseline attributes used by UIKit and PDF export. Older
/// readers ignore the group and render the same text. This avoids inferring a
/// base font from a legacy baseline offset, which can enlarge old notes.
@MainActor
enum RichTextScript {
    enum Kind: Int, Codable { case normal, superscript, subscriptText }
    private static let baseKey = NSAttributedString.Key("NeuralNotes.ScriptBaseFontSize")
    private static let kindKey = NSAttributedString.Key("NeuralNotes.ScriptKind")
    private static let prefix = Data("{\\*\\nnscript ".utf8)
    private struct Run: Codable { let location: Int, length: Int, base: Double; let kind: Kind }
    private struct Metadata: Codable { let version: Int, digest: String; let runs: [Run] }
    static func attributes(_ attributes: [NSAttributedString.Key: Any], applying kind: Kind) -> [NSAttributedString.Key: Any] {
        var result = attributes
        let font = attributes[.font] as? UIFont ?? .systemFont(ofSize: 18)
        let recorded = (attributes[baseKey] as? NSNumber)?.doubleValue
        let base = recorded.flatMap { $0.isFinite && (1...500).contains($0) ? $0 : nil } ?? Double(font.pointSize)
        result[.font] = font.withSize(kind == .normal ? base : base * 0.7)
        if kind == .normal {
            result.removeValue(forKey: baseKey); result.removeValue(forKey: kindKey); result.removeValue(forKey: .baselineOffset)
        } else {
            result[.baselineOffset] = base * (kind == .superscript ? 0.33 : -0.2)
            result[baseKey] = base; result[kindKey] = kind.rawValue
        }
        return result
    }
    static func kind(in attributes: [NSAttributedString.Key: Any]) -> Kind {
        (attributes[kindKey] as? NSNumber).flatMap { Kind(rawValue: $0.intValue) } ?? .normal
    }
    private static func digest(_ string: String) -> String { SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func appendMetadata(to rtf: Data, value: NSAttributedString) -> Data {
        var runs: [Run] = []
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attrs, range, _ in
            let kind = kind(in: attrs)
            if kind != .normal, let base = attrs[baseKey] as? NSNumber, base.doubleValue.isFinite, (1...500).contains(base.doubleValue) {
                runs.append(Run(location: range.location, length: range.length, base: base.doubleValue, kind: kind))
            }
        }
        guard !runs.isEmpty, runs.count <= 20_000,
              let payload = try? JSONEncoder().encode(Metadata(version: 1, digest: digest(value.string), runs: runs)),
              payload.count <= 1024 * 1024, let closing = rtf.lastIndex(of: 125) else { return rtf }
        let group = prefix + Data(payload.base64EncodedString().utf8) + Data("}".utf8)
        // The complete RTF must still fit the reader's limit. Keep the standard
        // font/baseline RTF if optional exact-base metadata would exceed it.
        guard rtf.count <= 2 * 1024 * 1024 - group.count else { return rtf }
        var result = rtf
        result.insert(contentsOf: group, at: closing)
        return result
    }
    static func restoreMetadata(in value: NSAttributedString, from rtf: Data) -> NSAttributedString {
        guard rtf.count <= 2 * 1024 * 1024, let start = rtf.range(of: prefix, options: .backwards),
              let end = rtf[start.upperBound...].firstIndex(of: 125), end - start.upperBound <= 1400_000,
              let payload = Data(base64Encoded: rtf[start.upperBound..<end]),
              let metadata = try? JSONDecoder().decode(Metadata.self, from: payload), metadata.version == 1,
              metadata.digest == digest(value.string), metadata.runs.count <= 20_000 else { return value }
        let restored = NSMutableAttributedString(attributedString: value)
        var previousEnd = 0
        for run in metadata.runs {
            guard run.kind != .normal, run.location >= previousEnd, run.length > 0, run.location <= value.length,
                  run.length <= value.length - run.location, run.base.isFinite, (1...500).contains(run.base) else { return value }
            let range = NSRange(location: run.location, length: run.length)
            var valid = true
            value.enumerateAttributes(in: range) { attrs, _, _ in
                let font = attrs[.font] as? UIFont
                let baseline = (attrs[.baselineOffset] as? NSNumber)?.doubleValue ?? 0
                if abs(Double(font?.pointSize ?? 0) - run.base * 0.7) > 0.75 || abs(baseline - run.base * (run.kind == .superscript ? 0.33 : -0.2)) > 0.75 { valid = false }
            }
            guard valid else { return value }
            restored.addAttributes([baseKey: run.base, kindKey: run.kind.rawValue], range: range)
            previousEnd = NSMaxRange(range)
        }
        return restored
    }
}
