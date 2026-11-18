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

    func testEveryLessonHasAnObservableExerciseAndEveryExerciseBelongsToALesson() {
        XCTAssertEqual(Set(GuidePractice.catalog.keys), Set(FeatureGuide.catalog.map(\.id)))
        for guide in FeatureGuide.catalog {
            XCTAssertFalse(guide.exercises.isEmpty, guide.id)
            XCTAssertTrue(guide.exercises.allSatisfy { $0.task.count >= 25 && $0.expected.count >= 25 }, guide.id)
            XCTAssertEqual(Set(guide.exercises.map(\.task)).count, guide.exercises.count, guide.id)
        }
    }

    func testExercisesMustAllBeCheckedAndProgressSurvivesSerialization() throws {
        let undo = try XCTUnwrap(FeatureGuide.catalog.first { $0.id == "undo" })
        XCTAssertGreaterThan(undo.exercises.count, 1)
        let first = undo.exerciseID(at: 0)
        let checked = Set(undo.exercises.indices.map { undo.exerciseID(at: $0) })
        XCTAssertFalse(undo.isPracticed([first]))
        XCTAssertTrue(undo.isPracticed(checked))
        XCTAssertEqual(FeatureGuide.checkedExerciseIDs(FeatureGuide.storeCheckedExercises(checked.union(["old/100"]))), checked)
        XCTAssertTrue(FeatureGuide.checkedExerciseIDs("not json").isEmpty)
        XCTAssertTrue(undo.matches("riporta in vita"))
    }
}
