import XCTest
@testable import NeuralNotesCore

final class HandwritingLayoutTests: XCTestCase {
    private func letter(id: Int, x: Double, baseline: Double, slope: Double = 0, height: Double = 18) -> HandwritingStroke {
        let values = [StrokeSample(x: x, y: baseline - height), .init(x: x + 4, y: baseline), .init(x: x + 8, y: baseline - height)]
        let points = values.map { StrokeSample(x: $0.x, y: $0.y + slope * $0.x) }
        return HandwritingStroke(id: id, points: points)
    }
    private func line(start: Int, y: Double, slope: Double = 0, words: Int = 3, height: Double = 18) -> [HandwritingStroke] {
        (0..<(words * 3)).map { i in letter(id: start + i, x: 40 + Double(i / 3) * 64 + Double(i % 3) * 12,
            baseline: y, slope: slope, height: height) }
    }
    private let page = SnapRect(x: 0, y: 0, width: 768, height: 1024)

    func testFiveIndependentlySlantedLinesBecomeHorizontalWithoutChangingStrokeIdentityOrPointData() throws {
        let slopes = [-0.15, 0.08, -0.04, 0.16, 0.0]
        let strokes = slopes.enumerated().flatMap { line(start: $0.offset * 100, y: 100 + Double($0.offset) * 80, slope: $0.element) }
        let analysis = try HandwritingLayout.analyze(strokes)
        XCTAssertEqual(analysis.lines.count, 5)
        for (actual, slope) in zip(analysis.lines, slopes) { XCTAssertEqual(actual.angle, atan(slope), accuracy: 0.035) }
        let proposal = try HandwritingLayout.propose(.straighten, strokes: strokes, analysis: analysis, page: page)
        XCTAssertTrue(proposal.fitsPage); XCTAssertEqual(proposal.adjustments.map(\.strokeID), strokes.map(\.id))
        XCTAssertTrue(proposal.adjustments.allSatisfy { $0.points == nil && $0.transform.isFinite })
        let map = Dictionary(uniqueKeysWithValues: proposal.adjustments.map { ($0.strokeID, $0.transform) })
        for group in analysis.lines {
            let bottoms = strokes.filter { group.strokeIDs.contains($0.id) }.map { map[$0.id]!.applying($0.points[1]).y }
            XCTAssertLessThan((bottoms.max() ?? 0) - (bottoms.min() ?? 0), 2)
        }
    }
    func testLineAndWordGroupingIncludesDotsAccentsAndCrossbarsExactlyOnce() throws {
        var strokes = line(start: 0, y: 100, words: 2) + line(start: 100, y: 160, words: 2)
        strokes += [HandwritingStroke(id: 90, points: [.init(x: 56, y: 74)]),
                    HandwritingStroke(id: 91, points: [.init(x: 42, y: 88), .init(x: 49, y: 88)])]
        let analysis = try HandwritingLayout.analyze(strokes)
        XCTAssertEqual(analysis.lines.count, 2); XCTAssertEqual(analysis.lines.map { $0.words.count }, [2, 2])
        XCTAssertTrue(analysis.lines[0].strokeIDs.contains(90)); XCTAssertTrue(analysis.lines[0].strokeIDs.contains(91))
        let all = analysis.lines.flatMap(\.strokeIDs)
        XCTAssertEqual(Set(all), Set(strokes.map(\.id))); XCTAssertEqual(all.count, strokes.count)
    }
    func testBottomBaselineFitRejectsOneDeepDescenderInsteadOfTiltingTheEntireLine() throws {
        var strokes = line(start: 0, y: 130, slope: 0.1, words: 5)
        let old = strokes[7]
        strokes[7] = HandwritingStroke(id: old.id, points: old.points + [.init(x: old.points[1].x, y: old.points[1].y + 28)])
        let result = try HandwritingLayout.analyze(strokes)
        XCTAssertEqual(result.lines.count, 1); XCTAssertEqual(result.lines[0].angle, atan(0.1), accuracy: 0.04)
    }
    func testExistingOCRLineBoxesAreOnlyGroupingHintsAndNeverReplaceTheNativePoints() throws {
        let strokes = line(start: 0, y: 100) + line(start: 100, y: 160)
        let hints = [SnapRect(x: 30, y: 75, width: 250, height: 30), .init(x: 30, y: 135, width: 250, height: 30)]
        let result = try HandwritingLayout.analyze(strokes, lineHints: hints)
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(Set(result.lines.flatMap(\.strokeIDs)), Set(strokes.map(\.id)))
        XCTAssertEqual(strokes[0].points, letter(id: 0, x: 40, baseline: 100).points)
    }
    func testStraightenCanAlignLeftAndPutItsBaselineOnTheExistingRuledPaperGrid() throws {
        var strokes = line(start: 0, y: 110) + line(start: 100, y: 180, slope: 0.1)
        for i in 9..<strokes.count {
            let value = strokes[i]
            strokes[i] = HandwritingStroke(id: value.id, points: value.points.map { .init(x: $0.x + 30, y: $0.y) })
        }
        let analysis = try HandwritingLayout.analyze(strokes)
        var options = HandwritingOptions(); options.alignLeft = true; options.paperSpacing = 32
        let proposal = try HandwritingLayout.propose(.straighten, strokes: strokes, analysis: analysis, page: page, options: options)
        let values = Dictionary(uniqueKeysWithValues: proposal.adjustments.map { ($0.strokeID, $0.transform) })
        for group in analysis.lines {
            let point = values[group.strokeIDs[0]]!.applying(group.baselineStart)
            XCTAssertEqual(point.x, analysis.bounds.x, accuracy: 0.1)
            XCTAssertEqual(point.y / 32, (point.y / 32).rounded(), accuracy: 0.001)
        }
    }
    func testUniformWordSizeClampsEveryScaleAndKeepsMetadataOutsideItsCoordinateProposal() throws {
        let strokes = line(start: 0, y: 100, words: 1, height: 6) + line(start: 100, y: 170, words: 1, height: 35)
        let analysis = try HandwritingLayout.analyze(strokes)
        let result = try HandwritingLayout.propose(.uniformSize, strokes: strokes, analysis: analysis, page: page)
        XCTAssertEqual(result.adjustments.count, strokes.count)
        for value in result.adjustments {
            XCTAssertGreaterThanOrEqual(value.transform.a, 0.8); XCTAssertLessThanOrEqual(value.transform.a, 1.25)
            XCTAssertEqual(value.transform.a, value.transform.d); XCTAssertNil(value.points)
        }
    }
    func testReflowWrapsCompleteWordsAndPreservesAllStrokeIdentitiesWithoutSplittingOneWord() throws {
        let strokes = line(start: 0, y: 100, words: 5)
        let analysis = try HandwritingLayout.analyze(strokes)
        XCTAssertEqual(analysis.lines.flatMap(\.words).count, 5)
        let result = try HandwritingLayout.propose(.reflow(width: 95), strokes: strokes, analysis: analysis, page: page)
        let transforms = Dictionary(uniqueKeysWithValues: result.adjustments.map { ($0.strokeID, $0.transform) })
        XCTAssertGreaterThan(Set(result.adjustments.map { $0.transform.ty }).count, 1)
        for word in analysis.lines.flatMap(\.words) {
            XCTAssertEqual(Set(word.strokeIDs.compactMap { transforms[$0]?.tx }).count, 1)
            XCTAssertEqual(Set(word.strokeIDs.compactMap { transforms[$0]?.ty }).count, 1)
        }
        XCTAssertTrue(result.fitsPage); XCTAssertEqual(Set(result.adjustments.map(\.strokeID)), Set(strokes.map(\.id)))
    }
    func testImpossibleReflowAndExpandedLineSpacingAreExplicitlyMarkedOutsideThePage() throws {
        let strokes = line(start: 0, y: 970, words: 5)
        let analysis = try HandwritingLayout.analyze(strokes)
        let result = try HandwritingLayout.propose(.reflow(width: 30), strokes: strokes, analysis: analysis, page: page)
        XCTAssertFalse(result.fitsPage)
        let lines = line(start: 0, y: 900) + line(start: 100, y: 990)
        let layout = try HandwritingLayout.analyze(lines)
        XCTAssertFalse(try HandwritingLayout.propose(.lineSpacing(2), strokes: lines, analysis: layout, page: page).fitsPage)
    }
    func testUniformLineSpacingRetainsTheFirstBaselineAndUsesOneTranslationForEveryStrokeInALine() throws {
        let strokes = line(start: 0, y: 100) + line(start: 100, y: 160) + line(start: 200, y: 245)
        let analysis = try HandwritingLayout.analyze(strokes)
        let result = try HandwritingLayout.propose(.lineSpacing(1.2), strokes: strokes, analysis: analysis, page: page)
        let transforms = Dictionary(uniqueKeysWithValues: result.adjustments.map { ($0.strokeID, $0.transform) })
        let baselines = analysis.lines.map { line in
            line.baseline + transforms[line.strokeIDs[0]]!.ty
        }
        XCTAssertEqual(baselines[0], analysis.lines[0].baseline, accuracy: 0.001)
        XCTAssertEqual(baselines[1] - baselines[0], baselines[2] - baselines[1], accuracy: 0.001)
        for line in analysis.lines { XCTAssertEqual(Set(line.strokeIDs.map { transforms[$0]!.ty }).count, 1) }
    }
    func testCleanupKeepsOriginalControlPointCountEndpointsAndReducesSmallJitterWithoutDroppingAnIndex() {
        let points = (0..<100).map { i in StrokeSample(x: Double(i), y: 100 + (i.isMultiple(of: 2) ? 0.3 : -0.3)) }
        let clean = HandwritingCleanup.points(points, strength: .medium)
        XCTAssertEqual(clean.count, points.count); XCTAssertEqual(clean.first, points.first); XCTAssertEqual(clean.last, points.last)
        let before = zip(points, points.dropFirst()).reduce(0.0) { $0 + abs($1.1.y - $1.0.y) }
        let after = zip(clean, clean.dropFirst()).reduce(0.0) { $0 + abs($1.1.y - $1.0.y) }
        XCTAssertLessThan(after, before * 0.5)
        XCTAssertTrue(zip(clean, clean.dropFirst()).allSatisfy { $0.0.x <= $0.1.x })
    }
    func testCleanupPreservesAClosedLoopAndHandlesAdversarialZigzagsWithBoundedWork() {
        let circle = (0...100).map { i in StrokeSample(x: 100 + cos(Double(i) * .pi / 50) * 30, y: 100 + sin(Double(i) * .pi / 50) * 30) }
        let clean = HandwritingCleanup.points(circle, strength: .light)
        XCTAssertEqual(clean.count, circle.count); XCTAssertEqual(clean.first, circle.first); XCTAssertEqual(clean.last, circle.last)
        for point in clean { XCTAssertEqual(hypot(point.x - 100, point.y - 100), 30, accuracy: 2) }
        let zigzag = (0..<20_000).map { StrokeSample(x: Double($0), y: $0.isMultiple(of: 2) ? 0 : 10) }
        let bounded = HandwritingCleanup.points(zigzag, strength: .strong)
        XCTAssertEqual(bounded.count, zigzag.count); XCTAssertEqual(bounded.first, zigzag.first); XCTAssertEqual(bounded.last, zigzag.last)
    }
    func testInvalidSelectionsAndInvalidParametersNeverProduceNonfiniteOrMissingAdjustments() throws {
        XCTAssertThrowsError(try HandwritingLayout.analyze([]))
        let duplicate = [letter(id: 1, x: 10, baseline: 100), letter(id: 1, x: 30, baseline: 100)]
        XCTAssertThrowsError(try HandwritingLayout.analyze(duplicate))
        XCTAssertThrowsError(try HandwritingLayout.analyze([.init(id: 1, points: [.init(x: .nan, y: 0)])]))
        let strokes = line(start: 0, y: 100), analysis = try HandwritingLayout.analyze(strokes)
        XCTAssertThrowsError(try HandwritingLayout.propose(.reflow(width: .infinity), strokes: strokes, analysis: analysis, page: page))
        XCTAssertThrowsError(try HandwritingLayout.propose(.lineSpacing(0), strokes: strokes, analysis: analysis, page: page))
    }
}
