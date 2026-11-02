import Foundation
import NeuralNotesCore

struct EditorSearchDestination: Equatable {
    let reference: SourceReference
    let query: String
}

@MainActor
extension EditorViewModel {
    func enqueueGlobalSearch(reference: SourceReference, query: String) {
        pendingGlobalSearch = EditorSearchDestination(reference: reference, query: String(query.prefix(200)))
        globalSearchDestinationRequest += 1
    }
    func consumeGlobalSearch() async {
        guard let destination = pendingGlobalSearch, hasLease, page != nil, !loading, !navigating, !hasActiveStroke else { return }
        pendingGlobalSearch = nil
        if let id = destination.reference.pageID, let page = pages.first(where: { $0.id == id }) {
            await select(page)
            if self.page?.id == id { searchFocus = SearchFocusRequest(pageID: id, query: destination.query) }
        }
        if let id = destination.reference.audioSessionID, let session = audio?.sessions.first(where: { $0.id == id }) {
            await audio?.play(session, at: destination.reference.seconds ?? 0)
        }
    }
}
