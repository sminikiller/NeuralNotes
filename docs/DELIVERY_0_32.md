# NeuralNotes 0.32 — PDF e navigazione

Stato: consegnata ad Apple come beta **1.0.0 (199)** il 15 novembre 2026 alle 14:49:47 UTC. [Upload TestFlight riuscito](https://github.com/sminikiller/NeuralNotes/actions/runs/43725854393). Elaborazione Apple e disponibilità sul dispositivo sono distinte dall’upload e non sono state verificate tramite App Store Connect.

Il rapporto dell’archivio conferma firma, Bundle ID e build 199. Il campo `uploaded: false` di quel rapporto è scritto prima dell’invio; il log successivo conferma `Upload succeeded` ed `EXPORT SUCCEEDED`.

## Correzioni

- PDF nel quaderno: riutilizzo della superficie visibile con margine durante lo spostamento; stessa strategia per livelli ed evidenziatore. Quando i tasselli alla risoluzione richiesta sono completi, non vengono ridisegnate anche tutte le risoluzioni precedenti.
- Barra pagine: miniatura e numero sopra il dito, caricamento su pausa breve con annullamento delle richieste obsolete. La pagina cambia solo al rilascio.
- PDF affiancato: una barra compatta con sorgente, ricerca, ritaglio e menu. I comandi sul testo compaiono solo con una selezione. Il ritaglio rettangolare inserisce un'immagine negli appunti con annulla/ripristina; non modifica il PDF originale. Rendering fuori dal thread UI e immagine limitata a 2048 pixel per lato.
- Annotazioni del PDF affiancato: aggiornamento delle sole pagine modificate, senza aprire ogni pagina a ogni revisione degli appunti.
- Primo tratto: la copertura che protegge dai residui della pagina precedente viene rimossa al contatto della penna, senza aspettare la pubblicazione del tratto completo da PencilKit.

## Verifiche concluse

Sorgenti: `ec58c7ac770cf871f82635e321fe56a79c4e4af0`.

- [Verifica finale 43723684538](https://github.com/sminikiller/NeuralNotes/actions/runs/43723684538): 448 XCTest Core + 98 Swift Testing, 289 test nativi e test UI finale della barra pagine, zero fallimenti. Compilazione Release riuscita.
- Cinque regressioni UI superate nella [verifica precedente 43709517783](https://github.com/sminikiller/NeuralNotes/actions/runs/43709517783): PDF affiancato e ritaglio con Undo/Redo, PDF denso con scrittura/evidenziatore, evidenziatore sul testo, doppio tap zoom, ingombro del footer nelle due rotazioni. I sorgenti dell'app sono identici; l'ultimo commit corregge solo la misura del controllo nel sesto test UI, poi superato nella verifica finale.
- Nuovi test nativi: ritaglio alle quattro rotazioni, limite di 2048 pixel, sorgente invariata, inserimento con Undo/Redo e riapertura, aggiornamento selettivo su 1500 riferimenti PDF, riuso della superficie durante lo spostamento e visibilità del primo tratto al contatto Pencil.
- Playgrounds Release per dispositivo e simulatore compilati; app rimasta attiva per 60 osservazioni con libreria/guida visibile. Questa è una prova di avvio, non una registrazione audio prolungata.
- QA visiva: anteprima durante il trascinamento, passaggio alla pagina 6 al rilascio, ritaglio dopo ripristina e PDF denso dopo scrittura. I fotogrammi video completi integrano gli screenshot XCTest in orizzontale, che presentano un ritaglio di acquisizione.
- ZIP esatto della CI: 374 file, CRC e confronto di tutti i sorgenti e risorse con il commit riusciti. SHA-256 `ca8873e788a243404b1099e39c58b097b49948694d8fcf6bf524c2b72e625059`.

## Prova rapida su iPad

1. Apri un PDF pesante nel quaderno, ingrandisci e spostati; prova penna ed evidenziatore. Confronta anche il primo tratto su una pagina bianca.
2. Trascina il cursore nella barra inferiore: compare miniatura e numero; la pagina cambia al rilascio.
3. Apri il PDF affiancato, premi l'icona di ritaglio e trascina un rettangolo. Il ritaglio viene inserito nel foglio come immagine; lo strumento torna alla navigazione PDF. Prova annulla e ripristina.

Le prove su simulatore non misurano la fluidità dell'iPad fisico con ogni PDF personale. Non sono dichiarati tempi o frame rate non misurati. Identità, firma, account, backend e iCloud restano quelli della beta esistente.
