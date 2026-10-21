import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public struct WebSource: Codable, Equatable, Sendable {
    public let title: String
    public let url: String
    public let endIndex: Int?
    public init(title: String, url: String, endIndex: Int? = nil) { self.title = title; self.url = url; self.endIndex = endIndex }
    public var link: URL? {
        guard url.count <= 4096, let value = URL(string: url), ["https", "http"].contains(value.scheme?.lowercased() ?? ""),
              value.host?.isEmpty == false, value.user == nil, value.password == nil else { return nil }; return value
    }
    public var isValid: Bool { link != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 500 && (endIndex ?? 0) >= 0 }
}
public struct WebResearchRequest: Codable, Sendable {
    public let term: String
    public init(term: String) { self.term = term.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var isValid: Bool { !term.isEmpty && term.utf16.count <= 120 && !term.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) }) }
    public func cacheKey(configuration: AIEngineConfiguration) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var data = Data("/v1/research|".utf8)
        data.append((try? encoder.encode(self)) ?? Data()); data.append(Data(configuration.consentKey.utf8))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
public struct CitedTextRun: Sendable { public let text: String; public let link: URL? }
private struct PositionedCitation { let number: Int; let source: WebSource; let index: String.Index }
public extension AIArtifact {
    func validatedWebResearch() throws -> AIArtifact {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 20_000,
              let webSources, (1...40).contains(webSources.count), webSources.allSatisfy(\.isValid),
              webSources.allSatisfy({ ($0.endIndex ?? 0) <= text.utf16.count }), references.isEmpty else { throw AIWireFailure.response }
        return self
    }
    /// Insert real, clickable source markers at annotation boundaries. The
    /// response itself remains plain text, never untrusted Markdown/HTML links.
    var citedRuns: [CitedTextRun] {
        let sources = Array((webSources ?? []).filter(\.isValid).prefix(40))
        guard !sources.isEmpty else { return [CitedTextRun(text: text, link: nil)] }
        var runs: [CitedTextRun] = [], cursor = text.startIndex
        var entries: [PositionedCitation] = []
        let length: Int = text.utf16.count
        for (offset, source) in sources.enumerated() {
            let end: Int = min(length, max(0, source.endIndex ?? length))
            let range: Range<String.Index>? = Range(NSRange(location: 0, length: end), in: text)
            let boundary = range?.upperBound ?? text.endIndex
            let safe = boundary == text.endIndex || text.indices.contains(boundary)
            entries.append(PositionedCitation(number: offset + 1, source: source, index: safe ? boundary : text.endIndex))
        }
        entries.sort { left, right in
            if left.index == right.index { return left.number < right.number }
            return left.index < right.index
        }
        for entry in entries {
            if cursor < entry.index { runs.append(CitedTextRun(text: String(text[cursor..<entry.index]), link: nil)); cursor = entry.index }
            runs.append(CitedTextRun(text: " [\(entry.number)]", link: entry.source.link))
        }
        if cursor < text.endIndex { runs.append(CitedTextRun(text: String(text[cursor...]), link: nil)) }
        for (i, source) in sources.enumerated() { runs.append(CitedTextRun(text: "\n[\(i + 1)] \(source.title) — \(source.url)", link: source.link)) }
        return runs
    }
}
public extension AIEngineConfiguration {
    var researchURL: URL? {
        guard let lookup = lookupURL, var parts = URLComponents(url: lookup, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = String(parts.path.dropLast("lookup".count)) + "research"; return parts.url
    }
}
