import SwiftUI
import NeuralNotesCore

/// Proposed flashcards stay editable drafts until the student saves the ones to keep.
@MainActor
struct FlashcardDraftsEditor: View {
    @Binding var drafts: [FlashcardDraft]
    @Binding var discarded: Set<UUID>
    let title: String
    let busy: Bool
    let onSave: ([FlashcardDraft]) -> Void
    var body: some View {
        Section(title) {
            ForEach($drafts) { $draft in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Tieni", isOn: Binding(get: { !discarded.contains(draft.id) },
                                                  set: { keep in if keep { discarded.remove(draft.id) } else { discarded.insert(draft.id) } }))
                    TextField("Domanda", text: $draft.question, axis: .vertical)
                    TextField("Risposta", text: $draft.answer, axis: .vertical).foregroundStyle(.secondary)
                }.opacity(discarded.contains(draft.id) ? 0.45 : 1)
            }
            Button("Salva \(kept.count) flashcard", systemImage: "tray.and.arrow.down") { onSave(kept) }.disabled(busy || kept.isEmpty)
            Button("Scarta le bozze", role: .destructive) { drafts = []; discarded = [] }.disabled(busy)
        }
    }
    private var kept: [FlashcardDraft] { drafts.filter { !discarded.contains($0.id) && $0.isValid } }
}
