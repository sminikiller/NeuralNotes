import Foundation

public struct GuideExercise: Sendable {
    public let task: String
    public let expected: String

    public init(_ task: String, _ expected: String) {
        self.task = task
        self.expected = expected
    }
}

extension FeatureGuide {
    public var exercises: [GuideExercise] { GuidePractice.catalog[id] ?? [] }

    public func exerciseID(at index: Int) -> String { "\(id)/\(index + 1)" }

    public func isPracticed(_ checked: Set<String>) -> Bool {
        !exercises.isEmpty && exercises.indices.allSatisfy { checked.contains(exerciseID(at: $0)) }
    }

    public static func checkedExerciseIDs(_ stored: String) -> Set<String> {
        let decoded = (try? JSONDecoder().decode([String].self, from: Data(stored.utf8))) ?? []
        let known = Set(catalog.flatMap { guide in guide.exercises.indices.map { guide.exerciseID(at: $0) } })
        return Set(decoded).intersection(known)
    }

    public static func storeCheckedExercises(_ ids: Set<String>) -> String {
        let data = try? JSONEncoder().encode(ids.sorted())
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}
