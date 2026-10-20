# Prove iPad — NeuralNotes 0.5

Percorso delle funzioni 0.5, aggiornato per 0.5.1 build 10. Per registrazione in background, doppio tocco e correzioni Audio/gesti, seguire anche [FIXES_0_5_1.md](FIXES_0_5_1.md). Le foto e la conferma dell’utente riguardano la versione precedente. Le nuove funzioni sono nel codice; compilazione e prove Apple della 0.5 non sono state eseguite su Windows.

## Avvio

Conserva il vecchio Playground e i suoi dati. Decomprimi NeuralNotes-iPad-0.5.1.zip in una cartella separata e apri NeuralNotes.swiftpm intero in Swift Playground. Le copie possono avere container distinti: trasferisci i quaderni con .nnbackup se necessario. Sidebar → Verifica sul dispositivo → Esegui controlli: **19 risultati**, inclusi PDF dalla libreria, modello pagina ed export della trascrizione.

## PDF come nuovo quaderno

Dalla libreria usa **Importa PDF o quaderno**, anche nell’icona in alto, e scegli un .pdf. Atteso: nuovo quaderno col nome del file, stesso numero di pagine e PDF originale conservato. Aprilo con Scrivi e studia, scrivi sopra il PDF, aggiungi testo/foto, riapri ed esporta. Non deve apparire un errore di backup nativo per un PDF.

Prova anche PDF protetto, file .pdf non valido e un backup valido: messaggi specifici per i PDF; il backup continua a usare il suo percorso. Un import PDF fallito non deve lasciare un quaderno vuoto in libreria. Limite invariato 100 MB/1000 pagine, senza modifica del sorgente.

## Carta, quaderni e pagine

Creando un quaderno scegli tipo, colore, passo, margine, formato e orientamento. La prima pagina viene creata quando entri nell’editor. Prova righe, quadretti, puntini e pagina libera su due quaderni con modelli diversi.

Nell’editor tocca l’**icona del foglio in alto** → Carta e formato. Cambia la pagina corrente; disattiva Usa anche per le nuove pagine per mantenere distinto il default. Aggiungi pagine e verifica il modello del quaderno. I quaderni vecchi senza default ereditano la carta dell’ultima pagina selezionata.

Prova A4, Letter, Quadrato e orientamento con contenuti già presenti: testo, immagini, forme e inchiostro vengono ridimensionati insieme; Annulla ripristina formato e contenuti. La preferenza per le pagine future resta una preferenza separata dall’undo della pagina. Cambiare carta non ricolora l’inchiostro: sull’ardesia seleziona un colore chiaro. Una pagina PDF mantiene il proprio sfondo e formato originali; il modello scelto può essere applicato alle nuove pagine vuote.

## Focus e gesti rapidi

- Premi il pulsante circolare flottante in alto a destra: spariscono anche toolbar e navigazione, resta il foglio intero con lo strumento corrente. Premi di nuovo: ritorno animato. Trascina il pulsante e verifica che resti raggiungibile dopo rotazione/finestra stretta. Un punto rosso indica il microfono attivo.
- A pagina intera, trascina verso l’alto molto oltre il bordo inferiore. Deve comparire Rilascia per avanzare; al rilascio vai alla pagina successiva, oppure viene creata una nuova pagina se sei all’ultima. Un trascinamento breve o uno spostamento mentre sei zoomato non deve creare pagine. L’aggiunta è annullabile. Usa le dita per scorrere; con disegno tramite dito attivo usa lo scroll a due dita.
- Carta e gesti rapidi → controlla Scarabocchio per cancellare (attivo inizialmente nella 0.5.1, salvo preferenze precedenti). Disegna uno zig-zag continuo ripetuto: cancella parole digitate e la zona di inchiostro attraversata, poi prova Annulla/Ripristina. Cerchi e linee semplici non devono cancellare. Il gesto è euristico; la grafia non viene interpretata semanticamente. Immagini e forme restano intatte.

## Trascrizioni, nomi, correzioni ed export

Il riconoscimento resta Apple Speech esclusivamente on-device. La conferma «ora pare che funzioni» riguarda il precedente riconoscimento. Non si promette precisione o durata illimitata della nuova gestione senza provarla.

1. Termina e salva una registrazione parlata di almeno 2–3 minuti. Premi Trascrivi: avanzamento per blocchi di 45 secondi e risultati salvati progressivamente.
2. Chiudi soltanto il pannello Audio e continua a scrivere: la trascrizione deve continuare. Riapri Audio e controlla avanzamento e testo.
3. Premi Pausa trascrizione, esci dal quaderno, riapri e premi Riprendi: i blocchi salvati non devono essere rifatti. Background/chiusura interrompono cooperativamente il lavoro, senza garantire esecuzione in background.
4. Audio → **Rinomina / correggi**: cambia nome e testo del minuto interessato, salva e riapri. Nome condiviso da registrazione e trascrizione; il CAF non cambia. Non si modificano testi mentre un riconoscimento è attivo.
5. Correggi un minuto già trascritto prima della ripresa di una trascrizione parziale: la correzione deve restare. Copre l’intero minuto, inclusi eventuali altri risultati di quel minuto arrivati alla ripresa.
6. **Esporta testo** → Salva su File. Il .txt contiene nome e righe [00:00:00], [00:01:00]…; oltre un’ora usa [01:00:00]. È un raggruppamento circa ogni minuto, non la precisione parola per parola dopo una correzione. I silenzi non producono righe vuote obbligatorie; un risultato incompleto viene marcato Trascrizione parziale.
7. Ripeti con una registrazione reale lunga e pausa/ripresa: annota durata, punto di eventuale errore e disponibilità dei risultati precedenti. Timeout o errore Apple devono indicare il blocco interessato e lasciare la ripresa disponibile.

Le trascrizioni complete delle vecchie versioni restano leggibili/modificabili/esportabili. La lingua/modello italiano on-device dipende dal sistema. Nessun audio viene inviato online come ripiego. I nuovi checkpoint aumentano i metadati: prestazioni e cataloghi grandi sono da misurare, così come registrazioni hardware lunghe.

## Regressioni e test

Ripetere foto/ritaglio, selezione mista, cronologia, PDF vettoriale, backup reimportato e recupero/spazio del percorso [0.4](TESTING_0_4.md). La prova sintetica facoltativa resta 50 pagine + CAF60s, non sostituisce una lezione reale.

Forniti **89 XCTest** (52 core, 31 integrazione, 6 UI), non eseguiti qui. Il test audio usa un CAF sintetico 95s e riconoscitore iniettato per provare fallimento, checkpoint, ricreazione del controller, ripresa e correzioni: non testa la qualità di Apple Speech. UI test del focus fornito. Su Mac eseguire tools/verify_macos.sh e conservare .xcresult.

Annotare risultati in [ACCEPTANCE.md](ACCEPTANCE.md). Restano da verificare build, gesti/Pencil, layout/accessibilità e prestazioni sul dispositivo.
