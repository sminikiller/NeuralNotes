import Foundation

public struct SourceContext: Sendable {
    public let sources: [IndexedChunk]
    public let availableCount: Int
    public let wasTruncated: Bool
    /// Without a query, sample across the whole document/lecture instead of
    /// silently sending just its beginning. References always remain original.
    public static func select(_ chunks: [IndexedChunk], spread: Bool = false,
                              maximumSources: Int = 40, maximumCharacters: Int = 80_000,
                              maximumPerSource: Int = 8000) -> SourceContext {
        let available = chunks.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let budget = max(0, min(80_000, maximumCharacters)), perSource = max(0, min(8000, maximumPerSource))
        let count = min(available.count, max(0, min(40, maximumSources)), budget)
        guard count > 0, perSource > 0 else { return SourceContext(sources: [], availableCount: available.count, wasTruncated: !available.isEmpty) }
        let chosen: [IndexedChunk]
        if spread, count > 1, available.count > count {
            chosen = (0..<count).map { available[$0 * (available.count - 1) / (count - 1)] }
        } else { chosen = Array(available.prefix(count)) }
        // JSON services count UTF-16 code units. Preserve grapheme boundaries
        // while ensuring emoji cannot exceed the server's string limits.
        let capped = chosen.map { prefix($0.text, utf16Limit: perSource) }
        let share = budget / count
        var allocations = capped.map { min($0.utf16.count, share) }
        var remaining = budget - allocations.reduce(0, +)
        for i in allocations.indices where remaining > 0 {
            let extra = min(remaining, capped[i].utf16.count - allocations[i]); allocations[i] += extra; remaining -= extra
        }
        let sources = chosen.indices.map { i in
            IndexedChunk(text: prefix(capped[i], utf16Limit: allocations[i]), reference: chosen[i].reference, kind: chosen[i].kind)
        }
        let truncated = chosen.count < available.count || chosen.indices.contains { sources[$0].text.count < chosen[$0].text.count }
        return SourceContext(sources: sources.filter { !$0.text.isEmpty }, availableCount: available.count, wasTruncated: truncated)
    }
    private static func prefix(_ text: String, utf16Limit: Int) -> String {
        var used = 0, end = text.startIndex
        for character in text {
            let length = String(character).utf16.count
            guard used + length <= utf16Limit else { break }
            used += length; end = text.index(after: end)
        }
        return String(text[..<end])
    }
}
