import UIKit
import NeuralNotesCore

@MainActor
extension DiagramLabels {
    static func scaling(_ shape: ShapeElement, by scale: Double) -> ShapeElement {
        guard scale != 1, scale.isFinite, scale > 0, shape.label != nil else { return shape }
        var value = shape
        let result = scaledText(shape.label ?? "", rtf: shape.labelRTF, fontSize: shape.labelFontSize ?? 18, scale: scale)
        value.labelFontSize = result.0; value.labelRTF = result.1; return value
    }
    static func scaling(_ connector: ConnectorElement, by scale: Double) -> ConnectorElement {
        guard scale != 1, scale.isFinite, scale > 0, connector.label != nil else { return connector }
        var value = connector
        let result = scaledText(connector.label ?? "", rtf: connector.labelRTF, fontSize: connector.labelFontSize ?? 16, scale: scale)
        value.labelFontSize = result.0; value.labelRTF = result.1; return value
    }
    private static func scaledText(_ text: String, rtf: Data?, fontSize: Double, scale: Double) -> (Double, Data?) {
        let size = min(200, max(6, fontSize * scale))
        // A plain label keeps its automatic paper/fill contrast, rather than
        // freezing the default text color into an RTF during a size change.
        guard let rtf else { return (size, nil) }
        var source = TextElement(text: text); source.rtf = rtf; source.fontSize = fontSize
        let scaled = RichText.scaled(source, by: scale)
        let value = NSMutableAttributedString(attributedString: RichText.attributed(scaled))
        value.enumerateAttribute(.font, in: NSRange(location: 0, length: value.length)) { item, range, _ in
            if let font = item as? UIFont { value.addAttribute(.font, value: font.withSize(min(200, max(6, font.pointSize))), range: range) }
        }
        return (size, RichText.data(value))
    }
}
