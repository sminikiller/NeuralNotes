# NeuralNotes 0.28 — selezioni, gomme e goniometro

**Firmata e caricata su Apple il 1 novembre 2026: TestFlight 1.0.0 (159).** [Invio riuscito41264713554](https://github.com/sminikiller/NeuralNotes/actions/runs/41264713554): `Upload succeeded`, `EXPORT SUCCEEDED` e `UPLOAD_COMMAND_SUCCEEDED` alle02:26:23UTC. L’elaborazione Apple e la comparsa nell’app TestFlight non sono ancora confermate. Il gruppo interno già configurato distribuisce automaticamente le build dopo l’elaborazione.

## Funzioni implementate

- Selezione tra pagine: miniature ricercabili, copia o sposta, nuova pagina dopo questa o alla fine, ridimensionamento proporzionale, identità nuove per le copie. Una transazione comprende entrambe le pagine e l’ordine; un annulla ripristina tutto. Foto originali e raddrizzamento, testo ricco, note, rimandi audio e connettori vengono conservati.
- Striscia temporanea di miniature per trascinare una selezione senza aprire finestre durante il gesto. La striscia si sovrappone al foglio senza ridurlo. Alternativa accessibile con tocco della destinazione; rifiuto di ticket scaduti, riutilizzati, cambiati o appartenenti a un’altra finestra. Il gesto reale, l’annulla e la conservazione dello spazio del foglio sono verificati nella suite completa sul simulatore. Le opzioni con pressione prolungata e i comandi della selezione sono disponibili anche nella mini toolbar di Solo foglio; il pop-up laterale si chiude prima del trascinamento.
- PNG trasparente a risoluzione doppia con soli elementi selezionati: copia e condivisione, nessuna carta/PDF o oggetto non selezionato, limiti verificati prima dell’allocazione. Il ritaglio OCR resta separato.
- Gomma per tutto, evidenziatore, penna, forme/connettori, testo/post-it e immagini. Il contatto segue la geometria visibile, compresi tratti mascherati, rotazioni e tratteggi. La modalità parziale riguarda l’inchiostro; gli oggetti vengono eliminati interi. Blocchi rispettati, un annulla per passata. Indice spaziale, contorni calcolati soltanto per i candidati e composizione carta/PDF preparata una sola volta per gesto.
- Eliminazione per tipo su questa pagina, pagine selezionate o tutto il quaderno: conteggi, conferma, backup preventivo obbligatorio sull’intero quaderno, blocco durante registrazione/compressione. Collegamenti audio rimuove i rimandi, conservando sessioni e trascrizioni. Conteggio e preparazione scorrono una pagina alla volta.
- Goniometro 180°/360°, tacche di un grado e numeri ogni dieci, spostamento, rotazione e dimensione. Archi e raggi con aggancio mantenuto fino al rilascio, misura di due raggi senza aggiungere inchiostro. Righello con centimetri e inclinazione; G/R da tastiera. Guide alternative, opzioni con pressione prolungata, VoiceOver.
- Annulla su disco per interventi tra pagine: snapshot fuori dal pacchetto, media propri, budget distinto dalla RAM, conservazione dell’ultimo intervento completo. Journal riprendibile dopo interruzione, indice pubblicato alla fine. Pulizia delle sole copie di cronologia abbandonate; esclusi quaderni, backup e finestre attive.
- Regressioni: cronologia nativa rinnovata dopo modifiche programmatiche, confronto completo delle proprietà pubbliche dei tratti anziché dell’identità privata del contenitore PKDrawing; risultati OCR tardivi rifiutati e cache invalida dopo gomma parziale.

## Ultime correzioni incluse

- Interruttore **Cancella anche gli oggetti** nelle opzioni della gomma: foto, testi e forme si possono includere o proteggere; gli oggetti bloccati rimangono protetti. Le evidenziazioni per parola restano nella categoria evidenziatore.
- Frecce rapide **Annulla/Ripristina** in un piccolo overlay in alto a sinistra, anche in Solo foglio. Usano la stessa cronologia e non riducono lo spazio della pagina.
- Evidenziatore **Parole / Tratto libero**. Parole usa lo stesso selettore della Lente per PDF, testi inseriti, etichette, scansioni e grafia riconosciuta. Una passata crea rettangoli vettoriali per parola, senza aggiungere inchiostro sintetico; ripetere lo stesso colore non scurisce le sovrapposizioni. Una passata vuota o annullata non lascia tratti accidentali. Tratto libero conserva la larghezza minima di1pt.
- Riquadri del testo ricavati dai glifi effettivi: sottolineare una parola non aggancia più accidentalmente la riga successiva. Cache OCR conservata per evidenziazione, annulla e salvataggio; una richiesta aggiornata attende la fine della lettura obsoleta e ne rifiuta il risultato. Gli errori invariati non generano tentativi senza fine.

## Verifiche della consegna

Sorgenti verificati: `52e150cb2cddec6c6257e148f4e580478d0c1587`. Il commit di invio `04a766a63e4c10454054b69df227a22b51b7d63e` cambia soltanto documentazione; il confronto dei sorgenti dell’app è vuoto.

[Verifica completa41248574248](https://github.com/sminikiller/NeuralNotes/actions/runs/41248574248): **sei job verdi**. Core macOS369 test; sul simulatore587 XCTest (due saltati, zero errori) e98 SwiftTesting; tutte le43 prove UI superate. Superati anche aggiornamento conservando il quaderno, build Release, compilazione e avvio del pacchetto Playgrounds e archivio. La mirata [41247014377](https://github.com/sminikiller/NeuralNotes/actions/runs/41247014377) aveva già superato202 prove native e tre UI delle correzioni.

Le prove controllano singole parole, copertura dei glifi realmente renderizzati, PDF nero leggibile, sovrapposizioni senza scurimento, cancellazione selettiva, annulla/ripristina, rifiuto di OCR obsoleto e dati nativi preesistenti. La fixture0.27 conserva aspetto, diagrammi, foto e preferenze attraverso apertura, salvataggio, PDF e backup/import. Le schermate della suite completa sono state ispezionate: selezione delle parole, frecce in Solo foglio, miniature per trascinamento, gomma e goniometro.

## Pacchetto esatto

ZIP della CI: `NeuralNotes-iPad-0.28.0.zip`, copiato in `.verification/NeuralNotes-iPad-0.28.0.zip`. Verificati CRC, insieme esatto dei file, manifest e corrispondenza di tutti i320 sorgenti/risorse al commit verificato.

SHA256: `a700801f8676b332218420242203a969c235f361677e8654a4af5d0ce147c7cb`.

## Confini

La beta firmata usa il Bundle ID esistente e iCloud disattivato, come le precedenti. Nessuna modifica a firma, segreti, corsia TestFlight o servizi esterni. Nessuna migrazione distruttiva e nessun intervento sui quaderni o backup personali. Il compasso era facoltativo e non è incluso. Tempi e fluidità della Pencil fisica non vengono dedotti dal simulatore.

La fase0.28 è consegnata; le fasi0.29,0.30 e0.31 del piano rimangono successive.
