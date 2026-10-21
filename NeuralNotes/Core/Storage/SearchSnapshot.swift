import Foundation

/// Rebuildable derived data; never a source of notebook contents or backup data.
struct SearchSnapshot: Codable {
    let format: Int
    let generation: String
    let chunks: [IndexedChunk]
    static func make(pages: [PageSnapshot], catalog: DocumentCatalog, documentID: UUID, generation: String, automaticOCR: [String: AutomaticOCRPage] = [:]) -> Self {
        var chunks: [IndexedChunk] = []
        for page in pages {
            var sources: [(String, SearchContentKind)] = [(page.texts.map(\.text).joined(separator: "\n"), .text), (page.recognizedText, page.pdfFile == nil ? .handwriting : .pdf)]
            if let ocr = automaticOCR[page.id.uuidString], ocr.revision == page.revision { sources.append((ocr.text, .handwriting)) }
            for (text, kind) in sources { for line in text.split(separator: "\n") {
                let value = String(line); var start = value.startIndex
                while start < value.endIndex {
                    let end = value.index(start, offsetBy: 2000, limitedBy: value.endIndex) ?? value.endIndex
                    chunks.append(IndexedChunk(text: String(value[start..<end]), reference: SourceReference(documentID: documentID, pageID: page.id, pageRevision: page.revision), kind: kind))
                    start = end
                }
            } }
        }
        for entry in catalog.glossary ?? [] {
            chunks.append(IndexedChunk(text: entry.term + "\n" + entry.definition, reference: entry.references.first ?? SourceReference(documentID: documentID), kind: .glossary))
        }
        for session in catalog.sessions where session.trashedAt == nil {
            for block in TranscriptText.minutes(session.readableTranscript) {
                chunks.append(IndexedChunk(text: block.text, reference: SourceReference(documentID: documentID, audioSessionID: session.id, seconds: block.start), kind: .audio))
            }
        }
        return Self(format: 2, generation: generation, chunks: chunks)
    }
}
