import XCTest
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class HandwritingNativeTests: XCTestCase {
    private let page = SnapRect(x: 0, y: 0, width: 800, height: 1100)

    private func stroke(marker: Bool = false, masked: Bool = false) -> PKStroke {
        var points: [PKStrokePoint] = []
        for index in 0..<80 {
            let x = CGFloat(index) * 2 + 40
            let y = 110 + CGFloat(index) * 0.2 + (index.isMultiple(of: 2) ? 2.0 : -2.0)
            let location = CGPoint(x: x, y: y), size = CGSize(width: CGFloat(index % 7 + 2), height: 4)
            let force = CGFloat(index % 11) / 10, time = Double(index) * 0.025
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                points.append(PKStrokePoint(location: location, timeOffset: time, size: size,
                    opacity: 0.85, force: force, azimuth: 0.25, altitude: 1.2, secondaryScale: 0.65, threshold: 0.3))
                continue
            }
            #endif
            points.append(PKStrokePoint(location: location, timeOffset: time, size: size,
                opacity: 0.85, force: force, azimuth: 0.25, altitude: 1.2, secondaryScale: 0.65))
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 12345))
        let mask = masked ? UIBezierPath(rect: CGRect(x: 80, y: 0, width: 70, height: 500)) : nil
        return PKStroke(ink: PKInk(marker ? .marker : .pen, color: .black), path: path,
            transform: CGAffineTransform(translationX: 25, y: 20), mask: mask, randomSeed: 42)
    }

    @MainActor func testStraighteningReusesNativePathAttributesAndDoesNotTouchOtherInk() throws {
        let source = PKDrawing(strokes: [stroke(), stroke(marker: true)])
        let input = try HandwritingNative.analyze(source.dataRepresentation(), selected: [0, 1])
        XCTAssertEqual(input.strokes.map(\.id), [0])
        let proposal = try HandwritingLayout.propose(.straighten, strokes: input.strokes, analysis: input.analysis, page: page)
        let result = try HandwritingNative.applying(proposal, to: source, allowed: [0])
        XCTAssertNotEqual(result.strokes[0].transform, source.strokes[0].transform)
        assertAttributes(result.strokes[0], source.strokes[0], locations: true)
        XCTAssertTrue(NativeInkComparison.equal(PKDrawing(strokes: [result.strokes[1]]), PKDrawing(strokes: [source.strokes[1]])))
        XCTAssertEqual(EditorInkSignatures.make(result), EditorInkSignatures.make(source), "Audio and merged-layer membership must keep their native keys")
    }

    @MainActor func testCleanupKeepsEveryPressureSampleAndMaskWithoutResurrectingErasedInk() throws {
        let source = PKDrawing(strokes: [stroke(masked: true)])
        let input = try HandwritingNative.analyze(source.dataRepresentation(), selected: [0])
        XCTAssertLessThan(input.strokes[0].layoutPoints.count, input.strokes[0].points.count)
        XCTAssertGreaterThanOrEqual(input.strokes[0].bounds.x, 105)
        let proposal = try HandwritingLayout.propose(.cleanup(.strong), strokes: input.strokes, analysis: input.analysis, page: page)
        let result = try HandwritingNative.applying(proposal, to: source, allowed: [0])
        assertAttributes(result.strokes[0], source.strokes[0], locations: false)
        XCTAssertEqual(result.strokes[0].transform, source.strokes[0].transform)
        XCTAssertTrue(zip(result.strokes[0].path, source.strokes[0].path).contains { $0.location != $1.location })
        let mask = try XCTUnwrap(result.strokes[0].mask)
        XCTAssertFalse(mask.contains(CGPoint(x: 50, y: 115))); XCTAssertTrue(mask.contains(CGPoint(x: 100, y: 120)))
        XCTAssertEqual(result.strokes[0].path.first?.location, source.strokes[0].path.first?.location)
        XCTAssertEqual(result.strokes[0].path.last?.location, source.strokes[0].path.last?.location)
    }

    func testInvalidOrMarkerOnlySelectionCannotProduceAChange() throws {
        let source = PKDrawing(strokes: [stroke(marker: true)])
        XCTAssertThrowsError(try HandwritingNative.analyze(source.dataRepresentation(), selected: [0]))
        XCTAssertThrowsError(try HandwritingNative.analyze(source.dataRepresentation(), selected: [1]))
        let pen = PKDrawing(strokes: [stroke()])
        let input = try HandwritingNative.analyze(pen.dataRepresentation(), selected: [0])
        let proposal = try HandwritingLayout.propose(.straighten, strokes: input.strokes, analysis: input.analysis, page: page)
        XCTAssertThrowsError(try HandwritingNative.applying(proposal, to: pen, allowed: []))
        XCTAssertThrowsError(try HandwritingNative.applying(proposal, to: source, allowed: [0]))
    }

    @MainActor private func assertAttributes(_ actual: PKStroke, _ expected: PKStroke, locations: Bool,
                                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.path.count, expected.path.count, file: file, line: line)
        XCTAssertEqual(actual.path.creationDate, expected.path.creationDate, file: file, line: line)
        XCTAssertEqual(actual.randomSeed, expected.randomSeed, file: file, line: line)
        XCTAssertEqual(actual.ink.inkType, expected.ink.inkType, file: file, line: line)
        XCTAssertEqual(actual.ink.color, expected.ink.color, file: file, line: line)
        XCTAssertEqual(actual.mask?.cgPath, expected.mask?.cgPath, file: file, line: line)
        for (a, b) in zip(actual.path, expected.path) {
            if locations { XCTAssertEqual(a.location, b.location, file: file, line: line) }
            XCTAssertEqual(a.size, b.size, file: file, line: line)
            XCTAssertEqual(a.timeOffset, b.timeOffset, file: file, line: line)
            XCTAssertEqual(a.force, b.force, file: file, line: line)
            XCTAssertEqual(a.opacity, b.opacity, file: file, line: line)
            XCTAssertEqual(a.azimuth, b.azimuth, file: file, line: line)
            XCTAssertEqual(a.altitude, b.altitude, file: file, line: line)
            XCTAssertEqual(a.secondaryScale, b.secondaryScale, file: file, line: line)
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) { XCTAssertEqual(a.threshold, b.threshold, file: file, line: line) }
            #endif
        }
    }
}
