import Foundation

public enum PDFMarkupKind: String, Codable, Sendable {
    case highlight, underline
    public init(from decoder: Decoder) throws { self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .highlight }
}
public struct PDFMarkup: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var kind: PDFMarkupKind
    public var x: Double, y: Double, width: Double, height: Double
    public var text: String
    public var wordHighlight: Bool?
    public var color: InkColor?
    public var opacity: Double?
    public init(kind: PDFMarkupKind, x: Double, y: Double, width: Double, height: Double, text: String) {
        self.kind = kind; self.x = x; self.y = y; self.width = width; self.height = height; self.text = text
    }
    public var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0 && color?.isValid != false &&
        opacity.map { $0.isFinite && (0...1).contains($0) } != false &&
        (wordHighlight != true || (kind == .highlight && width <= 20000 && height <= 20000 && abs(x) <= 1_000_000 && abs(y) <= 1_000_000 && text.count <= 100_000))
    }
}
