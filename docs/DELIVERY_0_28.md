# NeuralNotes 0.28 — selezioni, gomme e goniometro

**In sviluppo, non consegnata.** L'ultima beta caricata è 1.0.0 (142), fase 0.27. Nessuna nuova build TestFlight viene pubblicata prima di completare e verificare questa fase.

## Primo blocco

- Geometria pura del goniometro: semicerchio e cerchio, proiezione sull'arco, raggi agganciati ai gradi, soglia di 12 punti a schermo, misure in centimetri riferite alla pagina. Vista e comandi ancora da collegare.
- Classificatore condiviso per conteggio ed eliminazione per tipo. Distingue testo e note della Lente, comprende annotazioni PDF preesistenti, rispetta i blocchi e sgancia i connettori dai bersagli eliminati. L'audio viene scollegato senza eliminare registrazioni.
- Recupero di transazioni con intestazioni preparate su disco, incluse nuove pagine e ordine: validazione completa prima della prima scrittura, ripresa dopo applicazione parziale, completamento dell'indice alla fine.
- Snapshot dell'annulla con immagini proprie e disegni su file, fuori dal pacchetto: nessuna collezione di disegni dell'intero quaderno in RAM. La pulizia del quaderno non rimuove le copie necessarie all'annulla. I file esistenti non vengono sovrascritti dal ripristino.
- Budget separato per lo spazio su disco della cronologia: rimuove prima gli eventi vecchi ma conserva l'ultima operazione completa anche se grande. Smaltimento dei file fuori dal thread dell'interfaccia.

## Verifiche

Aggiunti 22 test per geometria, classificazione, ripristino dopo interruzione, 1.500 pagine, media conservati, errori di snapshot, applicazione/annulla/ripristina tra pagine e budget della cronologia. Controllo strutturale e grammaticale locale superato: 608 oggetti di progetto, 403 file Swift, 564 metodi XCTest presenti. Questo controllo **non esegue** i test e non sostituisce la compilazione SDK.

Primo collaudo [41106309619](https://github.com/sminikiller/NeuralNotes/actions/runs/41106309619), sorgenti c2dbdf2: compilazione Core riuscita, 350 dei 351 XCTest superati e 98 Swift Testing superati; un solo test di interruzione leggeva la data ISO del manifest con il decoder predefinito per numeri. Corretto il test usando lo stesso formato ISO dell'app, senza modificare il formato dei quaderni. Pacchetto Playgrounds compilato e avviato. Le successive prove includono la pubblicazione atomica di nuove pagine e il completamento di una transazione già pubblicata anche dopo la cancellazione del task.

Nuovo collaudo Apple dei sorgenti aggiornati da eseguire. I comandi di selezione/copia tra pagine, gomme selettive, eliminazione estesa e goniometro visibile non sono ancora completati; nessuna di queste basi è dichiarata disponibile nella beta 142.
