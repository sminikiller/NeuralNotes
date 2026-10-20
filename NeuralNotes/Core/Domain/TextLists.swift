import Foundation

public enum TextLists {
    public struct Continuation: Equatable, Sendable { public let prefix: String; public let consumed: Int; public let empty: Bool }
    public static func continuation(of line: String) -> Continuation? {
        guard let expression = try? NSRegularExpression(pattern: "^([ \\t]*)([-•]|[0-9]{1,6}[.)]|[☐☑])[ \\t]+"),
              let match = expression.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) else { return nil }
        let source = line as NSString, indent = source.substring(with: match.range(at: 1)), token = source.substring(with: match.range(at: 2))
        let next: String
        if let number = Int(token.dropLast()) { next = "\(min(999999, number + 1))\(token.suffix(1)) " }
        else { next = (token == "☑" ? "☐" : token) + " " }
        return Continuation(prefix: indent + next, consumed: match.range.length,
            empty: source.substring(from: match.range.length).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
