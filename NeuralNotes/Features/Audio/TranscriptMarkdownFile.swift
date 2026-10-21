import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import NeuralNotesCore

struct TranscriptMarkdownFile: Transferable {
    let session: AudioSession
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { value in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Capitoli-\(UUID()).md")
            try TranscriptChapters.markdown(session: value.session).write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
