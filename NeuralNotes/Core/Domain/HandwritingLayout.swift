import Foundation

public struct HandwritingAffine: Equatable, Sendable {
    public var a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double
    public init(a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1, tx: Double = 0, ty: Double = 0) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public static let identity = Self()
    public static func rotating(_ angle: Double, about point: StrokeSample) -> Self {
        let cosine = cos(angle), sine = sin(angle)
        return Self(a: cosine, b: sine, c: -sine, d: cosine,
            tx: point.x - cosine * point.x + sine * point.y, ty: point.y - sine * point.x - cosine * point.y)
    }
    public static func scaling(_ factor: Double, about point: StrokeSample) -> Self {
        Self(a: factor, d: factor, tx: point.x * (1 - factor), ty: point.y * (1 - factor))
    }
    public func translated(x: Double = 0, y: Double = 0) -> Self {
        var value = self; value.tx += x; value.ty += y; return value
    }
    public func applying(_ point: StrokeSample) -> StrokeSample {
        .init(x: a * point.x + c * point.y + tx, y: b * point.x + d * point.y + ty)
    }
    public func applying(_ box: SnapRect) -> SnapRect {
        HandwritingMath.bounds([applying(.init(x: box.x, y: box.y)), applying(.init(x: box.maxX, y: box.y)),
            applying(.init(x: box.x, y: box.maxY)), applying(.init(x: box.maxX, y: box.maxY))])
    }
    public var isFinite: Bool { [a, b, c, d, tx, ty].allSatisfy(\.isFinite) }
}

public struct HandwritingStroke: Equatable, Sendable {
    public let id: Int
    public let points: [StrokeSample]
    public let layoutPoints: [StrokeSample]
    public let bounds: SnapRect
    public init(id: Int, points: [StrokeSample], bounds: SnapRect? = nil, layoutPoints: [StrokeSample]? = nil) {
        let visible = layoutPoints ?? points
        self.id = id; self.points = points; self.layoutPoints = visible
        self.bounds = bounds ?? HandwritingMath.bounds(visible)
    }
}
public struct HandwritingWord: Equatable, Sendable {
    public let strokeIDs: [Int]
    public let bounds: SnapRect
    public let xHeight: Double
}
public struct HandwritingLine: Equatable, Sendable {
    public let strokeIDs: [Int]
    public let bounds: SnapRect
    public let baseline: Double
    public let angle: Double
    public let xHeight: Double
    public let words: [HandwritingWord]
    public var baselineStart: StrokeSample { .init(x: bounds.x, y: baseline) }
}
public struct HandwritingAnalysis: Equatable, Sendable {
    public let lines: [HandwritingLine]
    public let bounds: SnapRect
    public let wordGap: Double
    public let lineGap: Double
}
public enum HandwritingFailure: LocalizedError {
    case invalidSelection, tooLarge, outsidePage
    public var errorDescription: String? {
        switch self {
        case .invalidSelection: return "Seleziona una parte di grafia con il lazo."
        case .tooLarge: return "Seleziona un paragrafo più piccolo per la rifinitura della grafia."
        case .outsidePage: return "La proposta supera il foglio. Aumenta la larghezza o riduci l’interlinea."
        }
    }
}
public enum HandwritingAction: Equatable, Sendable {
    case straighten, uniformSize, cleanup(HandwritingCleanup.Strength), reflow(width: Double), lineSpacing(Double)
}
public struct HandwritingOptions: Equatable, Sendable {
    public var alignLeft = false
    public var paperSpacing: Double?
    public var paperOrigin = 0.0
    public var reflowX: Double?
    public init() { }
}
public struct HandwritingAdjustment: Equatable, Sendable {
    public let strokeID: Int
    public let transform: HandwritingAffine
    /// Coordinate-only replacement; the native adapter keeps all other fields
    /// at the same original indices, including pressure peaks and timestamps.
    public let points: [StrokeSample]?
}
public struct HandwritingProposal: Equatable, Sendable {
    public let adjustments: [HandwritingAdjustment]
    public let bounds: SnapRect
    public let fitsPage: Bool
}

public enum HandwritingLayout {
    public static let maximumStrokes = 4_000
    public static let maximumPoints = 500_000
    public static func analyze(_ strokes: [HandwritingStroke], lineHints: [SnapRect] = []) throws -> HandwritingAnalysis {
        guard !strokes.isEmpty, Set(strokes.map(\.id)).count == strokes.count else { throw HandwritingFailure.invalidSelection }
        guard strokes.count <= maximumStrokes, strokes.reduce(0, { $0 + $1.points.count }) <= maximumPoints,
              strokes.reduce(0, { $0 + $1.layoutPoints.count }) <= maximumPoints else { throw HandwritingFailure.tooLarge }
        guard strokes.allSatisfy({ valid($0) }) else { throw HandwritingFailure.invalidSelection }
        return HandwritingGrouping.analyze(strokes, hints: Array(lineHints.filter(\.valid).prefix(256)))
    }
    private static func valid(_ stroke: HandwritingStroke) -> Bool {
        !stroke.points.isEmpty && !stroke.layoutPoints.isEmpty && stroke.bounds.valid &&
        stroke.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 10_000_000 && abs($0.y) <= 10_000_000 }) &&
        stroke.layoutPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 10_000_000 && abs($0.y) <= 10_000_000 })
    }
    public static func propose(_ action: HandwritingAction, strokes: [HandwritingStroke], analysis: HandwritingAnalysis,
                               page: SnapRect, options: HandwritingOptions = HandwritingOptions()) throws -> HandwritingProposal {
        guard page.valid, !analysis.lines.isEmpty,
              Set(analysis.lines.flatMap(\.strokeIDs)) == Set(strokes.map(\.id)) else { throw HandwritingFailure.invalidSelection }
        var transforms = Dictionary(uniqueKeysWithValues: strokes.map { ($0.id, HandwritingAffine.identity) })
        var replacements: [Int: [StrokeSample]] = [:]
        switch action {
        case .straighten:
            var previousPaperBaseline: Double?
            for line in analysis.lines {
                var value = HandwritingAffine.rotating(-line.angle, about: line.baselineStart)
                if options.alignLeft { value = value.translated(x: analysis.bounds.x - line.bounds.x) }
                if let spacing = options.paperSpacing, spacing.isFinite, spacing > 0 {
                    var target = ((line.baseline - options.paperOrigin) / spacing).rounded() * spacing + options.paperOrigin
                    if let previousPaperBaseline { target = max(target, previousPaperBaseline + spacing) }
                    previousPaperBaseline = target
                    value = value.translated(y: target - line.baseline)
                }
                for id in line.strokeIDs { transforms[id] = value }
            }
        case .uniformSize:
            let heights = analysis.lines.flatMap(\.words).map(\.xHeight).filter { $0 > 1 }
            let target = HandwritingMath.median(heights)
            for line in analysis.lines { for word in line.words {
                let factor = max(0.8, min(1.25, target / max(1, word.xHeight)))
                let baseline = line.baseline + tan(line.angle) * (word.bounds.x - line.bounds.x)
                let value = HandwritingAffine.scaling(factor, about: .init(x: word.bounds.x, y: baseline))
                for id in word.strokeIDs { transforms[id] = value }
            } }
        case .cleanup(let strength):
            for stroke in strokes { replacements[stroke.id] = HandwritingCleanup.points(stroke.points, strength: strength) }
        case .reflow(let width):
            guard width.isFinite, width > 0 else { throw HandwritingFailure.invalidSelection }
            let startX = options.reflowX ?? analysis.bounds.x
            guard startX.isFinite, startX >= page.x, startX < page.maxX else { throw HandwritingFailure.invalidSelection }
            let words = analysis.lines.flatMap(\.words)
            let minimum = words.map { $0.bounds.width }.max() ?? 1
            let available = max(minimum, min(width, page.maxX - startX))
            let lineHeight = max(1, HandwritingMath.median(analysis.lines.map { $0.bounds.height }))
            var x = startX, y = analysis.bounds.y, tallest = lineHeight
            for word in words {
                if x > startX, x + word.bounds.width > startX + available {
                    x = startX; y += tallest + analysis.lineGap; tallest = lineHeight
                }
                let value = HandwritingAffine(tx: x - word.bounds.x, ty: y - word.bounds.y)
                for id in word.strokeIDs { transforms[id] = value }
                x += word.bounds.width + analysis.wordGap; tallest = max(tallest, word.bounds.height)
            }
        case .lineSpacing(let factor):
            guard factor.isFinite, (0.5...2).contains(factor) else { throw HandwritingFailure.invalidSelection }
            let first = analysis.lines[0].baseline
            let baselineGaps = zip(analysis.lines, analysis.lines.dropFirst()).map { $0.1.baseline - $0.0.baseline }
            let step = max(1, HandwritingMath.median(baselineGaps)) * factor
            for (index, line) in analysis.lines.enumerated() {
                for id in line.strokeIDs { transforms[id] = .init(ty: first + Double(index) * step - line.baseline) }
            }
        }
        let adjustments = strokes.map { HandwritingAdjustment(strokeID: $0.id, transform: transforms[$0.id] ?? .identity, points: replacements[$0.id]) }
        let boxes = zip(strokes, adjustments).map { stroke, value in
            value.points.map(HandwritingMath.bounds) ?? value.transform.applying(stroke.bounds)
        }
        let bounds = HandwritingMath.union(boxes)
        let fits = bounds.valid && bounds.x >= page.x - 0.5 && bounds.y >= page.y - 0.5 && bounds.maxX <= page.maxX + 0.5 && bounds.maxY <= page.maxY + 0.5
        return HandwritingProposal(adjustments: adjustments, bounds: bounds, fitsPage: fits)
    }
}
