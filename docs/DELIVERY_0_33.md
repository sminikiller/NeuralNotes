# NeuralNotes 0.33 — strumenti per studiare

Stato: implementata; verifica Apple e upload TestFlight da completare.

## Funzioni

- **Inserisci → Studio: schemi, scotch e capitoli** riunisce i nuovi comandi. Le parti esistenti continuano a usare oggetti, livelli, selezione, cronologia e archivi nativi.
- **Scotch** in sei colori, pieno, trasparente o a righe, con larghezza e altezza regolabili. Un tocco scopre/ricopre; Oggetti permette spostamento e dimensionamento. Stile scotch è anche nella barra della selezione.
- **Ripasso della pagina**: copre le risposte del livello attivo modificabile, disabilita la scrittura, offre Scopri prossima, Ricopri e Fine. La navigazione resta attiva. Nell’export PDF dei livelli: come sul foglio, coperture piene oppure senza scotch, senza alterare gli originali.
- **Post-it** Importante, Da ripassare, Dubbio ed Esempio, con testo formattato, colore e linguetta richiudibile. L’elenco raccoglie i richiami del quaderno e porta alla loro pagina. Testo con Pencil usa l’editor esistente; i tratti liberi disegnati sopra restano inchiostro della pagina, non parte del post-it.
- **Capitoli** sulle sezioni esistenti: colore, assegnazione delle pagine e linguette laterali disattivabili. Le linguette si collocano sul lato opposto alla toolbar quando questa è a destra. Identità delle pagine e assegnazioni sono conservate durante il riordino; la cronologia delle sezioni resta quella già implementata.
- **Elenchi** puntati, numerati e checklist: titolo, sfondo pastello, spaziatura e rientri salvati in RTF. Due spazi iniziali indicano un sottoelenco. Il testo selezionato può essere riutilizzato come sorgente.
- **Mappe e schemi**: mappa concettuale, causa/processo/conseguenza, confronto, albero gerarchico, domanda/risposta e scheda infermieristica. Nodi rettangolari o ovali con etichette modificabili e frecce agganciate. Creazione di rami, trascinamento, stile, allineamento e spaziatura usano i comandi diagramma già presenti.
- **Da elenco a mappa** mantiene i rapporti padre/figlio, fino a 15 voci per una mappa leggibile sul foglio. Gli elenchi più lunghi vanno divisi. Collegamenti e fonti può collegare direttamente il nodo o testo selezionato a un’altra pagina.
- Guida integrata aggiornata, conservando le istruzioni delle consegne precedenti.

## Verifiche

Controlli locali del progetto, sintassi e pacchetto; test Core su compatibilità dei vecchi scotch, metadati, template su più formati, gerarchie, duplicazione e copie di esportazione. Test nativi su Undo/Redo, riapertura, RTF, frecce dopo spostamento, ripasso ed export non distruttivo. UI sul percorso Inserisci → mappa → scotch → ripasso e regressioni PDF/layout. Esiti Apple e numero TestFlight saranno registrati solo dopo la loro conclusione.

La beta mantiene identità, firma e servizi esistenti. Nessuna nuova dipendenza da backend o AI. Le prove fisiche con Pencil e PDF personali restano distinte da quelle automatiche.
