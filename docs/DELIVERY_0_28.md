# NeuralNotes 0.28 — selezioni, gomme e goniometro

**In collaudo, non consegnata.** Ultima beta caricata: 1.0.0 (142), fase 0.27. Nessuna pubblicazione 0.28 prima della verifica completa.

## Funzioni implementate

- Selezione tra pagine: miniature ricercabili, copia o sposta, nuova pagina dopo questa o alla fine, ridimensionamento proporzionale, identità nuove per le copie. Una transazione comprende entrambe le pagine e l’ordine; un annulla ripristina tutto. Foto originali e raddrizzamento, testo ricco, note, rimandi audio e connettori vengono conservati.
- Striscia temporanea di miniature per trascinare una selezione senza aprire finestre durante il gesto. La striscia si sovrappone al foglio senza ridurlo. Alternativa accessibile con tocco della destinazione; rifiuto di ticket scaduti, riutilizzati, cambiati o appartenenti a un’altra finestra. Questo ultimo blocco richiede ancora prove SDK e del gesto reale.
- PNG trasparente a risoluzione doppia con soli elementi selezionati: copia e condivisione, nessuna carta/PDF o oggetto non selezionato, limiti verificati prima dell’allocazione. Il ritaglio OCR resta separato.
- Gomma per tutto, evidenziatore, penna, forme/connettori, testo/post-it e immagini. Il contatto segue la geometria visibile, compresi tratti mascherati, rotazioni e tratteggi. La modalità parziale riguarda l’inchiostro; gli oggetti vengono eliminati interi. Blocchi rispettati, un annulla per passata. Indice spaziale, contorni calcolati soltanto per i candidati e composizione carta/PDF preparata una sola volta per gesto.
- Eliminazione per tipo su questa pagina, pagine selezionate o tutto il quaderno: conteggi, conferma, backup preventivo obbligatorio sull’intero quaderno, blocco durante registrazione/compressione. Collegamenti audio rimuove i rimandi, conservando sessioni e trascrizioni. Conteggio e preparazione scorrono una pagina alla volta.
- Goniometro 180°/360°, tacche di un grado e numeri ogni dieci, spostamento, rotazione e dimensione. Archi e raggi con aggancio mantenuto fino al rilascio, misura di due raggi senza aggiungere inchiostro. Righello con centimetri e inclinazione; G/R da tastiera. Guide alternative, opzioni con pressione prolungata, VoiceOver.
- Annulla su disco per interventi tra pagine: snapshot fuori dal pacchetto, media propri, budget distinto dalla RAM, conservazione dell’ultimo intervento completo. Journal riprendibile dopo interruzione, indice pubblicato alla fine. Pulizia delle sole copie di cronologia abbandonate; esclusi quaderni, backup e finestre attive.
- Regressioni: cronologia nativa rinnovata dopo modifiche programmatiche, confronto completo delle proprietà pubbliche dei tratti anziché dell’identità privata del contenitore PKDrawing; risultati OCR tardivi rifiutati e cache invalida dopo gomma parziale.

## Verifiche e limiti

[41158003947](https://github.com/sminikiller/NeuralNotes/actions/runs/41158003947), commit b3825a8: verifica mirata verde, **176 prove native e 4 UI superate**, Core e Playgrounds compilati, Release compilata. Include trasferimenti/nuove pagine, annulla/ripristina, PNG, goniometro, pulizia della cronologia e cache OCR. La prova UI controlla la forma effettivamente tornata dopo Ripristina, riselezionandola come previsto dalla cronologia.

[41160440515](https://github.com/sminikiller/NeuralNotes/actions/runs/41160440515), commit c24ae00: in corso al momento di questo aggiornamento; comprende anche le nuove gomme e l’eliminazione estesa. Non comprende il trascinamento aggiunto successivamente. Non è la verifica finale di consegna.

Aggiunte prove per trasferimento tramite ticket, rifiuto dei dati obsoleti, gesto UI diretto sulle miniature e fixture 0.27 (apertura/salvataggio, diagrammi, immagine, preferenze pregresse, PDF e backup nativo). Controlli locali: struttura del progetto, grammatica Swift, integrità e risorse del pacchetto ZIP. **Non sono esecuzioni SDK**.

Restano la verifica Apple dell’ultimo blocco, la suite completa, l’aggiornamento da versione precedente, l’archivio e la consegna. Nessun tempo fisico di fluidità o prova Apple Pencil reale viene dedotto dal simulatore. Il compasso era facoltativo e non è incluso.

Nessuna modifica a identità, firma, segreti, corsia TestFlight o servizi esterni. Nessuna migrazione distruttiva dei quaderni.
