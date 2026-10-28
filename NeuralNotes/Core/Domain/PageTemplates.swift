import Foundation

public enum PaperTone: String, Codable, CaseIterable, Sendable {
    case white, cream, mint, blue, pink, slate
    public var title: String {
        switch self {
        case .white: return "Bianco"; case .cream: return "Avorio"; case .mint: return "Menta"
        case .blue: return "Azzurro"; case .pink: return "Rosa"; case .slate: return "Ardesia"
        }
    }
    public var rgb: (Double, Double, Double) {
        switch self {
        case .white: return (1, 1, 1); case .cream: return (1, 0.97, 0.88)
        case .mint: return (0.89, 0.97, 0.92); case .blue: return (0.90, 0.95, 1)
        case .pink: return (1, 0.92, 0.94); case .slate: return (0.16, 0.19, 0.22)
        }
    }
}

public enum PageFormat: String, Codable, CaseIterable, Sendable {
    case standard, a4, letter, square
    public var title: String {
        switch self { case .standard: return "Classico"; case .a4: return "A4"; case .letter: return "Letter"; case .square: return "Quadrato" }
    }
    public var size: (width: Double, height: Double) {
        switch self { case .standard: return (768, 1024); case .a4: return (595.28, 841.89)
        case .letter: return (612, 792); case .square: return (768, 768) }
    }
}

public struct PaperAppearance: Codable, Equatable, Sendable {
    public var tone: PaperTone
    public var spacing: Double
    public var margin: Bool
    public init(tone: PaperTone = .white, spacing: Double = 24, margin: Bool = false) {
        self.tone = tone; self.spacing = max(12, min(64, spacing)); self.margin = margin
    }
    public var isValid: Bool { spacing.isFinite && (12...64).contains(spacing) }
}

public struct PageTemplate: Codable, Equatable, Sendable {
    public var paper: PaperStyle
    public var appearance: PaperAppearance
    public var format: PageFormat
    public var landscape: Bool
    public var pdfFile: String?
    public var pdfIndex: Int?
    public var sourceWidth: Double?
    public var sourceHeight: Double?
    public init(paper: PaperStyle = .plain, appearance: PaperAppearance = PaperAppearance(), format: PageFormat = .standard, landscape: Bool = false) {
        self.paper = paper; self.appearance = appearance; self.format = format; self.landscape = landscape
    }
    public func makePage() -> PageSnapshot {
        var page = PageSnapshot(); page.paper = paper; page.appearance = appearance
        let size = format.size
        page.width = landscape ? size.height : size.width; page.height = landscape ? size.width : size.height
        if let file = pdfFile, let index = pdfIndex, let width = sourceWidth, let height = sourceHeight,
           width.isFinite, height.isFinite, width > 0, height > 0 {
            page.pdfFile = file; page.pdfIndex = index; page.width = width; page.height = height
        }
        return page
    }
}

public struct SpeechWindow: Codable, Equatable, Sendable {
    public var start: Double
    public var duration: Double
    public init(start: Double, duration: Double) { self.start = start; self.duration = duration }
    public static func plan(duration: Double, maximum: Double = 25) -> [SpeechWindow] {
        guard duration.isFinite, duration > 0, duration <= 604800, maximum.isFinite, maximum >= 1 else { return [] }
        var windows: [SpeechWindow] = [], start = 0.0
        while start < duration {
            let length = min(maximum, duration - start)
            windows.append(SpeechWindow(start: start, duration: length)); start += length
        }
        return windows
    }
    /// Frames of this window in an audio file, for reading it directly without
    /// an export. Adjacent windows share their boundary frame exactly, so the
    /// whole file is covered without gaps or overlaps. Nil past the end of file.
    public func frames(sampleRate: Double, length: Int64) -> Range<Int64>? {
        guard sampleRate.isFinite, sampleRate > 0, length > 0, start.isFinite, duration.isFinite, start >= 0, duration > 0 else { return nil }
        let first = Int64((start * sampleRate).rounded())
        let last = min(length, Int64(((start + duration) * sampleRate).rounded()))
        return first < last ? first..<last : nil
    }
}

public struct TranscriptionChunk: Codable, Equatable, Sendable {
    public var file: String
    public var window: SpeechWindow
    public var language: String
    public var segments: [TranscriptSegment]
    public init(file: String, window: SpeechWindow, language: String, segments: [TranscriptSegment]) {
        self.file = file; self.window = window; self.language = language; self.segments = segments
    }
}

public struct StrokeSample: Equatable, Sendable {
    public var x: Double, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public enum ScratchGesture {
    public static func matches(_ points: [StrokeSample]) -> Bool {
        guard points.count >= 8, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return false }
        let xs = points.map(\.x), ys = points.map(\.y)
        let width = (xs.max() ?? 0) - (xs.min() ?? 0), height = (ys.max() ?? 0) - (ys.min() ?? 0)
        guard max(width, height) >= 12, min(width, height) <= 140, max(width, height) <= 800 else { return false }
        // Accept repeated back-and-forth marks along either axis and repeated
        // loops used to black out a word. One circle or one cross is insufficient.
        // Count reversals on the dominant axis: normal writing often moves up
        // and down while progressing steadily to the right.
        return width >= height ? repeated(points.map(\.x), span: width) : repeated(points.map(\.y), span: height)
    }
    private static func repeated(_ values: [Double], span: Double) -> Bool {
        guard span >= 12 else { return false }
        let hysteresis = max(2.0, span * 0.15)
        var sign = 0, reversals = 0, travel = 0.0, extreme = values[0]
        for pair in zip(values, values.dropFirst()) {
            travel += abs(pair.1 - pair.0)
            let x = pair.1
            if sign == 0 {
                if abs(x - extreme) >= hysteresis { sign = x > extreme ? 1 : -1; extreme = x }
            } else if sign > 0 {
                if x >= extreme { extreme = x }
                else if extreme - x >= hysteresis { reversals += 1; sign = -1; extreme = x }
            } else {
                if x <= extreme { extreme = x }
                else if x - extreme >= hysteresis { reversals += 1; sign = 1; extreme = x }
            }
        }
        return reversals >= 4 && travel >= span * 4
    }
}
