import UIKit
import PencilKit
import NeuralNotesCore

/// Native curl transition rotated into the horizontal book axis. The payload
/// images counter-rotate, so paper and handwriting remain upright throughout.
@MainActor
final class BookPageTurnOverlay: UIView {
    private let sheet = UIView()
    private let before = UIImageView()
    private let after = UIImageView()
    private let reduceMotion: Bool
    init(frame: CGRect, image: UIImage, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        super.init(frame: frame)
        accessibilityIdentifier = "bookPageTurn"
        backgroundColor = .secondarySystemBackground; clipsToBounds = true
        before.image = image; before.contentMode = .scaleToFill
        after.contentMode = .scaleToFill
        addSubview(sheet); sheet.addSubview(before)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sheet.backgroundColor = .secondarySystemBackground
    }
    required init?(coder: NSCoder) { nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        sheet.transform = .identity
        sheet.bounds = CGRect(origin: .zero, size: reduceMotion ? bounds.size : CGSize(width: bounds.height, height: bounds.width))
        sheet.center = CGPoint(x: bounds.midX, y: bounds.midY)
        if !reduceMotion { sheet.transform = CGAffineTransform(rotationAngle: -.pi / 2) }
        for image in [before, after] {
            image.transform = .identity; image.bounds = CGRect(origin: .zero, size: bounds.size)
            image.center = CGPoint(x: sheet.bounds.midX, y: sheet.bounds.midY)
            if !reduceMotion { image.transform = CGAffineTransform(rotationAngle: .pi / 2) }
        }
    }
    func turn(to image: UIImage, forward: Bool) async {
        after.image = image; layoutIfNeeded()
        let effect: UIView.AnimationOptions = reduceMotion ? .transitionCrossDissolve : (forward ? .transitionCurlUp : .transitionCurlDown)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UIView.transition(with: sheet, duration: reduceMotion ? 0.16 : 0.5,
                options: [effect, .showHideTransitionViews, .curveEaseInOut], animations: {
                    self.before.removeFromSuperview(); self.sheet.addSubview(self.after)
                }, completion: { _ in continuation.resume() })
        }
        removeFromSuperview()
    }
}

@MainActor
extension CanvasHost: EditorPagePresenter {
    func presentPage(_ target: PageSnapshot, load: @MainActor () async throws -> Void) async throws {
        guard let model, let current = model.page, current.id != target.id,
              bounds.width > 0, bounds.height > 0 else { try await load(); return }
        let oldIndex = model.pages.firstIndex(where: { $0.id == current.id }) ?? 0
        let newIndex = model.pages.firstIndex(where: { $0.id == target.id }) ?? oldIndex
        let overlay = BookPageTurnOverlay(frame: bounds, image: pageTurnImage(model: model), reduceMotion: UIAccessibility.isReduceMotionEnabled)
        addSubview(overlay); overlay.layoutIfNeeded()
        do {
            try await load()
            synchronizePage(); setNeedsLayout(); layoutIfNeeded()
            let image = pageTurnImage(model: model)
            bringSubviewToFront(overlay)
            await overlay.turn(to: image, forward: newIndex > oldIndex)
        } catch { overlay.removeFromSuperview(); throw error }
    }

    private func pageTurnImage(model: EditorViewModel) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = min(2, 1600 / max(bounds.width, bounds.height)); format.opaque = true
        let page = surface.page
        let image = DocumentServices.image(page: page, drawing: canvas.drawing, workspace: model.workspace, maxDimension: 1600)
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { result in
            UIColor.secondarySystemBackground.setFill(); result.fill(bounds)
            image.draw(in: surface.frame)
        }
    }
}
