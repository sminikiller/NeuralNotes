import SwiftUI
import NeuralNotesCore

@MainActor
struct StudyStatisticsPanel: View {
    let model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var stats: StudyStatistics?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if let stats {
                    Section("Il tuo ripasso") {
                        LabeledContent("Da ripassare ora", value: "\(stats.dueNow)")
                        LabeledContent("Flashcard", value: "\(stats.totalCards)")
                        LabeledContent("Intervallo di almeno 21 giorni", value: "\(stats.matureCards)")
                        LabeledContent("Giorni consecutivi", value: "\(stats.streakDays)")
                        LabeledContent("Ripassi nello storico", value: "\(stats.recordedReviews)")
                        if stats.recordedReviews > 0 {
                            LabeledContent("Risposte Bene o Facile", value: "\(Int((Double(stats.recalledReviews) / Double(stats.recordedReviews) * 100).rounded()))%")
                        }
                        Text("Le valutazioni sono quelle indicate da te. Lo storico parte da questa versione e conserva gli ultimi 10.000 ripassi, anche se una flashcard viene eliminata.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Ripassi negli ultimi 7 giorni") { dayRows(stats.recentDays) }
                    Section("In programma nei prossimi 7 giorni") {
                        dayRows(stats.forecast)
                        Text("Oggi comprende anche le flashcard scadute. Le previsioni cambiano dopo ogni ripasso.").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let error { Text(error).foregroundStyle(.red) } else { ProgressView() }
            }.navigationTitle("Statistiche di studio")
                .task {
                    do { let catalog = try await model.workspace.catalog(); stats = .make(cards: catalog.studyCards ?? [], events: catalog.reviewLog ?? []) }
                    catch { self.error = error.localizedDescription }
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
    private func dayRows(_ days: [StudyDay]) -> some View {
        let maximum = max(1, days.map(\.count).max() ?? 1)
        return ForEach(days) { day in
            HStack {
                Text(day.date, format: .dateTime.weekday(.abbreviated).day()).frame(width: 76, alignment: .leading)
                ProgressView(value: Double(day.count), total: Double(maximum)).tint(Brand.accent)
                Text("\(day.count)").monospacedDigit().frame(minWidth: 32, alignment: .trailing)
            }.accessibilityElement(children: .ignore).accessibilityLabel("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(day.count)")
        }
    }
}
