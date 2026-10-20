import SwiftUI

struct SearchResultText: View {
    let text: String
    let query: String
    private var highlighted: AttributedString {
        let snippet: String
        if !query.isEmpty, let match = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: .current) {
            let start = text.index(match.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(match.upperBound, offsetBy: 180, limitedBy: text.endIndex) ?? text.endIndex
            snippet = (start == text.startIndex ? "" : "…") + text[start..<end] + (end == text.endIndex ? "" : "…")
        } else { snippet = String(text.prefix(260)) }
        var value = AttributedString(snippet)
        if !query.isEmpty, let range = value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: .current) {
            value[range].backgroundColor = .yellow.opacity(0.7); value[range].foregroundColor = .black
        }; return value
    }
    var body: some View { Text(highlighted).lineLimit(4).foregroundStyle(.primary) }
}
