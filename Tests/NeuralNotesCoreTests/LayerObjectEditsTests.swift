import XCTest
@testable import NeuralNotesCore

final class LayerObjectEditsTests: XCTestCase {
    func testWholePageProposalCannotDeleteRecolorOrUnlockOtherOwnersAndNewObjectsJoinTheActiveLayer() throws {
        let added = try PageLayerEditing.adding(to: PageSnapshot(), name: "Notes")
        let layer = added.layerID
        var page = added.page
        let base = TextElement(text: "Base")
        var active = TextElement(text: "Active"); active.layerID = layer
        var locked = TextElement(text: "Locked"); locked.layerID = layer
        page.texts = [base, active, locked]; page.lockedObjects = [base.id, locked.id]
        var proposed = page; var changed = active; changed.text = "Edited"; changed.layerID = nil
        let new = TextElement(text: "New")
        proposed.texts = [changed, new]; proposed.lockedObjects = nil
        let result = LayerObjectEdits.restricted(proposed, from: page, activeLayerID: layer)
        XCTAssertEqual(result.texts.first(where: { $0.id == base.id }), base)
        XCTAssertEqual(result.texts.first(where: { $0.id == locked.id }), locked)
        XCTAssertEqual(result.texts.first(where: { $0.id == active.id })?.text, "Edited")
        XCTAssertEqual(result.texts.first(where: { $0.id == active.id })?.layerID, layer)
        XCTAssertEqual(result.texts.first(where: { $0.id == new.id })?.layerID, layer)
        XCTAssertEqual(Set(result.lockedObjects ?? []), [base.id])
        try PageValidation.validate(result)
    }

    func testHiddenOrLockedLayerCannotAcquireTextImagesShapesMarkersOrAudioAnchors() throws {
        let added = try PageLayerEditing.adding(to: PageSnapshot(), name: "Notes")
        var page = try PageLayerEditing.visibility(added.layerID, visible: false, in: added.page)
        let existing = TextElement(text: "Keep Base"); page.texts = [existing]
        var proposed = page; proposed.texts = [TextElement(text: "Forbidden")]
        proposed.images = [ImageElement(file: "images/new.jpg", width: 100, height: 100)]
        proposed.shapes = [ShapeElement(kind: .triangle, x: 10, y: 10, width: 100, height: 100)]
        proposed.anchors = [StrokeAnchor(signature: "new", audioSessionID: UUID(), seconds: 10)]
        let hidden = LayerObjectEdits.restricted(proposed, from: page, activeLayerID: added.layerID)
        XCTAssertEqual(hidden.texts, page.texts); XCTAssertTrue(hidden.images.isEmpty)
        XCTAssertTrue(hidden.shapes?.isEmpty != false); XCTAssertTrue(hidden.anchors.isEmpty)
        page = try PageLayerEditing.visibility(added.layerID, visible: true, in: page)
        page = try PageLayerEditing.lock(added.layerID, locked: true, in: page)
        let locked = LayerObjectEdits.restricted(proposed, from: page, activeLayerID: added.layerID)
        XCTAssertEqual(locked.texts, page.texts); XCTAssertTrue(locked.images.isEmpty)
        XCTAssertTrue(locked.shapes?.isEmpty != false); XCTAssertTrue(locked.anchors.isEmpty)
    }

    func testNewShapeAndConnectorAnchorsFollowTheirOwnerAndLegacyPagesRemainExactlyUnchanged() throws {
        let added = try PageLayerEditing.adding(to: PageSnapshot(), name: "Notes"), owner = added.layerID
        var proposed = added.page
        let anchor = StrokeAnchor(signature: "original", audioSessionID: UUID(), seconds: 17.25)
        var shape = ShapeElement(kind: .triangle, x: 10, y: 10, width: 100, height: 100); shape.audioAnchor = anchor
        var connector = ConnectorElement(from: .init(objectID: shape.id, x: 20, y: 20), to: .init(x: 200, y: 200))
        connector.audioAnchor = anchor
        proposed.shapes = [shape]; proposed.connectors = [connector]; proposed.anchors = [anchor]
        let result = LayerObjectEdits.restricted(proposed, from: added.page, activeLayerID: owner)
        XCTAssertEqual(result.shapes?.first?.layerID, owner)
        XCTAssertEqual(result.shapes?.first?.audioAnchor?.layerID, owner)
        XCTAssertEqual(result.connectors?.first?.layerID, owner)
        XCTAssertEqual(result.connectors?.first?.audioAnchor?.layerID, owner)
        XCTAssertEqual(result.anchors.first?.layerID, owner)
        XCTAssertEqual(result.anchors.first?.seconds, 17.25); XCTAssertEqual(result.anchors.first?.signature, "original")
        try PageValidation.validate(result)
        let original = PageSnapshot(); var legacy = original
        legacy.texts = [TextElement(text: "Legacy")]; legacy.shapes = [shape]
        XCTAssertEqual(LayerObjectEdits.restricted(legacy, from: original, activeLayerID: original.id), legacy)
    }
}
