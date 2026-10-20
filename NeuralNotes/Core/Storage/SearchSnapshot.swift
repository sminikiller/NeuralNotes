import Foundation

/// Rebuildable derived data; never a source of notebook contents or backup data.
struct SearchSnapshot: Codable {
    let format: Int
    let generation: String
    let chunks: [IndexedChunk]
    static func make(pages: [PageSnapshot], catalog: DocumentCatalog, documentID: UUID, generation: String) -> Self {
        var chunks: [IndexedChunk] = []
        for page in pages {
            let text = (page.texts.map(\.text) + [page.recognizedText]).joined(separator: "\n")
            for line in text.split(separator: "\n") {
                let value = String(line); var start = value.startIndex
                while start < value.endIndex {
                    let end = value.index(start, offsetBy: 2000, limitedBy: value.endIndex) ?? value.endIndex
                    chunks.append(IndexedChunk(text: String(value[start..<end]), reference: SourceReference(documentID: documentID, pageID: page.id, pageRevision: page.revision)))
                    start = end
                }
            }
        }
        for session in catalog.sessions {
            for block in TranscriptText.minutes(session.readableTranscript) {
                chunks.append(IndexedChunk(text: block.text, reference: SourceReference(documentID: documentID, audioSessionID: session.id, seconds: block.start)))
            }
        }
        return Self(format: 1, generation: generation, chunks: chunks)
    }
}
