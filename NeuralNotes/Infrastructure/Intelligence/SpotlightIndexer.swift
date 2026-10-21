import CoreSpotlight
import UniformTypeIdentifiers
import Observation
import NeuralNotesCore

@MainActor @Observable
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()
    var message = ""
    @ObservationIgnored private var pending: Task<Void, Never>?
    func update(_ library: LibraryViewModel) async {
        let previous = pending
        let enabled = UserDefaults.standard.bool(forKey: "search.spotlight")
        let books = Array(library.notebooks.prefix(1000)), organization = library.organization
        let task = Task { @MainActor in
            await previous?.value
            do {
                let index = CSSearchableIndex.default()
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    index.deleteAllSearchableItems { error in if let error { continuation.resume(throwing: error) } else { continuation.resume() } }
                }
                guard enabled else { message = "Indice Spotlight rimosso"; return }
                let items = books.map { book in
                    let attributes = CSSearchableItemAttributeSet(contentType: .text)
                    attributes.title = book.title; attributes.contentDescription = "Quaderno NeuralNotes"
                    attributes.keywords = organization[book.id]?.tags ?? []
                    attributes.contentModificationDate = book.updatedAt
                    return CSSearchableItem(uniqueIdentifier: SystemSearchIdentity.identifier(documentID: book.documentID), domainIdentifier: "NeuralNotes.library", attributeSet: attributes)
                }
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    index.indexSearchableItems(items) { error in if let error { continuation.resume(throwing: error) } else { continuation.resume() } }
                }
                message = "\(items.count) quaderni indicizzati per titolo e tag"
            } catch { message = "Spotlight da riprovare: \(error.localizedDescription)" }
        }
        pending = task; await task.value
    }
}
