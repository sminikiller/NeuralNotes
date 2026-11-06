# Fase0.31 — progetto della grafia geometrica

Preparazione locale isolata durante la verifica della0.30. Non distribuita e non compilata con SDK. Nessuna AI, correzione delle parole o generazione di grafia.

## Contratto

- Core lavora su punti/piccoli rettangoli e indici originali: raggruppa righe e parole, stima la linea di base in coordinate pagina, propone trasformazioni geometriche.
- L'adattatore PencilKit applica affini ai tratti originali senza ricostruire i campi di pressione, tempo, inclinazione, maschera, seme o inchiostro. Ripulisci cambia solo le coordinate, ricampionate sugli indici originali: la curva di pressione e tutti gli altri campi rimangono esatti.
- RDP a tolleranza bassa e Chaikin preparano una guida; il risultato finale contiene tanti punti quanti l'originale, con primi/ultimi punti fissi. Nessun picco di pressione viene scartato dalla semplificazione.
- Il raggruppamento comprende punti, accenti e tratti piccoli; in coordinateUIKit la parte bassa è il quantile80%, equivalente al20% con assey verso l'alto. La stima della pendenza è robusta, non una regressione su un singolo discendente.
- L'anteprima non sostituisce il PKDrawing autorevole né scrive file. Mostra gli originali sbiaditi e il risultato, con Applica/Annulla. Applica produce un solo passo di cronologia e conserva il proprietario del livello.
- Riadatta ha maniglie laterali e va a capo per parole. Interlinea offre il comando uniforme sulla selezione (alternativa ammessa dal§9), non modifica silenziosamente contenuti di altri livelli.
- Se la proposta non entra nella pagina, Applica resta disabilitato con spiegazione; non tagliare né eliminare tratti.

## Verifiche previste

Righe sintetiche con inclinazioni differenti, parole/segni piccoli, stima robusta, fattori0.8…1.25, reflow con a capo e conservazione degli indici; Native controlla campi esatti dei punti, maschere, seme e annulla, oltre all'anteprima che non salva. UI mostra il pannello sul foglio e le maniglie. Compilazione, QA e consegna solo dopo aver incorporato i fix0.30 verificati.


Checkpoint locale, non consegna: Core, adattatore PencilKit, sessione di anteprima, pannello e maniglie integrati nella worktree isolata della31. **17 Core, 12 Native e 2 UI nuovi sono presenti; nessuno ancora eseguito con SDK.** Parser e controllo strutturale passati: 517 Swift, 794 metodi XCTest presenti. Candidato0.31.0/buildlocale61, non distribuito. La beta effettiva resta179 fino a nuova prova di upload. La selezione è limitata a4.000tratti e500.000punti, con controllo preventivo condiviso fra Core e adattatore; oltre il budget si richiede un paragrafo più piccolo. Il nuovo test UI usa il vero percorso di creazione del quaderno e i flag di isolamento già verificati negli altri test.

L’adattatore esclude l’evidenziatore, usa per le misure solo i punti visibili attraverso la maschera, e conserva tutti i punti originali per la levigatura. Mantiene esattamente anche secondaryScale e, con SDK/iOS26, threshold; nessuna API privata. Gli estremi riutilizzano i punti nativi originali. L’anteprima disegna solo il viewport, senza sostituire il canvas né scrivere file; la copia sbiadita è memorizzata entro due milioni di pixel per viewport. Navigazione, cambio strumento/livello, replay e annulla scartano l’anteprima.

La guida integrata descrive i cinque comandi. Suggerimenti OCR già in cache vengono usati soltanto sulle pagine composte esclusivamente da grafia, evitando che PDF, foto, testo digitato o altri livelli determinino le righe della selezione. Le parole del documento riconosciute in precedenza non vengono riscritte; dopo Applica scade l’indice spaziale. Il correttore ortografico facoltativo resta escluso. Le prove su grafia reale e la qualità percettiva richiedono il collaudo iPad, distinto dai test sintetici.

Le maniglie aggiornano la proposta con un worker alla volta e richieste successive accorpate: non attendono il rilascio del dito. La sessione annullata non può riavviarsi né applicare dati; durante l’anteprima i gesti di spostamento oggetti sono disabilitati, restano zoom e annulla. Il controllo finale comprende anche gli ingombri dipinti PencilKit, oltre ai punti geometrici. Grafia compare accanto alla prima azione della selezione e anche nelle azioni della mini-toolbar a foglio intero.

La grafia parzialmente cancellata viene misurata campionando la curva visibile (con limite), anche quando entrambi i punti di controllo originali sono fuori dalla maschera. La pulizia conserva comunque tutti i campi dei punti originali. Lo snap alla carta assegna righe distinte a righe manoscritte vicine; non le sovrappone. Prima di pubblicare Applica viene verificato anche il budget della cronologia, così un’operazione troppo grande non viene eseguita senza il suo annulla.

Undo durante l’anteprima annulla soltanto la proposta, senza consumare l’ultima azione reale né muovere il cursore della cronologia. Il controllo torna disponibile anche se non ci sono altre azioni; un secondo Undo agisce normalmente sul documento. Test dedicato con un’azione precedente.

La fixture statica del formato0.30 attraversa apertura, rifinitura, salvataggio, riapertura, backup nativo e importazione come copia. Il test controlla dati nativi esatti e OCR invariato; il PDF della copia deve conservare i tratti vettoriali senza immagini sostitutive. Questo è un test presente nella candidata, non ancora un esito SDK.

## Come provare la grafia sull’iPad

1. Scrivi un paragrafo con la penna, selezionalo con il lazo e apri **Grafia** nella barra della selezione. Il comando agisce sulla grafia del livello attivo, senza spostare foto o testo digitato.
2. Prova **Raddrizza**: controlla l’anteprima e, se serve, attiva Allinea a sinistra o Appoggia sulle righe. **Annulla** scarta la proposta; **Applica** conferma.
3. **Uniforma dimensione** avvicina l’altezza delle parole senza sostituire le lettere. **Ripulisci tratto** offre tre intensità: confrontale prima di confermare.
4. In **Riadatta alla larghezza**, trascina i due bordi o usa il cursore; le parole vanno a capo. Con VoiceOver le maniglie sono controlli regolabili, con posizione e larghezza lette ad alta voce.
5. **Spazio tra le righe** regola l’interlinea della selezione. Se la proposta supera il foglio, Applica resta disabilitato. Dopo una conferma, Undo ripristina l’originale in un passo e Redo riapplica la modifica.

Queste istruzioni descrivono la candidata; attendere la build indicata nella consegna verificata prima di provarla su TestFlight.
