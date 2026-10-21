import SwiftUI
import NeuralNotesCore

struct CitedAnswer: View {
    let artifact: AIArtifact
    private var value: AttributedString {
        var result = AttributedString()
        for run in artifact.citedRuns {
            var value = AttributedString(run.text); value.link = run.link; result.append(value)
        }; return result
    }
    var body: some View { Text(value).textSelection(.enabled) }
}
