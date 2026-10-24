import UIKit
import CoreImage.CIFilterBuiltins
import Vision
import ImageIO
import NeuralNotesCore

enum PhotoPerspective {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// One rendering path for canvas, exports, crop preview and the Lens.
    static func render(_ image: UIImage, adjustment: PhotoAdjustment, maxDimension: CGFloat? = nil) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        var source = CIImage(cgImage: cg).oriented(image.imageOrientation.exifOrientation)
        source = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
        if let quad = adjustment.perspective, quad != .full {
            guard let size = quad.outputSize(for: .init(width: source.extent.width, height: source.extent.height)) else { return nil }
            let filter = CIFilter.perspectiveCorrection()
            filter.inputImage = source
            func point(_ p: PerspectivePoint) -> CGPoint { CGPoint(x: p.x * source.extent.width, y: (1 - p.y) * source.extent.height) }
            filter.topLeft = point(quad.topLeft); filter.topRight = point(quad.topRight)
            filter.bottomRight = point(quad.bottomRight); filter.bottomLeft = point(quad.bottomLeft)
            guard let result = filter.outputImage, !result.extent.isEmpty else { return nil }
            source = result.transformed(by: CGAffineTransform(translationX: -result.extent.minX, y: -result.extent.minY))
            source = source.transformed(by: CGAffineTransform(scaleX: size.width / source.extent.width, y: size.height / source.extent.height))
        }
        switch ((adjustment.quarterTurns % 4) + 4) % 4 {
        case 1: source = source.oriented(.right)
        case 2: source = source.oriented(.down)
        case 3: source = source.oriented(.left)
        default: break
        }
        source = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
        if adjustment.enhanced {
            let colors = CIFilter.colorControls(); colors.inputImage = source; colors.contrast = 1.12; colors.brightness = 0.02
            guard let colored = colors.outputImage else { return nil }
            let sharp = CIFilter.sharpenLuminance(); sharp.inputImage = colored; sharp.sharpness = 0.45
            guard let enhanced = sharp.outputImage else { return nil }; source = enhanced
        }
        let crop = adjustment.crop
        guard crop.width > 0, crop.height > 0 else { return nil }
        let extent = source.extent
        let rect = CGRect(x: crop.x * extent.width, y: (1 - crop.y - crop.height) * extent.height,
                          width: crop.width * extent.width, height: crop.height * extent.height).intersection(extent)
        guard !rect.isEmpty, !rect.isNull else { return nil }
        source = source.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let limit = maxDimension ?? 8192
        let scale = min(1, limit / max(source.extent.width, source.extent.height))
        source = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let output = context.createCGImage(source, from: source.extent) else { return nil }
        return UIImage(cgImage: output)
    }

    static func detect(_ image: UIImage) async -> PerspectiveQuad? {
        guard let cg = render(image, adjustment: PhotoAdjustment(), maxDimension: 1400)?.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
            let document = VNDetectDocumentSegmentationRequest()
            var observation: VNRectangleObservation?
            if (try? handler.perform([document])) != nil { observation = document.results?.first }
            if observation == nil {
                let rectangles = VNDetectRectanglesRequest()
                rectangles.maximumObservations = 1; rectangles.minimumConfidence = 0.5; rectangles.minimumSize = 0.15
                rectangles.minimumAspectRatio = 0.15
                if (try? handler.perform([rectangles])) != nil { observation = rectangles.results?.first }
            }
            guard let found = observation else { return nil }
            func point(_ p: CGPoint) -> PerspectivePoint { .init(x: min(1, max(0, p.x)), y: min(1, max(0, 1 - p.y))) }
            let quad = PerspectiveQuad(topLeft: point(found.topLeft), topRight: point(found.topRight),
                bottomRight: point(found.bottomRight), bottomLeft: point(found.bottomLeft))
            return quad.isConvex ? quad : nil
        }.value
    }
}

private extension UIImage.Orientation {
    var exifOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
