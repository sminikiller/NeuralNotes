import XCTest
@testable import NeuralNotesCore

final class FeatureGuideTests: XCTestCase {
    func testCatalogCoversEveryToolAndCategoryWithDistinctStepByStepTutorials() {
        let guides = FeatureGuide.catalog
        XCTAssertGreaterThanOrEqual(guides.count, 40)
        XCTAssertEqual(Set(guides.map(\.id)).count, guides.count)
        XCTAssertEqual(Set(guides.map(\.category)), Set(GuideCategory.allCases))
        XCTAssertEqual(Set(guides.flatMap(\.tools)), Set(WorkspaceTool.allCases))
        for guide in guides {
            XCTAssertFalse(guide.title.isEmpty); XCTAssertFalse(guide.icon.isEmpty)
            XCTAssertGreaterThanOrEqual(guide.steps.count, 3)
            XCTAssertTrue(guide.steps.allSatisfy { $0.count >= 25 })
        }
    }
    func testSearchIgnoresCaseAccentsAndRequiresEveryWord() throws {
        let guide = try XCTUnwrap(FeatureGuide.catalog.first { $0.id == "account-sync" })
        XCTAssertTrue(guide.matches("SINCRONIZZA account"))
        XCTAssertTrue(FeatureGuide.catalog.first { $0.id == "page-trash" }?.matches("PIU PAGINE") == true)
        XCTAssertTrue(guide.matches("cloud entrambe"))
        XCTAssertFalse(guide.matches("cloud nonsense-word"))
        XCTAssertTrue(guide.matches("  "))
    }
    func testProgressRoundTripsAndDiscardsStaleOrCorruptIDs() {
        let ids: Set<String> = ["undo", "account-sync", "unknown"]
        XCTAssertEqual(FeatureGuide.completedIDs(FeatureGuide.store(ids)), ["undo", "account-sync"])
        XCTAssertEqual(FeatureGuide.completedIDs("not json"), [])
        XCTAssertEqual(FeatureGuide.completedIDs("[\"undo\",\"undo\",\"old\"]"), ["undo"])
    }
}
