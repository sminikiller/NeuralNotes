import Foundation

public enum PageNavigationMode: String, CaseIterable, Sendable {
    // Preserve the original preference key; the scroll now belongs to PKCanvas.
    case vertical = "continuous"
    case horizontal, single
    public var title: String {
        switch self {
        case .vertical: return "Scorrimento verticale"
        case .horizontal: return "Sfoglia orizzontalmente"
        case .single: return "Pagina singola"
        }
    }
    public var icon: String {
        switch self {
        case .vertical: return "rectangle.portrait.on.rectangle.portrait"
        case .horizontal: return "book.pages"
        case .single: return "doc"
        }
    }
}
