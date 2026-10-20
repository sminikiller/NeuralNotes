import Observation

@MainActor @Observable
final class LibraryRevision {
    static let shared = LibraryRevision()
    var value = 0
}
