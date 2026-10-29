import Foundation

public enum SelectionArrangement: String, CaseIterable, Sendable {
    case left, center, right, top, middle, bottom, horizontal, vertical, width, height
    public var title: String {
        switch self {
        case .left: return "Allinea a sinistra"; case .center: return "Allinea al centro"
        case .right: return "Allinea a destra"; case .top: return "Allinea in alto"
        case .middle: return "Allinea a metà"; case .bottom: return "Allinea in basso"
        case .horizontal: return "Distribuisci in orizzontale"; case .vertical: return "Distribuisci in verticale"
        case .width: return "Uguaglia larghezza"; case .height: return "Uguaglia altezza"
        }
    }
    public var minimumCount: Int { self == .horizontal || self == .vertical ? 3 : 2 }
    /// Keys and order are preserved. Distribution keeps both outer objects fixed.
    public func applying(_ values: [UUID: SnapRect]) -> [UUID: SnapRect] {
        guard values.count >= minimumCount, values.values.allSatisfy(\.valid) else { return values }
        let minX = values.values.map(\.x).min()!, maxX = values.values.map(\.maxX).max()!
        let minY = values.values.map(\.y).min()!, maxY = values.values.map(\.maxY).max()!
        var result = values
        if self == .horizontal || self == .vertical {
            let horizontal = self == .horizontal
            let sorted = values.sorted {
                let a = horizontal ? $0.value.x : $0.value.y, b = horizontal ? $1.value.x : $1.value.y
                return a == b ? $0.key.uuidString < $1.key.uuidString : a < b
            }
            let total = sorted.reduce(0.0) { $0 + (horizontal ? $1.value.width : $1.value.height) }
            let first = sorted.first!.value, last = sorted.last!.value
            let start = horizontal ? first.x : first.y, end = horizontal ? last.maxX : last.maxY
            let gap = (end - start - total) / Double(values.count - 1)
            var position = start
            for (id, original) in sorted {
                var rect = original
                if horizontal { rect.x = position } else { rect.y = position }
                result[id] = rect; position += (horizontal ? rect.width : rect.height) + gap
            }
            return result
        }
        let width = values.values.map(\.width).max()!, height = values.values.map(\.height).max()!
        for (id, original) in values {
            var rect = original
            switch self {
            case .left: rect.x = minX
            case .center: rect.x = (minX + maxX - rect.width) / 2
            case .right: rect.x = maxX - rect.width
            case .top: rect.y = minY
            case .middle: rect.y = (minY + maxY - rect.height) / 2
            case .bottom: rect.y = maxY - rect.height
            case .width: rect.width = width
            case .height: rect.height = height
            default: break
            }
            result[id] = rect
        }
        return result
    }
}
