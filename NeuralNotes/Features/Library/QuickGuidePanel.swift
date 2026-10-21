import SwiftUI

@MainActor
struct QuickGuidePanel: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarding.completed") private var completed = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "book.pages.fill").font(.system(size: 46)).foregroundStyle(Brand.accent).accessibilityHidden(true)
                    Text("Uno spazio per pensare").font(.largeTitle.bold())
                    Text("Scrivi, registra le lezioni e ritrova le fonti senza interrompere gli appunti.").font(.title3).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                        card("pencil.tip", "Scrivi con Pencil", "Le dita spostano il foglio. Il doppio tocco alterna pagina intera e larghezza dello schermo. Scegli lo scorrimento dal comando Navigazione.")
                        card("slider.horizontal.3", "Strumenti subito disponibili", "Tieni premuto uno strumento per le sue opzioni. I workspace conservano preferiti e colori per attività; Solo foglio mantiene una piccola toolbar espandibile.")
                        card("waveform", "Audio e fonti", "Il punto rosso segnala la registrazione anche in focus. Puoi rinominare, correggere ed esportare le trascrizioni, oppure tornare all’audio dai tratti collegati.")
                        card("folder", "Trova il tuo percorso", "Organizza con cartelle, sezioni e segnalibri. La ricerca trova testo, PDF e grafia indicizzata; i collegamenti riportano alla pagina d’origine.")
                        card("externaldrive.badge.checkmark", "Conserva i quaderni", "I salvataggi sono sul dispositivo. Puoi esportare backup e scegliere una cartella esterna per le copie automatiche. Una copia del Playground può avere una libreria separata.")
                        card("sparkles", "Studia dalle tue fonti", "Glossario, flashcard e ripasso funzionano anche senza AI generativa. I motori remoti inviano soltanto le fonti della richiesta dopo l’attivazione nella Connessione AI.")
                    }
                    Button("Inizia a scrivere", systemImage: "arrow.right") { completed = true; dismiss() }.buttonStyle(.borderedProminent).controlSize(.large)
                }.padding(28).frame(maxWidth: 1000)
            }.navigationTitle("Guida rapida").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { completed = true; dismiss() } } }
        }
    }
    private func card(_ icon: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(Brand.accent).accessibilityHidden(true)
            Text(title).font(.headline); Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Brand.surface, in: RoundedRectangle(cornerRadius: 22))
            .accessibilityElement(children: .combine)
    }
}
