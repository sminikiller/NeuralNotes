import XCTest
@testable import NeuralNotesCore

final class LayerStrokeTimelineTests: XCTestCase {
    func testPartialEraseRebasesOnlyTheRetainedOccurrenceAndKeepsOtherOwnersAndTimes() {
        let page = UUID(), layer = UUID(), session = UUID()
        let base = StrokeAnchor(signature: "same", audioSessionID: session, seconds: 5)
        var erased = StrokeAnchor(signature: "same", audioSessionID: session, seconds: 10)
        erased.layerID = layer; erased.strokeOccurrence = 0
        var retained = erased; retained.id = UUID(); retained.seconds = 20; retained.strokeOccurrence = 1
        var orphan = retained; orphan.id = UUID(); orphan.strokeOccurrence = 4
        let original = [base, erased, retained, orphan]
        let result = LayerStrokeTimeline.replacing(anchors: original, oldSignatures: ["same", "same"], newSignatures: ["cut"],
            retainedOriginalIndices: [1], pageID: page, layerID: layer)
        XCTAssertEqual(result.count, 3); XCTAssertEqual(result[0], base)
        XCTAssertEqual(result[1].id, retained.id); XCTAssertEqual(result[1].seconds, 20)
        XCTAssertEqual(result[1].layerID, layer); XCTAssertEqual(result[1].signature, "cut"); XCTAssertEqual(result[1].strokeOccurrence, 0)
        XCTAssertEqual(result[2].id, orphan.id); XCTAssertEqual(result[2].seconds, 20)
        XCTAssertEqual(LayerStrokeTimeline.current(signatures: ["cut"], anchors: result, pageID: page, layerID: layer, sessionID: session, seconds: 20.2), [0])
        XCTAssertEqual(original[2].signature, "same")
        XCTAssertEqual(LayerStrokeTimeline.replacing(anchors: original, oldSignatures: ["same"], newSignatures: ["cut"],
            retainedOriginalIndices: [99], pageID: page, layerID: layer), original)
    }

    func testEraseExpandsLegacyWildcardsWithoutDuplicateIDsAndDoesNotAttachAnOrphanToANewSignature() {
        let page = UUID(), layer = UUID(), session = UUID()
        var wildcard = StrokeAnchor(signature: "same", audioSessionID: session, seconds: 10); wildcard.layerID = layer
        var orphan = StrokeAnchor(signature: "cut", audioSessionID: session, seconds: 2); orphan.layerID = layer
        let result = LayerStrokeTimeline.replacing(anchors: [wildcard, orphan], oldSignatures: ["same", "same"],
            newSignatures: ["cut", "cut"], retainedOriginalIndices: [0, 1], pageID: page, layerID: layer)
        XCTAssertEqual(result.count, 3); XCTAssertEqual(Set(result.map(\.id)).count, 3)
        XCTAssertEqual(result.prefix(2).map(\.strokeOccurrence), [0, 1]); XCTAssertEqual(result.prefix(2).map(\.seconds), [10, 10])
        XCTAssertEqual(result.last?.id, orphan.id); XCTAssertEqual(result.last?.strokeOccurrence, 2)
        XCTAssertEqual(LayerStrokeTimeline.visible(signatures: ["cut", "cut"], anchors: result, pageID: page, layerID: layer, sessionID: session, seconds: 5), [])
        XCTAssertEqual(LayerStrokeTimeline.current(signatures: ["cut", "cut"], anchors: result, pageID: page, layerID: layer, sessionID: session, seconds: 2.2), [])
    }
    func testIdenticalNativeSignaturesOnDifferentLayersDoNotShareVisibilityOrHighlighting() {
        let page = UUID(), layer = UUID(), session = UUID()
        var base = StrokeAnchor(signature: "same", audioSessionID: session, seconds: 10)
        base.strokeOccurrence = 0
        var upper = StrokeAnchor(signature: "same", audioSessionID: session, seconds: 20); upper.layerID = layer; upper.strokeOccurrence = 0
        let anchors = [base, upper]
        XCTAssertEqual(LayerStrokeTimeline.visible(signatures: ["same"], anchors: anchors, pageID: page, layerID: nil, sessionID: session, seconds: 12), [0])
        XCTAssertEqual(LayerStrokeTimeline.visible(signatures: ["same"], anchors: anchors, pageID: page, layerID: layer, sessionID: session, seconds: 12), [])
        XCTAssertEqual(LayerStrokeTimeline.current(signatures: ["same"], anchors: anchors, pageID: page, layerID: layer, sessionID: session, seconds: 10.2), [])
        XCTAssertEqual(LayerStrokeTimeline.current(signatures: ["same"], anchors: anchors, pageID: page, layerID: nil, sessionID: session, seconds: 10.2), [0])
    }
    func testMergeRebasesOccurrencesAndTimesWithoutChangingSignaturesOrOtherOwners() {
        let page = UUID(), source = UUID(), untouched = UUID(), session = UUID()
        let base = StrokeAnchor(signature: "same", audioSessionID: session, seconds: 10)
        var copied = StrokeAnchor(signature: "same", audioSessionID: session, seconds: 20); copied.layerID = source
        var other = StrokeAnchor(signature: "other", audioSessionID: session, seconds: 30); other.layerID = untouched
        let original = [base, copied, other]
        let merged = LayerStrokeTimeline.rebasingForMerge(anchors: original, targetSignatures: ["same", "same"], sourceSignatures: ["same"], pageID: page, targetID: page, sourceID: source)
        XCTAssertEqual(merged.filter { $0.signature == "same" }.map(\.strokeOccurrence), [0, 1, 2])
        XCTAssertEqual(merged.filter { $0.signature == "same" }.map(\.seconds), [10, 10, 20])
        XCTAssertEqual(merged.last, other); XCTAssertEqual(Set(merged.map(\.id)).count, 4)
        XCTAssertEqual(merged[0].id, base.id); XCTAssertEqual(merged[2].id, copied.id)
        XCTAssertTrue(merged.prefix(3).allSatisfy { $0.layerID == nil })
        XCTAssertEqual(LayerStrokeTimeline.visible(signatures: ["same", "same", "same"], anchors: merged, pageID: page, layerID: nil, sessionID: session, seconds: 12), [0, 1])
        XCTAssertEqual(LayerStrokeTimeline.current(signatures: ["same", "same", "same"], anchors: merged, pageID: page, layerID: nil, sessionID: session, seconds: 20.1), [2])
        XCTAssertNil(original[0].strokeOccurrence); XCTAssertEqual(original[1].layerID, source)
    }
    func testLegacyWildcardRemainsCompatibleAndOccurrenceIsOptionalInTheArchive() throws {
        let page = UUID(), session = UUID(), anchor = StrokeAnchor(signature: "s", audioSessionID: session, seconds: 10)
        let encoded = try JSONEncoder().encode(anchor)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("strokeOccurrence"))
        XCTAssertEqual(try JSONDecoder().decode(StrokeAnchor.self, from: encoded), anchor)
        let signatures = ["s", "s", "unlinked"]
        XCTAssertEqual(LayerStrokeTimeline.visible(signatures: signatures, anchors: [anchor], pageID: page, layerID: nil, sessionID: session, seconds: 5), AudioReplay.visible(signatures: signatures, anchors: [anchor], sessionID: session, seconds: 5))
        XCTAssertEqual(LayerStrokeTimeline.current(signatures: signatures, anchors: [anchor], pageID: page, layerID: nil, sessionID: session, seconds: 10.5), AudioReplay.current(signatures: signatures, anchors: [anchor], sessionID: session, seconds: 10.5))
        var snapshot = PageSnapshot(id: page), invalid = anchor; invalid.strokeOccurrence = -1; snapshot.anchors = [invalid]
        XCTAssertThrowsError(try PageValidation.validate(snapshot))
    }
    func testOrphanAnchorCannotAttachItselfToANewlyMergedIdenticalSignature() {
        let page = UUID(), source = UUID(), session = UUID()
        let orphan = StrokeAnchor(signature: "s", audioSessionID: session, seconds: 10)
        let merged = LayerStrokeTimeline.rebasingForMerge(anchors: [orphan], targetSignatures: [], sourceSignatures: ["s"], pageID: page, targetID: page, sourceID: source)
        XCTAssertEqual(merged.first?.seconds, 10); XCTAssertEqual(merged.first?.strokeOccurrence, 1)
        XCTAssertEqual(LayerStrokeTimeline.visible(signatures: ["s"], anchors: merged, pageID: page, layerID: nil, sessionID: session, seconds: 5), [0])
        XCTAssertEqual(LayerStrokeTimeline.current(signatures: ["s"], anchors: merged, pageID: page, layerID: nil, sessionID: session, seconds: 10.5), [])
        var invalidOrdinal = orphan; invalidOrdinal.strokeOccurrence = 1
        let shifted = LayerStrokeTimeline.rebasingForMerge(anchors: [invalidOrdinal], targetSignatures: ["s"], sourceSignatures: ["s"], pageID: page, targetID: page, sourceID: source)
        XCTAssertEqual(shifted.first?.strokeOccurrence, 2)
    }

}
