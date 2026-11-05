# 0.28.2 — PDF durante lettura e scrittura

La beta precedente 1.0.0 (165) conserva tutte le correzioni di 0.28.1. Questo lotto interviene sul rendering a schermo dei PDF importati, senza cambiare il formato dei quaderni, i gesti, la firma o i servizi cloud.

## Problema e modifica

La cache precedente riutilizzava il documento PDF aperto, ma non i pixel già disegnati. Zoom, scorrimento, nuovi tratti dell'evidenziatore, anteprime e alcuni lavori OCR potevano eseguire ancora `drawPDFPage` sul thread dell'interfaccia.

`PDFRasterCache` affida il disegno del PDF a un worker seriale separato dal main actor. Prepara una piccola anteprima della pagina richiesta e tasselli fissi delle zone visibili, riutilizzabili durante lo scorrimento. Penna, oggetti, annulla e ripristina non invalidano questo sfondo immutabile.

- Cache di pixel limitata a 48 MiB: un quarto per le anteprime, il resto per i tasselli. La risoluzione si adatta anche al budget dell'intera area visibile, evitando cicli continui di espulsione e ridisegno.
- Un solo lavoro di rasterizzazione alla volta, coda limitata e priorità alle anteprime e alla zona richiesta più recentemente. Non viene caricato l'intero PDF in `Data`.
- Il worker conserva al massimo tre documenti aperti e rinnova il documento dopo sedici pagine diverse, per limitare le risorse PDF interne.
- Identità separata per file, indice PDF, dimensioni e generazione della cache; risultati tardivi non diventano lo sfondo di un'altra pagina.
- Anteprime, sfondo visibile e composizione dell'evidenziatore condividono gli stessi pixel; gli aggiornamenti vengono raggruppati e notificati solo alle viste interessate.
- I dettagli vengono preparati con margine di risoluzione quando il budget lo consente. I tasselli già sufficientemente densi usano il campionamento bilineare durante gli spostamenti frazionari, evitando sia la marcatura dei bordi senza filtro sia la sfocatura del filtro di ricostruzione; le anteprime ingrandite conservano un filtro più ampio.
- Anche la prima preparazione delle parole su un PDF scansionato usa i pixel preparati in background prima di avviare l'OCR. Cambio pagina, revisione e chiusura invalidano il risultato in ritardo.
- L'esportazione mantiene il percorso originale vettoriale e il testo PDF selezionabile. Le nuove cache sono derivate e non modificano gli originali o i backup.

## Verifica conclusa

Sorgenti dell'app: `780cc5902ea935a5e848d14ebb0962265caab99e`; i due successivi commit modificano solo la preparazione del simulatore. La [verifica Apple41502998310](https://github.com/sminikiller/NeuralNotes/actions/runs/41502998310) ha passato Core373XCTest+98SwiftTesting, tutti220 test nativi, Release e PlaygroundsRelease per dispositivo e simulatore con60 controlli di avvio. Include il backingstore PDF reale dipinto subito dopo il primo tratto, prima di qualsiasi layout, oltre alle quattro rotazioni con criteri originali di contrasto e geometria.

Il solo test UI ha richiesto una ripresa. L'attesa di lancio del simulatore ha evidenziato una migrazione CoreLocation ancora in corso; il setup ora attende la fine del primo avvio prima di chiedere a XCTest di lanciare l'app. Non sono cambiati gesti, zoom, soglie pixel o asserzioni UI. La [ripresa41993405959](https://github.com/sminikiller/NeuralNotes/actions/runs/41993405959) ha completato il test reale di PDF denso: zoom, scorrimento, evidenziatore leggibile, annulla, penna e annulla della penna,97.168s,zero fallimenti.

Sono state ispezionate entrambe le immagini CI, immediatamente dopo il primo tratto e a salvataggio concluso: i caratteri sono nitidi, il tratto nativo è visibile e le due immagini sono identiche. Il campo di1800 righe grigie è la fixture di stress intenzionale. La revisione precedente aveva rilevato un blur transitorio: togliendo il telo antiresidui al primo tratto, il dettaglio PDF nascosto non veniva riattivato fino al prossimo layout. Il dettaglio ora viene ripristinato nella stessa callback, conservando opacità e hit testing nativi.

ZIP compilato esatto: `.verification/NeuralNotes-iPad-0.28.2.zip`,325file,CRC e contenuti confrontati con il commit780. SHA256: `6822dd9c1fbbab24e216180e255bb2dd825c737c04c1a924b5016d3b3643b149`. Il pacchetto precedente196 è conservato separatamente. Prove: `phase0282-final-delivery-package-proof.json` e `phase0282-firststroke-visual-proof.json` nella cartella.verification.

## Distribuzione

La beta **1.0.0 (177)** è stata firmata e caricata su Apple il5novembre2026 alle08:46:58UTC con la [corsia TestFlight41996320635](https://github.com/sminikiller/NeuralNotes/actions/runs/41996320635), conclusa con successo. I log riportano `Upload succeeded` e `UPLOAD_COMMAND_SUCCEEDED`; `archive-proof.json` è stato generato prima dell'upload e riporta per questo uploaded=false. Versione, numero build, BundleID e firma sono stati confrontati col vero archivio. Elaborazione Apple e disponibilità nel gruppo TestFlight non ancora confermate. iCloud resta escluso dalla beta, come nelle precedenti.

Prova del caricamento: `.verification/phase0282-testflight-status.json`.

## Come provarla sull'iPad dopo la disponibilità in TestFlight

1. Apri un quaderno con PDF importato, mantenendo i tuoi appunti esistenti.
2. Ingrandisci, scorri la pagina e torna a pagina intera col doppio tap.
3. Scrivi alcune parole e sottolinea una riga: lo sfondo viene riutilizzato mentre i nuovi tratti si aggiornano.
4. Annulla e riscrivi, poi passa a una pagina vuota e torna al PDF.
5. Esporta un PDF: il documento originale rimane vettoriale e il testo selezionabile.

Non è misurata la latenza fisica della Pencil sull'iPad10. Nessun limite di un secondo promesso per ogni PDF. Le prove sintetiche e sul simulatore verificano cache, memoria, geometria, isolamento delle pagine, leggibilità, annulla e integrità dell'export; il confronto di fluidità percepita resta fisico. Formato dei quaderni, media originali e backup sono conservati.
