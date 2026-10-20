# NeuralNotes 0.7 — build 13

Questa versione aggiunge lo scorrimento verticale continuo con fogli ravvicinati e la voltata orizzontale a libro. Conserva il canvas esteso della 0.6.1. L’utente ha risposto «perfetto» alla precedente correzione; questa nuova implementazione non è ancora stata provata sull’iPad dall’agente.

## Modalità verticale

In **Navigazione pagine → Scorrimento verticale**, i fogli sono visibili uno dopo l’altro con un distacco di 12 punti del documento, ridimensionato insieme allo zoom. Pan e decelerazione appartengono al PKCanvasView principale; non c’è uno ScrollView esterno né un riquadro più piccolo per la pagina.

Le pagine vicine vengono mostrate con anteprime preparate in anticipo; il solo canvas attivo conserva l’inchiostro nelle coordinate locali della pagina. Quando la pagina attiva cambia, l’offset viene ricalcolato per mantenere lo stesso punto del documento sullo schermo. Lo scorrimento non scatta alla pagina successiva e può fermarsi fra due fogli. I formati diversi sono centrati su una larghezza comune; lo zoom minimo usa le dimensioni massime del documento per mantenere stabile la scala fra fogli.

Apple Pencil rimane esclusa dal pan/pinch e dallo sfoglio. Dopo lo scorrimento viene aperta la pagina più visibile. Le pagine già preparate possono attivarsi al primo contatto della penna senza spostare il viewport. Se una pagina non è ancora pronta, il primo tocco la apre e compare un messaggio; inizia il tratto dopo il caricamento. Questa protezione impedisce che il tratto venga scritto nel file del foglio sbagliato. Il distacco fra fogli non è un’area di scrittura. Con disegno tramite dito usa due dita per scorrere.

Prova su tre fogli con un numero scritto al centro:

1. Scorri lentamente attraverso il bordo fra due pagine e fermati con entrambe visibili. Lo spazio fra i fogli deve rimanere piccolo e la posizione non deve saltare dopo la decelerazione.
2. Riparti da quella posizione, scorri velocemente avanti e indietro e verifica la pagina selezionata nei pulsanti in basso.
3. Scrivi dopo lo scorrimento, poi su una pagina vicina già visibile. Controlla che la penna non trascini il documento e che il tratto rimanga nel foglio corretto dopo riapertura ed export.
4. Ripeti con fogli di altezze diverse, un PDF misto, zoom maggiore, rotazione e focus. Le anteprime possono richiedere caricamento; non devono essere scambiate per pagine vuote.
5. Cambia modalità e torna al verticale: il canvas deve mantenere le dimensioni dell’editor e l’input deve restare disponibile. Verifica anche Annulla/Ripristina e registrazione audio mentre cambi pagina.

## Modalità orizzontale

In **Sfoglia orizzontalmente**, lo swipe con le dita a pagina intera usa un’animazione di voltata con incurvamento. La direzione si inverte tornando alla pagina precedente. I pulsanti numerati attivano la stessa presentazione quando selezionano un’altra pagina. Quando sei ingrandito, il gesto sposta il foglio; torna a Pagina intera per sfogliare.

L’effetto usa le transizioni curl pubbliche di UIKit, ruotate sull’asse orizzontale, con immagini del foglio e dell’inchiostro che rimangono dritte. Non riscrive i tratti. La navigazione rimane occupata fino al completamento dell’animazione. Con **Riduci movimento** l’effetto diventa una breve dissolvenza. Riferimenti Apple: [transitionCurlUp](https://developer.apple.com/documentation/uikit/uiview/animationoptions/transitioncurlup), [transitionCurlDown](https://developer.apple.com/documentation/uikit/uiview/animationoptions/transitioncurldown).

Prova avanti/indietro, tocchi ripetuti durante la voltata, prima/ultima pagina, fogli con immagini e inchiostro e ritorno alla scrittura. La voltata è avviata dallo swipe: non segue interattivamente ogni posizione del dito. Verifica visivamente il verso della piega, l’assenza di lampeggi e la leggibilità, anche con Riduci movimento attivo. Ruotare il dispositivo durante la voltata richiede una prova reale.

## Verifiche fornite e limiti

Sei nuove regressioni: geometria/ordine/distacco del flusso, scelta della pagina visibile, documenti lunghi e geometrie invalide; offset conservato fra formati diversi con inchiostro locale; rifiuto di attivazione preparata con modifiche non salvate o header obsoleto; completamento della voltata nei due sensi e conservazione dell’inchiostro. Aggiornato il test UI del verticale perché non richieda più un salto obbligato di una sola pagina.

Totale **113 XCTest** (59 core, 43 integrazione, 11 UI), **22 controlli incorporati**. Il nuovo controllo sul dispositivo verifica distacco e ordine delle coordinate, non simula tocchi o la piega. Le anteprime sono limitate alle pagine vicine (fino a sei più l’attiva), con immagini a dimensione massima 1200; prestazioni e memoria su documenti reali grandi richiedono misure.

In Windows sono eseguiti controlli di struttura, grammatica e packaging. **Nessuna compilazione Apple, XCTest/UI o verifica visiva dell’animazione è stata eseguita qui.** [Validazione](VALIDATION.md) · [Accettazione](ACCEPTANCE.md).

Conserva il vecchio Playground e i backup .nnbackup prima di aprire la nuova copia. I diversi progetti possono avere dati separati; il formato dei quaderni resta invariato.
