# NeuralNotes 0.27 — Diagrammi, connettori e correzioni di scrittura

**In collaudo, non consegnata.** Ultima beta caricata: 1.0.0 (135), fase 0.26. Nessuna modifica a firma, identità o servizi esterni.

## Implementato
- Quattro punti blu per duplicare un blocco e collegarlo in un solo annulla, con distanza di 48 punti e controllo dello spazio. Trascinamento su contorni ruotati, estremi liberi con sosta, riaggancio e maniglia di curvatura.
- Connettori dritti, curvi e ortogonali che seguono gli oggetti anche nell’anteprima di trascinamento, ridimensionamento e rotazione, senza scritture su disco durante il gesto. Oggetto eliminato: estremo libero nell’ultima posizione.
- Etichette RTF centrate e contenute, riduzione facoltativa del carattere, elenchi e rientri. Mappe AI con blocchi e collegamenti modificabili e fonti conservate.
- Selezione lungo il tracciato reale, frecce comprese; copia, spostamento, trasformazioni, replay, ricerca, PDF e backup includono collegamenti ed etichette. Clone nativo rimappa fonti e ancore audio.
- Evidenziatore da 1 a 80 punti reali, recenti separati, composizione moltiplica con PDF e penna sopra. Aggancio alle parole digitali del PDF riusa la geometria della Lente, senza avviare OCR delle scansioni. Originali e disegni PK conservati.
- Riconoscimento confermato fino al rilascio; reset esplicito della sessione nativa dopo la conversione per evitare ricomparsa del tratto grezzo. Regressioni per movimento minimo, tratto successivo, annulla e ripristina.
- Guida e Novità, comandi italiani e VoiceOver. I campi aggiunti ai modelli preesistenti sono opzionali.

## Prove
Primo pre-collaudo [40945883449](https://github.com/sminikiller/NeuralNotes/actions/runs/40945883449): 327 Core senza fallimenti; isolamento del renderer ed espressione complessa delle forme corretti dopo gli errori di compilazione.
Secondo pre-collaudo [40948901500](https://github.com/sminikiller/NeuralNotes/actions/runs/40948901500), sorgenti 99b77d4: 329 Core + 98 Swift Testing superati, pacchetto Playgrounds compilato e avviato; quattro regressioni native dei diagrammi superate. Due asserzioni di un test preesistente conteggiavano anche il nuovo doppio tocco Pencil per le etichette come gesto zoom: ora i due gesti zoom e il gesto etichetta sono verificati separatamente. Un test UI della barra pagine ha osservato il cambio orientamento prima che terminasse: attesa dello stato reale, mantenendo tutti i limiti di dimensioni.
Aggiunte fixture 0.26 e regressioni native PDF/backup, rimappatura fonti/audio, riaggancio, sosta, testo nero leggibile e riconoscimento. Test UI dello schema a sei blocchi e dell’etichetta. Nuovi sorgenti e test attendono il successivo collaudo SDK; il controllo grammaticale locale non li esegue.

## Prima della consegna
Verifica completa di tutti i job, analisi degli eventuali fallimenti reali, controllo visivo degli screenshot e ZIP esatto compilato. Solo dopo: TestFlight con SHA verificato. Nessuna nuova beta dichiarata disponibile prima della conferma del caricamento. Fluidità e falsi positivi su iPad 10/Pencil fisici restano distinti dalle prove sintetiche e sul simulatore. Lotti 0.28–0.31 ancora successivi, non dichiarati conclusi.


### Rifiniture successive al pre-collaudo 6fafef3
Il compositore dell’evidenziatore mantiene al massimo due immagini dell’area visibile (due milioni di pixel ciascuna) e aggiorna solo l’inchiostro del gesto: nessuna rilettura del PDF per campione. Una prova controlla dodici aggiornamenti con un’unica ricostruzione. Le parole molto strette sono mascherate al loro rettangolo; pagine ruotate usano lo stesso trasformato del rendering, verificato confrontando i riquadri con i glifi rasterizzati a 0/90/180/270 gradi. Nuove prove da eseguire sulla revisione successiva.
Riferimento tecnico della trasformazione: [CGPDFPage Apple](https://developer.apple.com/documentation/CoreGraphics/CGPDFPage), coerente con la geometria già usata dallo studio PDF.


### Pre-collaudo 41063870261 — 6fafef3
[Run Apple](https://github.com/sminikiller/NeuralNotes/actions/runs/41063870261): Core **333 XCTest + 98 Swift Testing superati**; **129 test nativi con due asserzioni fallite nello stesso test dell’evidenziatore**. Passati i sei test nativi dei diagrammi, due di compatibilità 0.26/backup, riconoscimento con piccoli movimenti e nuovo tratto; passati **tutti i tre flussi UI selezionati** (schema sei blocchi con etichetta, doppio tocco zoom, barra pagine e orientamento), più build Release. Playgrounds: compilazione simulatore/dispositivo e avvio dello ZIP con 60 controlli superati.
I fallimenti hanno mostrato problemi reali, non limiti da allargare nel test: PencilKit impone 7,5 pt al proprio pennino marker; UIImage.draw ripristinava la fusione normale. Correzioni: sotto validWidthRange si registrano direttamente punti PKStroke della larghezza richiesta, mantenendo gomma/annulla/riconoscimento; la fusione viene passata esplicitamente a UIImage.draw. Il test ora misura anche la geometria effettiva del tratto libero da 1 pt. Le asserzioni di leggibilità rimangono invariate. Le rifiniture cache/rotazione e il test UI nativo di riconoscimento attendono la prossima revisione.

### Pre-collaudo 41067587689 — sorgenti 421db12
[Verifica](https://github.com/sminikiller/NeuralNotes/actions/runs/41067587689): **333 XCTest Core + 98 Swift Testing e tutti i 133 test nativi selezionati superati**. Passati tratto libero da 1 pt (anche geometria renderizzata), parole digitali, leggibilità del testo nero, PDF ruotati, riuso della cache, penna bianca sopra il colore, ancore audio/fonti nei backup e tutti i sette test dei diagrammi. Il nuovo test UI con scrittura reale PencilKit, conversione, cancellazione della forma, nuovo tratto e annulla/ripristina è passato; passato anche lo schema UI di sei blocchi. Compilazioni Release e Playgrounds simulatore/dispositivo più avvio dello ZIP superati.
Il solo test UI dello zoom ha esaurito l’attesa iniziale, prima di inviare gesti: schermata e gerarchia mostrano pagina correttamente intera. Il waiter sincrono sul MainActor è sostituito da quello asincrono, mantenendo **stesso timeout di 15 secondi, stesso valore e stessa condizione di hittability**. Riferimento: [XCTWaiter.fulfillment Apple](https://developer.apple.com/documentation/xctest/xctwaiter/fulfillment(of:timeout:enforceorder:)-swift.type.method). La modifica riguarda soltanto il test, nessuna variazione al comportamento di zoom confermato dall’utente. Verifica completa da eseguire sulla revisione aggiornata.
