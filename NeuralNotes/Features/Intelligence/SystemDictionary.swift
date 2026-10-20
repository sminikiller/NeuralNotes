import UIKit

@MainActor
enum SystemDictionary {
    static func open(term: String, from view: UIView? = nil) {
        let word = String(term.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !word.isEmpty else { return }
        let window = view?.window ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        guard var presenter = window?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let dictionary = UIReferenceLibraryViewController(term: word); dictionary.modalPresentationStyle = .formSheet
        presenter.present(dictionary, animated: true)
    }
}
