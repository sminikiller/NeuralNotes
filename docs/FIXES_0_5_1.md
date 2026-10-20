# Correzioni 0.5.1 — build 10

## Registrazione con schermo bloccato e altre app

La precedente gestione scenePhase chiamava Pausa appena l’app perdeva lo stato attivo. Ora salva pagina e metadati audio senza fermare AVAudioRecorder; il progetto Xcode e il plist aggiuntivo del Playground dichiarano UIBackgroundModes/audio. Al ritorno controlla se il recorder è ancora attivo: un’interruzione del sistema viene segnalata e lascia disponibile Riprendi. Le interruzioni audio reali e la chiusura esplicita del quaderno continuano a sospendere la registrazione. La trascrizione Speech resta sospesa in background e può riprendere dai checkpoint.

Il pannello Audio segnala se il bundle effettivo espone audio in background. Il supporto del runner Swift Playground e il comportamento con blocco schermo vanno verificati sul dispositivo; dichiarare la modalità non garantisce registrazione dopo arresto forzato o terminazione del processo. Riferimento Apple: [registrazione e UIBackgroundModes/audio](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record).

Prova con un quaderno temporaneo: avvia una registrazione, parla indicando il tempo, blocca lo schermo per due minuti, torna e parla ancora. Ripeti passando a un’altra app per due minuti. Termina e ascolta anche la parte intermedia: il solo contatore non basta. Ripeti con una registrazione lunga e con un’interruzione audio; annota durata, eventuali avvisi e se il runner espone la modalità.

## Doppio tocco per pagina intera

Doppio tocco con un dito sul foglio: zoom e posizione tornano a mostrare la pagina intera, con animazione. Con disegno tramite dito attivo si usa il doppio tocco con due dita. È incluso il doppio clic del puntatore nella modalità ordinaria. Apple Pencil resta dedicata alla scrittura.

Prova dopo zoom e spostamento, anche in focus e dopo rotazione; i contenuti devono restare identici. Controlla anche selezione oggetti e collegamenti audio con tocco singolo.

## Scarabocchio per cancellare

La soglia precedente ignorava i piccoli movimenti ravvicinati: adesso accumula i cambi di direzione e riconosce anche zig-zag più piccoli. Il gesto è attivo inizialmente, salvo una preferenza esplicita già salvata; si cambia in Carta e gesti rapidi. Richiede una penna e uno zig-zag continuo ripetuto.

Il testo digitato perde le parole attraversate in base alla loro posizione. Per la grafia, viene mascherata la zona attraversata: il resto di un tratto collegato rimane. Le maschere sono persistenti, compatibili con export vettoriale e Annulla/Ripristina. Non riconosce semanticamente le parole scritte a mano. Immagini e forme restano intatte.

Prova su una parola di una casella con più parole e su una parola manoscritta collegata alla successiva. Controlla il resto della riga, Annulla, Ripristina, riapertura e PDF esportato. Ripeti due cancellazioni sullo stesso tratto. Una linea o un cerchio semplice non devono essere interpretati come scarabocchio. La natura euristica del gesto richiede prove con la propria grafia.

## Pulsanti Audio indipendenti

Rinomina / correggi ed Esporta testo ora occupano righe separate, con stile pulsante esplicito e un’unica presentazione esclusiva. Il tap su una riga non deve più avviare le due azioni insieme.

Apri una trascrizione: Rinomina / correggi deve mostrare solo l’editor; annulla o salva e premi Esporta testo, che deve aprire solo il foglio di condivisione del TXT. Ripeti dopo aver chiuso entrambi i pannelli.

## Verifica disponibile

Sette nuovi XCTest: zig-zag con campioni ravvicinati; maschere successive e riapertura senza cancellare il resto del tratto; parole digitate; zoom pagina intera; cancellazione con undo/redo; due UI test per i pulsanti Audio. La fixture UI crea solo metadati in uno storage temporaneo isolato, con argomenti DEBUG espliciti; non accende il microfono né verifica Speech.

Totale 89 XCTest forniti e 19 controlli incorporati. In questo ambiente Windows sono stati verificati struttura, grammatica e pacchetti: nessuna build Apple, XCTest o prova hardware eseguita. Vedi [validazione effettiva](VALIDATION.md). Conserva il progetto precedente e trasferisci i quaderni mediante backup prima di abbandonarlo.
