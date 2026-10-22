import Foundation

struct AutomaticOCRPage: Codable {
    let revision: Int
    let text: String
    /// A PDF text-layer probe is not a completed OCR of a scanned page.
    var pdfTextOnly: Bool? = nil
}
