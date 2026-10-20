# NeuralNotes 0.6.1 — build 12

Correzione della regressione di layout/input introdotta nella 0.6 e segnalata dall’utente. La versione precedente non è stata verificata sul dispositivo dall’agente; i controlli grammaticali e ZIP non avevano rilevato il problema di interazione reale.

## Comportamento corretto nel codice

Il contenitore SwiftUI scorrevole esterno, lo stack di anteprime, il limite di larghezza del riquadro e la selezione automatica della pagina visibile sono stati rimossi dall’editor. DocumentPageViewport contiene sempre un solo PencilCanvas esteso a tutta l’area disponibile. Il canvas rimane montato quando si cambia modalità, con il layout precedente alla 0.6. La carta conserva le sue proporzioni e il normale adattamento/zoom; non viene deformata per riempire lo schermo.

Il default dei nuovi quaderni torna a **Pagina singola**. Le altre scelte rimangono nel menu Navigazione pagine:

- **Sfoglia verticalmente**: a pagina intera, swipe con le dita verso l’alto per la pagina successiva, verso il basso per la precedente.
- **Sfoglia orizzontalmente**: a pagina intera, swipe con le dita a sinistra/destra.
- **Pagina singola**: pulsanti in basso e trascinamento oltre il fondo configurabile per avanzare/creare una pagina.

La modalità verticale è ora uno sfoglio tra pagine nel canvas principale. Il precedente scorrimento continuo con più fogli impilati è stato rimosso. La preferenza salvata dalla 0.6 con chiave continuous viene riconosciuta come sfoglio verticale; il documento non cambia identità.

Pan e pinch del canvas escludono esplicitamente Apple Pencil. I quattro swipe delle pagine ricevono solo tocchi diretti delle dita. Con disegno tramite dito attivo servono due dita per spostarsi/sfogliare. Nessun gesto di sfoglio viene eseguito mentre lo strumento PencilKit sta tracciando un tratto o mentre una casella di testo è in modifica. Lo zoom torna a usare esclusivamente il canvas principale.

## Prova rapida su iPad

1. Conserva la vecchia copia ed esporta i quaderni importanti in .nnbackup prima di aprire un nuovo Playground. Le copie possono avere dati separati. Apri NeuralNotes.swiftpm della 0.6.1 intero e trasferisci i backup se necessario.
2. Apri un quaderno con tre pagine. In Pagina singola controlla che l’area di scrittura sia come prima, senza riquadro scorrevole interno. Prova portrait/landscape e focus.
3. Scrivi con Apple Pencil su tutta la pagina, inclusi i bordi; fai tratti lunghi verticali/orizzontali. Non devono scorrere il foglio né cambiare pagina. Riavvia la stessa copia e controlla i tratti.
4. Cambia tra le tre modalità. Il canvas deve mantenere la stessa dimensione e lo stesso contenitore. In verticale/orizzontale usa le dita per sfogliare e Pencil per scrivere. Ripeti con zoom maggiore: le dita spostano il foglio; per sfogliare torna a Pagina intera.
5. Attiva scrittura tramite dito: un dito disegna, due dita spostano/sfogliano. Disattivala: un dito torna a navigare e Pencil scrive.
6. Verifica Annulla/Ripristina e che il cambio pagina conservi l’inchiostro. Esegui i 21 controlli incorporati: quello geometrico ora verifica anche l’esclusione di Pencil dal pan.

## Verifiche fornite

Quattro regressioni aggiuntive: hosting reale del viewport nelle tre modalità con identità e dimensioni del canvas stabili e assenza di scroll antenati; tipi di input del pan/pinch e dei quattro swipe; blocco della navigazione durante scrittura/testo con conservazione dei tratti; test UI delle dimensioni invarianti cambiando modalità. Aggiornato il test UI dello sfoglio verticale.

Totale **107 XCTest** (56 core, 40 integrazione, 11 UI) e **21 controlli incorporati**. In questo ambiente Windows sono eseguiti solo controlli strutturali, grammaticali e packaging. **Build Apple, XCTest/UI e prova Pencil fisica non eseguiti qui.** [Validazione](VALIDATION.md).
