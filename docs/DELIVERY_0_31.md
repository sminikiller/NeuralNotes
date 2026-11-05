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


Checkpoint locale, non consegna: Core, adattatore PencilKit, sessione di anteprima, pannello e maniglie integrati nella worktree isolata della31. **15 Core, 6 Native e 2 UI nuovi sono presenti; nessuno ancora eseguito con SDK.** Parser e controllo strutturale passati: 516 Swift, 783 metodi XCTest presenti. La versione del pacchetto resta30 fino alla preparazione della verifica31.

L’adattatore esclude l’evidenziatore, usa per le misure solo i punti visibili attraverso la maschera, e conserva tutti i punti originali per la levigatura. Mantiene esattamente anche secondaryScale e, con SDK/iOS26, threshold; nessuna API privata. Gli estremi riutilizzano i punti nativi originali. L’anteprima disegna solo il viewport, senza sostituire il canvas né scrivere file; la copia sbiadita è memorizzata entro due milioni di pixel per viewport. Navigazione, cambio strumento/livello, replay e annulla scartano l’anteprima.

La guida integrata descrive i cinque comandi. Suggerimenti OCR già in cache vengono usati soltanto sulle pagine composte esclusivamente da grafia, evitando che PDF, foto, testo digitato o altri livelli determinino le righe della selezione. Le parole del documento riconosciute in precedenza non vengono riscritte; dopo Applica scade l’indice spaziale. Il correttore ortografico facoltativo resta escluso. Le prove su grafia reale e la qualità percettiva richiedono il collaudo iPad, distinto dai test sintetici.
