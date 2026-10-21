# NeuralNotes 0.10.0, build 20 — anteprima

Questa consegna aggiorna sorgenti e App Playground; non è una build iPad firmata né una versione dichiarata completa. La compilazione e i test Apple delle ultime modifiche sono ancora aperti perché GitHub non avvia i job per un blocco di fatturazione. La versione mantiene lo schema della libreria SwiftData e il formato quaderno v1, con nuovi campi opzionali.

## Accesso alle funzioni

| Funzione | Comando |
| --- | --- |
| Opzioni dello strumento | Tieni premuta l’icona di penna, evidenziatore, gomma, selezione, forme, testo, righello o Lente. |
| Sezioni/sottosezioni | Anteprime pagine → Sezioni. Dal menu dell’anteprima assegna la pagina; il filtro comprende le sottosezioni. |
| Collegamenti e fonti in entrata | Anteprime pagine → Collegamenti. Crea un testo collegato oppure consulta le pagine che puntano a quella corrente. |
| Estratto PDF collegato | Pannello PDF → seleziona testo → Inserisci estratto con fonte. Con Oggetti, seleziona l’estratto e toccalo di nuovo per aprire la pagina originale. |
| Definizione con fonti | Lente AI → Scheda definizione. Il dizionario di sistema funziona senza backend; la scheda strutturata richiede il backend configurato e consenso. |
| Glossario | Lente o pannello Studio → Glossario; modifica voci e crea flashcard con la fonte. |
| Statistiche | Flashcard e ripasso → Statistiche. Valutazioni reali, andamento giornaliero e scadenze; nessuno storico precedente viene inventato. |
| Capitoli della trascrizione | Audio → Visualizza trascrizione → Per capitoli. Capitoli ogni cinque minuti e ai segnalibri personali, senza riassumere il testo. |
| Export dei capitoli | Condivisione nel lettore: file `.md` con timestamp e stato completo/parziale. Esporta testo nel pannello Audio resta separato. |
| Rinomina segnalibro audio | Tieni premuta la riga del segnalibro → Rinomina. |
| Colore cartella | Tieni premuta la cartella nella libreria → Colore cartella. Preferenza locale; non richiede una migrazione della libreria. |

Gli altri lotti includono FSRS-6, carte aggiuntive, nastro di ripasso, post-it/timbri/livelli/blocco, lazo libero e trasformazioni, copia area e conversione OCR, ricerca globale con filtri, OCR dei quaderni precedenti, audio importato/segnalibri/velocità/replay, backup esterno a cartella File, motori AI configurabili e cache della Lente. L’[audit del piano](CLAUDE_PLAN_AUDIT.md) distingue gli interventi eseguiti da ciò che manca.

## File e dati esistenti

Il pacchetto viene generato in `.verification/NeuralNotes-iPad-0.10.0.zip` e contiene `NeuralNotes.swiftpm`. Il progetto completo è in `.verification/NeuralNotes-Sorgenti-0.10.0.zip`. Generazione e checksum verificano che i sorgenti siano gli stessi del progetto; non compilano Swift.

Conservare il vecchio Playground e i backup dei quaderni. Una copia del progetto aperta come nuova app in Swift Playgrounds può usare un contenitore dati distinto: la libreria della copia precedente non viene trasferita automaticamente. Un quaderno assente nella nuova copia non prova che quello originale sia stato cancellato. L’import del backup conserva nuove identità e i file originali.

Le prove eseguite e i limiti effettivi sono nel [report di verifica](ROADMAP_VALIDATION.md), incluso il difetto intermittente del campo testo ancora aperto. Fotocamera, scanner, Pencil e standby richiedono anche la prova fisica; nessuna di queste prove viene dichiarata eseguita dal solo controllo sintattico.
