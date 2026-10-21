import Foundation

/// File Providers may still be downloading or replacing a selected item.
enum CoordinatedFileAccess {
    static func read<Value>(_ url: URL, operation: (URL) throws -> Value) throws -> Value {
        var coordinationError: NSError?
        var result: Result<Value, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            result = Result { try Task.checkCancellation(); return try operation(coordinated) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}
