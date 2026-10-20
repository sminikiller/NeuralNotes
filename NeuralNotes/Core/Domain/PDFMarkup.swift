import Foundation

public enum PDFMarkupKind: String, Codable, Sendable { case highlight, underline }
public struct PDFMarkup: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var kind: PDFMarkupKind
    public var x: Double, y: Double, width: Double, height: Double
    public var text: String
    public init(kind: PDFMarkupKind, x: Double, y: Double, width: Double, height: Double, text: String) {
        self.kind = kind; self.x = x; self.y = y; self.width = width; self.height = height; self.text = text
    }
    public var isValid: Bool { [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
}
