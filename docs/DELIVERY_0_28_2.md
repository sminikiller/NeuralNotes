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
- I dettagli vengono preparati con margine di risoluzione quando il budget lo consente. I tasselli già sufficientemente densi non ricevono un secondo filtro sui bordi dei caratteri; le anteprime ingrandite conservano invece il filtro di ricampionamento.
- Anche la prima preparazione delle parole su un PDF scansionato usa i pixel preparati in background prima di avviare l'OCR. Cambio pagina, revisione e chiusura invalidano il risultato in ritardo.
- L'esportazione mantiene il percorso originale vettoriale e il testo PDF selezionabile. Le nuove cache sono derivate e non modificano gli originali o i backup.

## Verifica

Controlli locali: struttura del progetto, grammatica Swift, risorse, nove controlli di preflight e composizione dello ZIP. Questi controlli non compilano contro l'SDK Apple.

Prove Apple aggiunte: PDF denso con cento frame e piccoli spostamenti a cache calda; budget ridotto senza ridisegni ciclici; cambio pagina e invalidazione con risultato tardivo; testo a zoom elevato nelle quattro rotazioni; venti nuove composizioni dell'evidenziatore senza decodifica PDF sincrona; diciotto pagine, file non valido e avviso memoria; importazione reale con penna, annulla/ripristina, nuova pagina e PDF esportato ancora selezionabile. Un test UI usa un PDF denso reale per zoom, scorrimento, evidenziazione, scrittura e annulla, controllando i pixel oltre ai comandi.

La prima verifica ha compilato Debug, Release e il pacchetto Playgrounds per dispositivo e simulatore, avviandolo per sessanta controlli; tutti i nove test UI pertinenti sono passati, incluso il PDF denso. Il nuovo test dei caratteri ruotati ha rilevato un ricampionamento aggiuntivo dei bordi: le immagini diagnostiche hanno confermato che la geometria e la quantità di inchiostro restano corrette, mentre il contrasto dei pixel interni si riduceva. Il controllo di contrasto originale è conservato; sono aggiunti anche i limiti geometrici a livello di pixel. Una prova ulteriore usa un PDF realmente composto da un'immagine e verifica il contenuto ricevuto dall'OCR senza decodifica PDF sul main actor.

**Verifica SDK finale e nuova distribuzione: in attesa.** La latenza fisica della Pencil e la fluidità percepita sull'iPad non sono misurate dai controlli strutturali. Non presentare lo ZIP precedente come il pacchetto dell'ultimo sorgente o questa fase come già presente nella beta 165.
