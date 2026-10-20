import Foundation

public struct PageLinkTarget: Codable, Equatable, Sendable {
    public var documentID: UUID
    public var pageID: UUID
    public init(documentID: UUID, pageID: UUID) { self.documentID = documentID; self.pageID = pageID }
    public func remapped(from original: UUID, to copy: UUID, pages: [UUID: UUID]) -> PageLinkTarget {
        guard documentID == original else { return self }
        return PageLinkTarget(documentID: copy, pageID: pages[pageID] ?? pageID)
    }
}

public struct IndexedPageLink: Identifiable, Equatable, Sendable {
    public var id: UUID { textID }
    public var originPageID: UUID
    public var textID: UUID
    public var label: String
    public var target: PageLinkTarget
}

public enum PageLinks {
    public static func index(_ pages: [PageSnapshot]) -> [IndexedPageLink] {
        pages.flatMap { page in
            page.texts.compactMap { text in
                text.pageLink.map { IndexedPageLink(originPageID: page.id, textID: text.id, label: String(text.text.prefix(240)), target: $0) }
            }
        }
    }
    public static func backlinks(to target: PageLinkTarget, in pages: [PageSnapshot]) -> [IndexedPageLink] {
        index(pages).filter { $0.target == target }
    }
}
