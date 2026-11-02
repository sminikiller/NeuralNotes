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
- L'esportazione mantiene il percorso originale vettoriale e il testo PDF selezionabile. Le nuove cache sono derivate e non modificano gli originali o i backup.

## Verifica

Controlli locali: struttura del progetto, grammatica Swift, risorse, nove controlli di preflight e composizione dello ZIP. Questi controlli non compilano contro l'SDK Apple.

Prove Apple aggiunte: PDF denso con cento frame e piccoli spostamenti a cache calda; budget ridotto senza ridisegni ciclici; cambio pagina e invalidazione con risultato tardivo; testo a zoom elevato nelle quattro rotazioni; venti nuove composizioni dell'evidenziatore senza decodifica PDF sincrona; diciotto pagine, file non valido e avviso memoria; importazione reale con penna, annulla/ripristina, nuova pagina e PDF esportato ancora selezionabile. Un test UI usa un PDF denso reale per zoom, scorrimento, evidenziazione, scrittura e annulla, controllando i pixel oltre ai comandi.

**Verifiche SDK, prove UI e nuova distribuzione: in attesa.** La latenza fisica della Pencil e la fluidità percepita sull'iPad non sono misurate dai controlli strutturali. Non presentare lo ZIP locale come una build già compilata o questa fase come già presente nella beta 165.
