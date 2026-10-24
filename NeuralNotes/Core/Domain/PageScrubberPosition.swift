import Foundation

/// Zero-based page positions. Scrubbing previews a number without opening pages.
public enum PageScrubberPosition {
    public static func index(fraction: Double, count: Int) -> Int? {
        guard count > 0, fraction.isFinite else { return nil }
        let unit = min(1, max(0, fraction))
        return Int((unit * Double(count - 1)).rounded())
    }

    public static func fraction(index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        return Double(min(count - 1, max(0, index))) / Double(count - 1)
    }

    public static func pageNumber(_ text: String, count: Int) -> Int? {
        guard let number = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              number > 0, number <= count else { return nil }
        return number - 1
    }
}
