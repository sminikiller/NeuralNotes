import XCTest
@testable import NeuralNotesCore

final class LayerMergePlanTests: XCTestCase {
    private func fixture() throws -> (PageSnapshot, UUID, UUID, UUID) {
        var page = PageSnapshot()
        let added = try PageLayerEditing.adding(to: page, name: "Upper"); page = added.page
        let base = TextElement(text: "Base")
        var upper = TextElement(text: "Upper"); upper.layerID = added.layerID
        page.texts = [base, upper]; page.objectOrder = [base.id, upper.id]
        return (page, added.layerID, base.id, upper.id)
    }
    func testMergePreservesContentStagesGroupOpacityAndObjectIdentitiesWithoutFlatteningNativeReferences() throws {
        var (page, upper, baseObject, topObject) = try fixture()
        page = try PageLayerEditing.opacity(page.id, value: 0.5, in: page)
        page = try PageLayerEditing.opacity(upper, value: 0.7, in: page)
        let original = page
        let plan = try LayerMergePlan.make(page: page, sourceID: upper, targetStrokes: ["base:0"], sourceStrokes: ["upper:0"], mergedStrokes: ["base:0", "upper:0"])
        XCTAssertEqual(plan.targetID, page.id); XCTAssertEqual(plan.page.layers?.count, 1)
        XCTAssertEqual(plan.page.texts.map(\.id), [baseObject, topObject])
        XCTAssertTrue(plan.page.texts.allSatisfy { $0.layerID == nil })
        let root = try XCTUnwrap(plan.page.layers?.first?.composition), children = try XCTUnwrap(root.children)
        XCTAssertEqual(children.count, 2); XCTAssertEqual(children[0].opacity, 0.5); XCTAssertEqual(children[1].opacity, 0.7)
        XCTAssertEqual(children[0].objectReferences, [baseObject]); XCTAssertEqual(children[1].objectReferences, [topObject])
        XCTAssertEqual(children[0].strokeReferences, ["base:0"]); XCTAssertEqual(children[1].strokeReferences, ["upper:0"])
        XCTAssertNil(plan.page.layers?.first?.opacity); XCTAssertEqual(page, original)
        try PageValidation.validate(plan.page)
        XCTAssertEqual(try JSONDecoder().decode(PageSnapshot.self, from: JSONEncoder().encode(plan.page)), plan.page)
    }
    func testCopiedNativeSignaturesRebaseAudioAndCompositionWithoutChangingDatesOrAttachingOrphanAnchors() throws {
        var (page, upper, _, _) = try fixture()
        let session = UUID()
        let base = StrokeAnchor(signature: "same:0", audioSessionID: session, seconds: 10)
        var top = StrokeAnchor(signature: "same:0", audioSessionID: session, seconds: 30); top.layerID = upper
        var orphan = top; orphan.id = UUID(); orphan.strokeOccurrence = 1
        page.anchors = [base, top, orphan]
        let plan = try LayerMergePlan.make(page: page, sourceID: upper, targetStrokes: ["same:0"], sourceStrokes: ["same:0"], mergedStrokes: ["same:0", "same:1"])
        XCTAssertEqual(plan.page.anchors.map(\.seconds), [10, 30, 30])
        XCTAssertEqual(plan.page.anchors[0].signature, "same:0"); XCTAssertEqual(plan.page.anchors[1].signature, "same:1")
        XCTAssertEqual(plan.page.anchors[0].strokeOccurrence, 0); XCTAssertEqual(plan.page.anchors[1].strokeOccurrence, 0)
        XCTAssertEqual(plan.page.anchors[2].strokeOccurrence, 1)
        XCTAssertTrue(plan.page.anchors.allSatisfy { $0.layerID == nil })
        XCTAssertEqual(plan.page.layers?.first?.composition?.strokeReferences, ["same:0", "same:1"])
    }
    func testMergingMovedBaseKeepsAnEmptyCanonicalBaseAndRejectsHiddenOrLockedTargetsWithoutChanges() throws {
        var (page, upper, _, _) = try fixture()
        page = try PageLayerEditing.reordering([upper, page.id], in: page)
        page.drawingFile = "drawings/base.drawing"
        let result = try LayerMergePlan.make(page: page, sourceID: page.id, targetStrokes: ["upper:0"], sourceStrokes: ["base:0"], mergedStrokes: ["upper:0", "base:0"])
        XCTAssertEqual(result.targetID, upper); XCTAssertEqual(result.page.layers?.count, 2)
        XCTAssertNil(result.page.drawingFile); XCTAssertTrue(result.page.texts.allSatisfy { $0.layerID == upper })
        let hidden = try PageLayerEditing.visibility(upper, visible: false, in: page)
        XCTAssertThrowsError(try LayerMergePlan.make(page: hidden, sourceID: page.id, targetStrokes: [], sourceStrokes: [], mergedStrokes: []))
        let locked = try PageLayerEditing.lock(upper, locked: true, in: page)
        XCTAssertThrowsError(try LayerMergePlan.make(page: locked, sourceID: page.id, targetStrokes: [], sourceStrokes: [], mergedStrokes: []))
        try PageValidation.validate(result.page)
    }
    func testCompositionRejectsRepeatedMembersForeignObjectsExcessiveDepthAndUnboundedReferences() throws {
        let id = UUID(), leaf = LayerComposition(strokes: ["a"], objects: [id])
        XCTAssertThrowsError(try LayerComposition(children: [leaf, leaf]).validate(ownedObjects: [id], ownedMarkups: []))
        XCTAssertThrowsError(try leaf.validate(ownedObjects: [], ownedMarkups: []))
        var deep = leaf
        for _ in 0..<6 { deep = LayerComposition(opacity: 0.5, children: [deep]) }
        XCTAssertThrowsError(try deep.validate(ownedObjects: [id], ownedMarkups: []))
        XCTAssertThrowsError(try LayerComposition(strokes: [String(repeating: "x", count: 257)]).validate(ownedObjects: [], ownedMarkups: []))
        XCTAssertThrowsError(try LayerComposition(opacity: .nan).validate(ownedObjects: [], ownedMarkups: []))
        XCTAssertThrowsError(try LayerComposition(children: [], strokes: ["a"]).validate(ownedObjects: [], ownedMarkups: []))
    }
    func testCompositionSurvivesDuplicationPageCloneObjectDeletionAndStrokeOccurrenceCompaction() throws {
        let (page, upper, baseID, _) = try fixture()
        let merged = try LayerMergePlan.make(page: page, sourceID: upper, targetStrokes: ["same:0"], sourceStrokes: ["same:0"], mergedStrokes: ["same:0", "same:1"]).page
        var copy = merged
        let objectMap = copy.renewObjectIDs()
        XCTAssertEqual(copy.layers?.first?.composition?.objectReferences, Set(copy.objectIDs))
        XCTAssertFalse(copy.layers?.first?.composition?.objectReferences.contains(baseID) == true)
        XCTAssertNotNil(objectMap[baseID])
        let duplicate = try PageLayerEditing.duplicating(merged.id, in: merged, name: "Copy", drawingCopy: nil)
        XCTAssertEqual(duplicate.page.layers?.last?.composition?.objectReferences, PageLayers.ownedObjectIDs(in: duplicate.page, layerID: duplicate.layerID))
        var removed = merged; removed.texts.removeAll { $0.id == baseID }; removed.pruneObjectReferences()
        XCTAssertFalse(removed.layers?.first?.composition?.objectReferences.contains(baseID) == true)
        let original = try XCTUnwrap(merged.layers?.first?.composition)
        let compacted = original.replacingStrokes(old: ["same:0", "same:1"], new: ["same:0"], retainedIndices: [1])
        XCTAssertEqual(compacted.children?.first?.strokeReferences, [])
        XCTAssertEqual(compacted.children?.last?.strokeReferences, ["same:0"])
        try PageValidation.validate(copy); try PageValidation.validate(removed); try PageValidation.validate(duplicate.page)
    }
    func testEditsAfterOneMergeAreCapturedAsTheFinalStageOfTheNextWithoutLosingEarlierGroups() throws {
        let id = UUID(), original = LayerComposition(children: [LayerComposition(opacity: 0.5, strokes: ["old"]), LayerComposition(objects: [id])])
        let captured = LayerComposition.capturing(original, opacity: 0.8, strokes: ["old", "new"], objects: [id], markups: [])
        XCTAssertEqual(captured.opacity, 0.8); XCTAssertEqual(captured.children?.last?.strokes, ["new"])
        XCTAssertEqual(captured.strokeReferences, ["old", "new"])
        XCTAssertEqual(captured.objectReferences, [id]); try captured.validate(ownedObjects: [id], ownedMarkups: [])
    }
    func testTypeDeletionExcludesHiddenAndLockedOwnersFromBothCountsAndMutation() throws {
        var (page, upper, baseID, topID) = try fixture()
        page = try PageLayerEditing.visibility(upper, visible: false, in: page)
        let session = UUID()
        var hidden = StrokeAnchor(signature: "upper", audioSessionID: session, seconds: 30); hidden.layerID = upper
        page.anchors = [StrokeAnchor(signature: "base", audioSessionID: session, seconds: 10), hidden]
        var mark = PDFMarkup(kind: .highlight, x: 10, y: 10, width: 20, height: 10, text: "hidden"); mark.layerID = upper
        page.pdfMarkups = [mark]
        let counts = PageDeletion.metadataCounts(in: page)
        XCTAssertEqual(counts[.text], 1); XCTAssertEqual(counts[.audioLinks], 1); XCTAssertEqual(counts[.marker], 0)
        let deleted = PageDeletion.removing([.text, .audioLinks, .marker], from: page)
        XCTAssertEqual(deleted.texts.map(\.id), [topID]); XCTAssertFalse(deleted.texts.contains(where: { $0.id == baseID }))
        XCTAssertEqual(deleted.anchors, [hidden]); XCTAssertEqual(deleted.pdfMarkups, [mark])
        try PageValidation.validate(deleted)
    }

}
