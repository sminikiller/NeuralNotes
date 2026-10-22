import UIKit
import NeuralNotesCore

/// The commands beside words picked with the Lens: explain them in a note, ask about
/// them, search them in the whole notebook, copy them or let them go. It lives on the
/// page view, so it follows scrolling and zoom and never covers the picked words.
@MainActor
final class LensSelectionBar: UIView {
    private weak var model: EditorViewModel?
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let stack = UIStackView()
    private let scroll = UIScrollView()
    private var textButtons: [UIButton] = []
    private var size = CGSize(width: 320, height: 46)

    init() {
        super.init(frame: .zero)
        isHidden = true
        layer.shadowColor = UIColor.black.cgColor; layer.shadowOpacity = 0.22; layer.shadowRadius = 10; layer.shadowOffset = CGSize(width: 0, height: 4)
        blur.layer.cornerRadius = 14; blur.clipsToBounds = true
        addSubview(blur)
        stack.axis = .horizontal; stack.alignment = .center; stack.spacing = 0
        scroll.showsHorizontalScrollIndicator = false
        blur.contentView.addSubview(scroll); scroll.addSubview(stack)
        stack.addArrangedSubview(button("Spiega", icon: "lightbulb", identifier: "lensPickExplain") { $0.lensPickExplain() })
        stack.addArrangedSubview(button("Chiedi", icon: "bubble.left.and.text.bubble.right", identifier: "lensPickAsk") { $0.lensPickAsk() })
        let search = button("Cerca", icon: "magnifyingglass", identifier: "lensPickSearch") { $0.lensPickSearch() }
        let copy = button("Copia", icon: "doc.on.doc", identifier: "lensPickCopy") { $0.lensPickCopy() }
        textButtons = [search, copy]
        for item in textButtons { stack.addArrangedSubview(item) }
        stack.addArrangedSubview(button(nil, icon: "sparkle.magnifyingglass", identifier: "lensPickAgain") { $0.chooseTool(.lens) })
        stack.addArrangedSubview(button(nil, icon: "xmark", identifier: "lensPickClose") { $0.lensPickDismiss() })
        let fitting = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        size = CGSize(width: max(200, fitting.width + 12), height: max(46, fitting.height + 6))
        accessibilityIdentifier = "lensSelectionBar"
    }
    required init?(coder: NSCoder) { nil }

    private func button(_ title: String?, icon: String, identifier: String, action: @escaping (EditorViewModel) -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(textStyle: .subheadline))
        configuration.title = title
        configuration.imagePadding = 5
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming; outgoing.font = UIFont.preferredFont(forTextStyle: .subheadline); return outgoing
        }
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            if let model = self?.model { action(model) }
        })
        button.accessibilityIdentifier = identifier
        if title == nil { button.accessibilityLabel = identifier == "lensPickAgain" ? "Nuova selezione" : "Chiudi" }
        return button
    }

    /// Above the picked words, or below them near the top of the screen; always inside the view.
    func update(_ host: CanvasHost) {
        model = host.model
        guard let model = host.model, let pick = model.lensPick, pick.pageID == host.surface.page.id,
              !pick.area.isNull, host.bounds.width > 0 else {
            if !isHidden { isHidden = true }
            return
        }
        let words = host.surface.convert(pick.area, to: host)
        for button in textButtons { button.isEnabled = !pick.text.isEmpty }
        let width = min(size.width, max(1, host.bounds.width - 16))
        var origin = CGPoint(x: words.midX - width / 2, y: words.minY - size.height - 10)
        if origin.y < 8 { origin.y = words.maxY + 10 }
        origin.x = min(max(8, origin.x), max(8, host.bounds.width - width - 8))
        origin.y = min(max(8, origin.y), max(8, host.bounds.height - size.height - 8))
        frame = CGRect(origin: origin, size: CGSize(width: width, height: size.height))
        blur.frame = bounds
        scroll.frame = bounds
        stack.frame = CGRect(x: 6, y: 3, width: size.width - 12, height: size.height - 6)
        scroll.contentSize = size
        if isHidden { isHidden = false }
        if host.subviews.last !== self { host.bringSubviewToFront(self) }
    }
}
