import Foundation

enum HandwritingMath {
    static func median(_ values: [Double]) -> Double { quantile(values, 0.5) }
    static func quantile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 1 }
        let sorted = values.sorted(), position = Double(sorted.count - 1) * max(0, min(1, fraction))
        let index = Int(position), upper = min(sorted.count - 1, index + 1), weight = position - Double(index)
        return sorted[index] * (1 - weight) + sorted[upper] * weight
    }
    static func bounds(_ points: [StrokeSample]) -> SnapRect {
        guard let first = points.first else { return .init(x: 0, y: 0, width: 0, height: 0) }
        var x0 = first.x, x1 = first.x, y0 = first.y, y1 = first.y
        for point in points.dropFirst() { x0 = min(x0, point.x); x1 = max(x1, point.x); y0 = min(y0, point.y); y1 = max(y1, point.y) }
        return .init(x: x0, y: y0, width: max(0.5, x1 - x0), height: max(0.5, y1 - y0))
    }
    static func union(_ boxes: [SnapRect]) -> SnapRect {
        guard let first = boxes.first else { return .init(x: 0, y: 0, width: 0, height: 0) }
        var x0 = first.x, x1 = first.maxX, y0 = first.y, y1 = first.maxY
        for box in boxes.dropFirst() { x0 = min(x0, box.x); x1 = max(x1, box.maxX); y0 = min(y0, box.y); y1 = max(y1, box.maxY) }
        return .init(x: x0, y: y0, width: max(0.5, x1 - x0), height: max(0.5, y1 - y0))
    }
    /// Quantile buckets suppress ascenders/descenders; the median pair slope
    /// (Theil–Sen) rejects an occasional low loop or dot. At most32buckets.
    static func baseline(_ points: [StrokeSample], bounds: SnapRect) -> (slope: Double, intercept: Double) {
        let bins = Int(min(32, max(3, bounds.width / 10)))
        var values = Array(repeating: [Double](), count: bins)
        var positions = Array(repeating: [Double](), count: bins)
        for point in points {
            let index = max(0, min(bins - 1, Int((point.x - bounds.x) / max(1, bounds.width) * Double(bins))))
            values[index].append(point.y); positions[index].append(point.x)
        }
        var samples: [StrokeSample] = []
        for i in values.indices where !values[i].isEmpty {
            samples.append(.init(x: median(positions[i]), y: quantile(values[i], 0.8)))
        }
        var slopes: [Double] = []
        for i in samples.indices { for j in samples.indices where j > i {
            let dx = samples[j].x - samples[i].x
            if abs(dx) > max(2, bounds.width * 0.15) { slopes.append((samples[j].y - samples[i].y) / dx) }
        } }
        let limit = tan(25 * Double.pi / 180)
        let slope = slopes.isEmpty ? 0 : max(-limit, min(limit, median(slopes)))
        let intercept = samples.isEmpty ? bounds.maxY : median(samples.map { $0.y - slope * $0.x })
        return (slope, intercept)
    }
}

enum HandwritingGrouping {
    private struct Measure {
        let stroke: HandwritingStroke
        let samples: [StrokeSample]
        let slope: Double
        let intercept: Double
        let height: Double
    }
    private struct Draft {
        var members: [Measure]
        var samples: [StrokeSample]
        var slope: Double
        var intercept: Double
    }
    static func analyze(_ strokes: [HandwritingStroke], hints: [SnapRect]) -> HandwritingAnalysis {
        let measured = strokes.map { stroke -> Measure in
            let step = max(1, stroke.layoutPoints.count / 256)
            let samples = stride(from: 0, to: stroke.layoutPoints.count, by: step).map { stroke.layoutPoints[$0] }
            let fit = stroke.bounds.width >= stroke.bounds.height * 1.5 ? HandwritingMath.baseline(samples, bounds: stroke.bounds) : (slope: 0.0, intercept: stroke.bounds.maxY)
            let leveled = samples.map { StrokeSample(x: $0.x, y: $0.y - fit.slope * $0.x) }
            let threshold = HandwritingMath.quantile(leveled.map(\.y), 0.8)
            let bottom = zip(samples, leveled).filter { $0.1.y >= threshold }.map { $0.0 }
            let lowerFit = HandwritingMath.baseline(bottom, bounds: stroke.bounds)
            return Measure(stroke: stroke, samples: bottom, slope: lowerFit.slope, intercept: lowerFit.intercept, height: HandwritingMath.bounds(leveled).height)
        }
        let bodyHeight = max(0.5, HandwritingMath.median(measured.map(\.height)))
        var drafts: [Draft] = []
        let bodies = measured.filter { $0.height >= bodyHeight * 0.3 }.sorted { $0.stroke.bounds.midX < $1.stroke.bounds.midX }
        var assigned = Set<Int>()
        for hint in hints {
            let members = bodies.filter { item in
                guard !assigned.contains(item.stroke.id) else { return false }
                let box = item.stroke.bounds
                let vertical = min(box.maxY, hint.maxY) - max(box.y, hint.y)
                return box.midX >= hint.x - bodyHeight && box.midX <= hint.maxX + bodyHeight && vertical >= 0.4 * min(box.height, hint.height)
            }
            guard !members.isEmpty else { continue }
            assigned.formUnion(members.map { $0.stroke.id })
            let all = members.flatMap(\.samples), step = max(1, Int(ceil(Double(all.count) / 512)))
            let points = stride(from: 0, to: all.count, by: step).map { all[$0] }
            let fit = HandwritingMath.baseline(points, bounds: HandwritingMath.union(members.map { $0.stroke.bounds }))
            drafts.append(Draft(members: members, samples: points, slope: fit.slope, intercept: fit.intercept))
        }
        for item in bodies where !assigned.contains(item.stroke.id) {
            let x = item.stroke.bounds.midX, y = item.slope * x + item.intercept
            let closest = drafts.indices.min { abs(drafts[$0].slope * x + drafts[$0].intercept - y) < abs(drafts[$1].slope * x + drafts[$1].intercept - y) }
            let overlaps: Bool
            if let closest {
                let expected = drafts[closest].slope * x + drafts[closest].intercept
                let height = max(1, HandwritingMath.median(drafts[closest].members.map(\.height)))
                let overlap = min(expected, y) - max(expected - height, y - item.height)
                overlaps = overlap >= 0.4 * (height + item.height) / 2
            } else { overlaps = false }
            if let closest, overlaps {
                drafts[closest].members.append(item)
                let all = drafts[closest].samples + item.samples
                let step = max(1, Int(ceil(Double(all.count) / 512)))
                drafts[closest].samples = stride(from: 0, to: all.count, by: step).map { all[$0] }
                let group = drafts[closest].members.map(\.stroke)
                let fit = HandwritingMath.baseline(drafts[closest].samples, bounds: HandwritingMath.union(group.map(\.bounds)))
                drafts[closest].slope = fit.slope; drafts[closest].intercept = fit.intercept
            } else { drafts.append(Draft(members: [item], samples: item.samples, slope: item.slope, intercept: item.intercept)) }
        }
        for item in measured where item.height < bodyHeight * 0.3 {
            let x = item.stroke.bounds.midX, y = item.stroke.bounds.midY
            let closest = drafts.indices.min { abs(drafts[$0].slope * x + drafts[$0].intercept - bodyHeight * 0.5 - y) < abs(drafts[$1].slope * x + drafts[$1].intercept - bodyHeight * 0.5 - y) }
            if let closest, abs(drafts[closest].slope * x + drafts[closest].intercept - bodyHeight * 0.5 - y) < bodyHeight * 2 {
                drafts[closest].members.append(item)
            } else { drafts.append(Draft(members: [item], samples: item.samples, slope: 0, intercept: item.stroke.bounds.maxY)) }
        }
        var lines: [HandwritingLine] = [], gaps: [Double] = []
        for draft in drafts {
            let members = draft.members.map(\.stroke), box = HandwritingMath.union(members.map(\.bounds))
            let angle = atan(draft.slope), baseline = draft.slope * box.x + draft.intercept
            let rotation = HandwritingAffine.rotating(-angle, about: .init(x: box.x, y: baseline))
            let projected = members.map { ($0, HandwritingMath.bounds($0.layoutPoints.map(rotation.applying))) }.sorted { $0.1.x < $1.1.x }
            let xHeight = max(1, HandwritingMath.median(projected.map { $0.1.height }.filter { $0 >= bodyHeight * 0.3 }))
            let heights = Dictionary(uniqueKeysWithValues: projected.map { ($0.0.id, $0.1.height) })
            func makeWord(_ word: [HandwritingStroke]) -> HandwritingWord {
                let bodyHeights = word.compactMap { heights[$0.id] }.filter { $0 >= bodyHeight * 0.3 }
                return .init(strokeIDs: word.map(\.id), bounds: HandwritingMath.union(word.map(\.bounds)),
                    xHeight: max(1, bodyHeights.isEmpty ? xHeight : HandwritingMath.median(bodyHeights)))
            }
            var words: [HandwritingWord] = [], word: [HandwritingStroke] = [], right = -Double.infinity
            for (stroke, rect) in projected {
                if !word.isEmpty, rect.x - right > 0.6 * xHeight {
                    words.append(makeWord(word))
                    gaps.append(rect.x - right); word = []
                }
                word.append(stroke); right = max(right, rect.maxX)
            }
            if !word.isEmpty { words.append(makeWord(word)) }
            lines.append(.init(strokeIDs: members.map(\.id), bounds: box, baseline: baseline, angle: angle, xHeight: xHeight, words: words))
        }
        lines.sort { $0.baseline < $1.baseline }
        let lineGaps = zip(lines, lines.dropFirst()).map { pair in max(0, pair.1.bounds.y - pair.0.bounds.maxY) }
        return HandwritingAnalysis(lines: lines, bounds: HandwritingMath.union(strokes.map(\.bounds)),
            wordGap: max(2, gaps.isEmpty ? bodyHeight * 0.3 : HandwritingMath.median(gaps)),
            lineGap: max(2, lineGaps.isEmpty ? bodyHeight * 0.4 : HandwritingMath.median(lineGaps)))
    }
}
