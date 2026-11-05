import XCTest
@testable import NeuralNotesCore

final class LayerRenderPlanTests: XCTestCase {
    func testLegacyPlanUsesOneBaseWithUnchangedDrawingAndForegroundOrdering() throws {
        var page = PageSnapshot(); page.drawingFile = "drawings/current.drawing"; page.previousDrawingFile = "drawings/previous.drawing"
        let first = TextElement(text: "Under"), foreground = TextElement(text: "Above")
        let tape = StudyTape()
        var marker = ShapeElement(kind: .rectangle, x: 50, y: 80, width: 200, height: 20); marker.rectangularMarker = true
        page.texts = [first, foreground]; page.shapes = [marker]; page.tapes = [tape]
        page.objectOrder = [tape.id, foreground.id, marker.id, first.id]; page.aboveInkObjects = [foreground.id]
        let original = page, plan = try LayerRenderPlan.make(page: page, activeLayerID: page.id)
        XCTAssertEqual(plan.count, 1); XCTAssertEqual(plan[0].layer.id, page.id); XCTAssertEqual(plan[0].opacity, 1)
        XCTAssertEqual(plan[0].drawingFile, page.drawingFile); XCTAssertEqual(plan[0].previousDrawingFile, page.previousDrawingFile)
        XCTAssertTrue(plan[0].isActive)
        XCTAssertEqual(plan[0].underObjectIDs, [first.id]); XCTAssertEqual(plan[0].underMarkerIDs, [marker.id])
        XCTAssertEqual(plan[0].aboveObjectIDs, [foreground.id]); XCTAssertEqual(plan[0].tapeIDs, [tape.id])
        XCTAssertEqual(page, original); XCTAssertNil(page.layers)
    }

    func testExportSelectionDoesNotMutateVisibilityOpacityOrOwnerOrder() throws {
        let added = try PageLayerEditing.adding(to: PageSnapshot(), name: "Upper")
        let third = try PageLayerEditing.adding(to: added.page, name: "Hidden")
        var page = try PageLayerEditing.visibility(third.layerID, visible: false, in: third.page)
        page = try PageLayerEditing.lock(added.layerID, locked: true, in: page)
        page = try PageLayerEditing.opacity(added.layerID, value: 0.4, in: page)
        var base = TextElement(text: "Base"); base.layerID = page.id
        var upper = TextElement(text: "Upper"); upper.layerID = added.layerID
        var hidden = TextElement(text: "Hidden"); hidden.layerID = third.layerID
        page.texts = [base, upper, hidden]; page.objectOrder = [hidden.id, upper.id, base.id]
        let original = page
        let visible = try LayerRenderPlan.make(page: page, activeLayerID: added.layerID)
        XCTAssertEqual(visible.map { $0.layer.id }, [page.id, added.layerID])
        XCTAssertEqual(visible[1].underObjectIDs, [upper.id]); XCTAssertTrue(visible[1].layer.isLocked)
        XCTAssertTrue(visible[1].isActive); XCTAssertEqual(visible[1].opacity, 0.4)
        let all = try LayerRenderPlan.make(page: page, selection: .all)
        XCTAssertEqual(all.map { $0.layer.id }, [page.id, added.layerID, third.layerID])
        XCTAssertEqual(all[2].underObjectIDs, [hidden.id]); XCTAssertFalse(all[2].layer.isVisible)
        let selected = try LayerRenderPlan.make(page: page, selection: .selected([third.layerID, page.id]))
        XCTAssertEqual(selected.map { $0.layer.id }, [page.id, third.layerID])
        XCTAssertEqual(page, original)
    }

    func testReorderingPlacesWholeOwnerGroupsAndKeepsMarkersAndTapesInTheirOwnStage() throws {
        let added = try PageLayerEditing.adding(to: PageSnapshot(), name: "Notes"), owner = added.layerID
        var page = added.page
        var under = TextElement(text: "Under"); under.layerID = owner
        var over = TextElement(text: "Over"); over.layerID = owner
        var tape = StudyTape(); tape.layerID = owner
        var marker = ShapeElement(kind: .rectangle, x: 50, y: 80, width: 200, height: 20); marker.rectangularMarker = true; marker.layerID = owner
        page.texts = [under, over]; page.shapes = [marker]; page.tapes = [tape]
        page.aboveInkObjects = [over.id, marker.id]; page.lockedObjects = [under.id]
        page = try PageLayerEditing.reordering([owner, page.id], in: page)
        let plan = try LayerRenderPlan.make(page: page)
        XCTAssertEqual(plan.map { $0.layer.id }, [owner, page.id])
        XCTAssertEqual(plan[0].underObjectIDs, [under.id])
        XCTAssertTrue(plan[0].underMarkerIDs.isEmpty)
        XCTAssertEqual(plan[0].aboveObjectIDs, [marker.id, over.id])
        XCTAssertEqual(plan[0].tapeIDs, [tape.id])
        XCTAssertTrue(plan[1].underObjectIDs.isEmpty)
    }
}
