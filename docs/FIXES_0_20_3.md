# Correzione 0.20.3 / build 39 — conflitto UIKit della Lente

23 ottobre 2026. La schermata dell'iPad documenta che la **0.20.2 non compila**: `LensNotesOverlay` dichiara una proprietà privata `hidden: UUID?`, che collide con la proprietà booleana ereditata da UIKit. I precedenti controlli di sintassi non potevano verificare le dichiarazioni dell'SDK Apple; la dichiarazione era rimasta anche nella consegna 0.20.2.

La proprietà dell'overlay ora si chiama `draggedNoteID` in dichiarazione, aggiornamento e confronto. Continua a identificare solo la nota esclusa dall'overlay durante il trascinamento; `isHidden` mantiene la normale funzione di visibilità della vista. Non viene aggiunto un override.

In `SearchHighlight` l'elenco locale `boxes` ora è `let`, perché non viene modificato. Era un avviso, distinto dall'errore bloccante della Lente.

Lo script di verifica analizza anche le proprietà `hidden` nelle sottoclassi UIKit elencate nel controllo, con fixture che rifiuta la dichiarazione errata e accetta il nome dedicato e lo stato di una normale struct. È una protezione mirata contro questo errore noto, non un controllo completo dei nomi riservati o una compilazione SDK.

Verificati grafo/membership del progetto, grammatica Swift, protezione AST e parsing con Swift 6.1.2 in modalità Swift 5; pacchetti controllati byte per byte. **Compilazione Apple e avvio della 0.20.3 sull'iPad non eseguiti.** La CI resta bloccata per fatturazione come documentato nelle [verifiche](ROADMAP_VALIDATION.md); nessun tentativo identico ripetuto. Il fallimento reale della 0.20.2 rimane registrato.

Core e backend non cambiano e non vengono rieseguiti per questa rinomina: gli ultimi risultati sono quelli della 0.20.2, 259 XCTest Core (257 passati e due skip Darwin), 98 FSRS e 48 test backend; integrazione account locale reale con modello simulato. Nessuna nuova prova live AI o hardware è implicita.

`NeuralNotes-iPad-0.20.3.zip` contiene tutte le funzionalità della [0.20.2](DELIVERY_0_20_2.md) e questa patch. Decomprimere in una cartella nuova e aprire `NeuralNotes.swiftpm` intero. Conservare il vecchio Playground e i quaderni: la patch non richiede reset dei dati e non modifica il formato dei documenti.
