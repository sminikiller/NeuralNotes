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


Checkpoint: fondazione Core locale e12prove sintetiche PRESENTI, NON eseguite con SDK. Raggruppamento incrementale con fit limitato a512campioni bassi e massimo32bucket; pendenza Theil–Sen; hintsOCR facoltativi. Dot e crossbar associati alla riga più vicina, intervallo0.6altezza-x perparole. Ripulisci usa un budget di valutazioniRDP per evitare costoquadratico suzigzag e restituisce tutti gli indici originali, estremi fissi. PipelineNative eUI ancora da integrare. Non è la consegna31.
