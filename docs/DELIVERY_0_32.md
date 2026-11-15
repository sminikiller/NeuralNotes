# NeuralNotes 0.32 — PDF e navigazione

Stato: candidato locale, verifica Apple e upload TestFlight ancora da eseguire.

## Correzioni

- PDF nel quaderno: riutilizzo della superficie visibile con margine durante lo spostamento; stessa strategia per livelli ed evidenziatore. Quando i tasselli alla risoluzione richiesta sono completi, non vengono ridisegnate anche tutte le risoluzioni precedenti.
- Barra pagine: miniatura e numero sopra il dito, caricamento su pausa breve con annullamento delle richieste obsolete. La pagina cambia solo al rilascio.
- PDF affiancato: una barra compatta con sorgente, ricerca, ritaglio e menu. I comandi sul testo compaiono solo con una selezione. Il ritaglio rettangolare inserisce un'immagine negli appunti con annulla/ripristina; non modifica il PDF originale. Rendering fuori dal thread UI e immagine limitata a 2048 pixel per lato.
- Annotazioni del PDF affiancato: aggiornamento delle sole pagine modificate, senza aprire ogni pagina a ogni revisione degli appunti.
- Primo tratto: la copertura che protegge dai residui della pagina precedente viene rimossa al contatto della penna, senza aspettare la pubblicazione del tratto completo da PencilKit.

## Verifiche previste

Core e test nativi critici, con regressioni su livelli, evidenziatore, cronologia e geometria. Nuovi casi per ritagli alle quattro rotazioni, limite pixel, sorgente invariata, salvataggio e Undo/Redo, aggiornamento selettivo su 1500 riferimenti, riuso del viewport e primo contatto Pencil. UI: PDF denso, ritaglio laterale, barra pagine, zoom, livelli e grafia. Build Release, pacchetto Playgrounds esatto e avvio su simulatore.

Le prove su simulatore non misurano la fluidità dell'iPad fisico con ogni PDF personale. Non sono dichiarati tempi o frame rate non misurati. Identità, firma, account, backend e iCloud restano quelli della beta esistente.
