# NeuralNotes 0.20.2 / build 38 — selezione, ricerca PDF e note formattate

23 ottobre 2026. Ripreso il lavoro indicato nel testo allegato: i commit fino a `2372f89` e i 27 file non ancora salvati della cartella `AppAppunti-claude`. La cartella originale è rimasta intatta; una copia locale delle modifiche iniziali è conservata in `.verification`. Non si tratta di una nuova attivazione dei servizi online.

## Comandi della Lente

Seleziona lo strumento **Lente**, quindi:

- **Parole:** tocca un termine oppure passa sopra più parole come con un evidenziatore. Un giro chiuso sufficientemente alto funziona come lazo. La selezione usa parole intere.
- **Area:** disegna un cerchio o un rettangolo attorno al testo. Vengono prese le parole con il centro dentro la zona.
- **Immagine:** seleziona una zona visiva; la conversazione prepara il ritaglio come immagine. Per inviarlo serve un motore che supporti immagini e il consenso alla connessione.
- La barra vicina alla selezione offre **Spiega**, **Chiedi**, **Cerca**, **Copia** e chiusura. Segue zoom e scorrimento; su finestre strette i comandi scorrono orizzontalmente. **Cerca** apre la ricerca del quaderno con il testo scelto: è distinto dalla ricerca web della Lente.

Con Nota automatica attiva, una sottolineatura breve può produrre subito una nota; altrimenti resta la barra di scelta. Il tocco su una parola apre la spiegazione. Le richieste automatiche richiedono comunque connessione e consenso già configurati; la penna normale non avvia richieste AI.

Il livello digitale dei PDF fornisce le posizioni dei caratteri; dai caratteri vengono costruite le parole nelle coordinate della pagina. Le pagine ruotate ricorrono al percorso OCR. Grafia e scansioni usano Vision parola per parola: precisione e ordine di lettura dipendono dal riconoscimento, soprattutto con colonne, formule e scrittura poco leggibile. Le caselle di testo hanno un proprio layout, con cache e trasformazione della rotazione. Le note generate dalla Lente sono escluse dalle parole da selezionare.

Le evidenziazioni evitano di unire parole non adiacenti e quindi di colorare parole intermedie escluse dal lazo. Le cache OCR vengono invalidate anche prima del salvataggio quando cambia il disegno; risultati preparati per un'altra pagina o per una versione ormai cambiata vengono scartati. Un primo gesto durante la preparazione può ancora usare il riconoscimento della zona: non è garantita una selezione esatta immediata su materiale non ancora letto.

## Risposte e modifica delle note

Paragrafi, **grassetti**, corsivo, punti elenco e passaggi numerati vengono interpretati nelle spiegazioni e nel pannello, senza eseguire HTML o link arbitrari prodotti dal modello. I prompt personali e server chiedono la stessa formattazione. La copia delle spiegazioni rimuove i marcatori di stile. Le risposte basate su fonti del quaderno mantengono i riferimenti numerati; quelle web conservano il percorso precedente con collegamenti verificati, senza reinterpretare gli indici delle citazioni come Markdown.

Le note sul foglio conservano gli stili in RTF, con rientri degli elenchi e dimensione ridotta sulle pagine PDF. **Modifica nota** ora apre un editor formattato del testo completo: la prima riga è il titolo, con grassetto, corsivo, sottolineatura, elenchi puntati/numerati, colore e altri comandi della barra di formattazione. Il fondo riprende il colore della nota ed è leggibile anche con l'interfaccia scura. Salva conserva RTF, origine e collegamento alla selezione; Annulla chiude senza applicare la bozza. Cambiare colore o ridurre a 💡 non ricostruisce il corpo in testo semplice.

Gli stili restano nel salvataggio nativo, nell'undo e nel rendering/esportazione PDF. Il renderer e le nuove prove native devono ancora essere eseguiti con Apple: la loro presenza non dimostra la resa effettiva sull'iPad.

## Ricerca nei PDF grandi

All'apertura di **Ricerca e allegati** vengono letti i livelli di testo delle pagine PDF che non erano stati estratti all'importazione. Avanzamento visibile; risultati salvati come indice derivato in gruppi da 50 pagine, non una riscrittura per ogni pagina. Le letture completate rimangono disponibili dopo una chiusura; riaprire riprende il resto. Un errore viene mostrato e non memorizzato come pagina vuota.

Una scansione senza livello digitale viene ricordata anche alla riapertura, ma rimane idonea all'OCR della libreria: questa distinzione impedisce di perdere definitivamente il testo delle scansioni. Le revisioni cambiate vengono rilette. I risultati digitali vengono evidenziati sulla pagina usando le parole del PDF; il fallback OCR usa anch'esso parole, anziché evidenziare tutta la riga.

Restano i limiti della 0.19: **1 GiB e 5.000 pagine per import PDF locale**, copia a blocchi e originale preservato. L'indicizzazione di 1.500 pagine richiede tempo; non è stata misurata sull'iPad e non è una ricerca istantanea durante la prima preparazione. L'estrazione conserva al massimo 20.000 caratteri per pagina. Più colonne e parole spezzate possono richiedere ulteriori rifiniture. Il limite cloud rimane separato da quello PDF locale.

## Trascinamento

Per una singola nota, immagine o forma spostata senza ridimensionamento si muove un'anteprima su layer. Il modello della pagina viene aggiornato al rilascio; annullare il gesto ripristina lo stato precedente. La bitmap dell'anteprima è limitata a due milioni di pixel, considerando lo schermo Retina. I gesti di ridimensionamento, le selezioni multiple e l'inchiostro mantengono il percorso precedente: non vengono dichiarati ottimizzati da questo cambiamento.

## Verifiche

- Swift Linux 6.1.2: **259 XCTest, 257 passati, due skip Darwin preesistenti, zero fallimenti; 98 FSRS passati**. Copertura nuova su tocco/sottolineatura, lazo/area, UTF-16, sillabazione, ricerca senza accenti, parole non adiacenti, marcatori incompleti, elenchi, indice PDF per revisioni e scansioni vuote ancora riconoscibili con OCR.
- Backend: **48 test Node passati**, con verifica della richiesta di elenchi e grassetti e dei contratti già presenti.
- Integrazione reale locale: GoTrue/Auth, email in Mailpit, PostgREST/PostgreSQL, due utenti, RLS, quote e consumi per account, refresh e revoca logout. Il trasporto verso il modello AI è simulato esplicitamente: nessuna prova live della qualità o della latenza dei provider.
- Progetto: grafo e membership aggiornati, **300 file Swift / 402 metodi XCTest individuati**; grammatica e parsing del compilatore in modalità Swift 5. Questi controlli non sono una build SDK.
- Prove native predisposte: modifica RTF della nota con elenchi, metadati, undo/redo, riapertura ed export; estesa la prova PDF di 1.500 pagine con parole, coordinate, tocco e risultati. **Non eseguite** con Apple.

La verifica GitHub più recente sul commit precedente, [39858791254](https://github.com/sminikiller/NeuralNotes/actions/runs/39858791254), è fallita prima degli step per pagamenti/limite di spesa; il job Apple è stato saltato. Non è stata rilanciata inutilmente. Nessun SDK Apple o collegamento di controllo all'iPad disponibile nella sessione. Compilazione Playgrounds, fluidità e interazioni Pencil della 0.20.2 restano quindi da confermare sul dispositivo.

## Pacchetti e conservazione dei dati

`NeuralNotes-iPad-0.20.2.zip` contiene il Playground completo, verificato byte per byte rispetto ai sorgenti. `NeuralNotes-Sorgenti-0.20.2.zip` contiene progetto, backend, test e documentazione. Non contengono le fixture grandi o i segreti dei servizi locali.

Apri il nuovo ZIP in una cartella separata e conserva il vecchio Playground e gli export. Una copia del progetto può avere un container dati distinto. Questa consegna include le funzioni precedenti della 0.20; non dichiara completati comunità nativa, pagamenti, hosting AI o tutte le prove fisiche della roadmap. [Consegna precedente](DELIVERY_0_20_1.md), [configurazione servizi](../backend/ACTIVATION.md).
