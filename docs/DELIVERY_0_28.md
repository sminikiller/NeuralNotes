# NeuralNotes 0.28 — selezioni, gomme e goniometro

**In sviluppo, non consegnata.** L'ultima beta caricata è 1.0.0 (142), fase 0.27. Nessuna nuova build TestFlight viene pubblicata prima di completare e verificare questa fase.

## Primo blocco

- Goniometro collegato all'editor: semicerchio e cerchio, graduazioni, trascinamento/rotazione/dimensione, archi e raggi precisi, misura di due raggi senza aggiungere inchiostro. Lo strumento resta agganciato fino al rilascio. Comandi accessibili e opzioni con pressione prolungata; righello e goniometro sono alternativi. Il righello mostra lunghezza in centimetri e angolo durante il tratto. Nuove scorciatoie G e R. Queste modifiche sono ancora da compilare e provare con SDK Apple.
- Classificatore condiviso per conteggio ed eliminazione per tipo. Distingue testo e note della Lente, comprende annotazioni PDF preesistenti, rispetta i blocchi e sgancia i connettori dai bersagli eliminati. L'audio viene scollegato senza eliminare registrazioni.
- Recupero di transazioni con intestazioni preparate su disco, incluse nuove pagine e ordine: validazione completa prima della prima scrittura, ripresa dopo applicazione parziale, completamento dell'indice alla fine.
- Snapshot dell'annulla con immagini proprie e disegni su file, fuori dal pacchetto: nessuna collezione di disegni dell'intero quaderno in RAM. La pulizia del quaderno non rimuove le copie necessarie all'annulla. I file esistenti non vengono sovrascritti dal ripristino.
- Budget separato per lo spazio su disco della cronologia: rimuove prima gli eventi vecchi ma conserva l'ultima operazione completa anche se grande. Smaltimento dei file fuori dal thread dell'interfaccia.

## Verifiche

Aggiunti 22 test per geometria, classificazione, ripristino dopo interruzione, 1.500 pagine, media conservati, errori di snapshot, applicazione/annulla/ripristina tra pagine e budget della cronologia. Controllo strutturale e grammaticale locale superato: 608 oggetti di progetto, 403 file Swift, 564 metodi XCTest presenti. Questo controllo **non esegue** i test e non sostituisce la compilazione SDK.

Primo collaudo [41106309619](https://github.com/sminikiller/NeuralNotes/actions/runs/41106309619), sorgenti c2dbdf2: compilazione Core riuscita, 350 dei 351 XCTest superati e 98 Swift Testing superati; un solo test di interruzione leggeva la data ISO del manifest con il decoder predefinito per numeri. Corretto il test usando lo stesso formato ISO dell'app, senza modificare il formato dei quaderni. Pacchetto Playgrounds compilato e avviato. Le successive prove includono la pubblicazione atomica di nuove pagine e il completamento di una transazione già pubblicata anche dopo la cancellazione del task.

Il secondo collaudo mirato [41130444981](https://github.com/sminikiller/NeuralNotes/actions/runs/41130444981), sorgenti 147c103, è verde: Core, test nativi selezionati, prova UI del tratto dopo riconoscimento e pacchetto Playgrounds compilato e avviato. Comprende la correzione del test ISO; non comprende ancora il nuovo goniometro nell'interfaccia.

Blocco successivo pronto per collaudo: un solo evento di annulla su disco nell'editor; prova con immagine cancellata e recuperata dopo pulizia; invalidazione delle parole OCR dopo gomma parziale e rifiuto dei risultati OCR arrivati in ritardo; decodifica tollerante delle preferenze contenenti strumenti futuri. Cinque prove native del goniometro e una UI verificano archi, raggi, misura, annulla e accessibilità. Controllo locale aggiornato: 624 oggetti, 411 file Swift, 574 metodi XCTest presenti, grammatica valida; non è ancora una verifica SDK.

I comandi di selezione/copia tra pagine, gomme selettive ed eliminazione estesa restano da completare. Nessuna funzione della fase 0.28 è dichiarata disponibile nella beta 142.
