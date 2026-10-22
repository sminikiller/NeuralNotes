import SwiftUI
import NeuralNotesCore

@MainActor
struct CitedAnswer: View {
    let artifact: AIArtifact
    private var value: AttributedString {
        var result = AttributedString()
        for run in artifact.citedRuns {
            var value = AttributedString(run.text); value.link = run.link; result.append(value)
        }; return result
    }
    @ViewBuilder var body: some View {
        if (artifact.webSources ?? []).isEmpty { LensFormattedText(text: artifact.text).textSelection(.enabled) }
        else { Text(value).textSelection(.enabled) }
    }
}
