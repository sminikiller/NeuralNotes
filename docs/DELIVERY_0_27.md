# NeuralNotes 0.27 — Diagrammi e connettori

**In sviluppo, non consegnata e non verificata con SDK Apple.** Ultima beta caricata: 1.0.0 (135), fase 0.26. Nessuna modifica a firma, identità o servizi esterni.

## Base implementata
- Modelli opzionali e validazione di connettori, etichette nelle forme e riferimenti alle fonti. Decodifica tollerante del tracciato; riferimenti mancanti risolti come estremi liberi.
- Geometria condivisa per contorni ruotati, estremi che seguono gli oggetti, curve, gomiti con uscita perpendicolare e percorso intorno ai due blocchi collegati, selezione del tracciato e punte.
- Impaginazione delle etichette RTF centrata e contenuta, con riduzione facoltativa del carattere e percorso condiviso per schermo/PDF/ricerca delle parole.
- Le mappe AI usano blocchi arrotondati con etichette e connettori curvi, mantenendo le fonti. Il limite preesistente di otto rami è conservato.
- Prima integrazione di selezione, doppio tocco per le etichette e annulla. Base per duplicazione collegata con distanza di 48 punti e controllo dello spazio.

## Ancora da completare prima della consegna
- Punti blu e gesti di creazione/modifica dei connettori; anteprima che segue il trascinamento senza riscrivere continuamente il documento.
- Tutti i percorsi di copia, spostamento, trasformazione, riproduzione audio e import/clone; menu stile e fonti; rifiniture di accessibilità e tema.
- Fixture 0.26, prove native di annulla/PDF/backup e test UI dello schema di sei blocchi; Guida e Novità.
- Verifica completa e successiva build TestFlight dei sorgenti corrispondenti.

## Prove attuali
Controllo strutturale e grammaticale superato: 564 oggetti di progetto, 374 file Swift, 518 metodi XCTest presenti. **Questi controlli non compilano Swift né eseguono i test.** Aggiunti otto test Core per contorni ruotati, magnete, distacco, percorsi ortogonali, curve, identità, dati malformati e disposizione dei blocchi. Il collaudo Apple preliminare va eseguito prima di attribuire risultati a questi test.
