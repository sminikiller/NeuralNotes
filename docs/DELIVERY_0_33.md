# NeuralNotes 0.33 — strumenti per studiare

Stato: implementata, verificata e caricata su TestFlight come **1.0.0 (202)**. Apple ha ricevuto l’upload il **17 novembre 2026 alle 07:52:12 UTC** ([run 44040872993](https://github.com/sminikiller/NeuralNotes/actions/runs/44040872993), `Upload succeeded` ed `EXPORT SUCCEEDED`). La disponibilità dopo l’elaborazione Apple non è stata osservata direttamente.

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

- [Verifica finale 43976555572](https://github.com/sminikiller/NeuralNotes/actions/runs/43976555572), sorgenti `b71e5297214f945e23636cd1f62b3e566e1295b4`: **452 XCTest Core + 98 Swift Testing, 291 test nativi e un test UI Studio**, zero fallimenti. Compilazioni native Debug/Release e Playgrounds Release per dispositivo/simulatore riuscite; avvio dal vero ZIP con 60 osservazioni superato.
- I test coprono compatibilità dei vecchi scotch, metadati, template su più formati, gerarchie, duplicazione, Undo/Redo, riapertura, RTF, frecce dopo spostamento, rimozione dei collegamenti dai nodi, ripasso ed export non distruttivo.
- Nella [verifica precedente 43918783878](https://github.com/sminikiller/NeuralNotes/actions/runs/43918783878) erano passate tutte e tre le UI Studio/PDF denso/barra pagine. L’unico test nativo fallito riguardava il colore dello scotch storico: ripristinato il colore originale senza cambiare l’asserzione, poi superato nella verifica finale. Il runner Playgrounds precedente era indisponibile, non un errore del codice.
- Ispezionate le schermate finali della mappa e del ripasso, quelle precedenti di PDF/barra pagine e la schermata di avvio del pacchetto.
- **ZIP esatto:** [artefatto 14281671880](https://github.com/sminikiller/NeuralNotes/actions/runs/43976555572/artifacts/14281671880), `NeuralNotes-iPad-0.33.0.zip`, 377 file con CRC e confronto di tutti i sorgenti/risorse superati. SHA-256 `63ef58580ce27495c7d0c5a2331d67320eb21da185a4613257acf7419b2bf910`.

La beta mantiene identità, firma e servizi esistenti. Nessuna nuova dipendenza da backend o AI. Le prove fisiche con Pencil e PDF personali restano distinte da quelle automatiche.

## Prova rapida sull’iPad

1. Apri un quaderno e usa **Inserisci → Studio: schemi, scotch e capitoli**.
2. Inserisci una mappa, sposta un nodo e modifica la sua etichetta: le frecce devono seguirlo. Prova Annulla/Ripristina.
3. In **Ripasso**, inserisci uno scotch su una parola, scegli colore e stile, poi avvia il ripasso. Prova **Scopri prossima**, **Ricopri** e **Fine**.
4. Inserisci un post-it, richiudilo in linguetta e riaprilo; ritrovalo nell’elenco **Post-it** dopo aver cambiato pagina.
5. Crea un capitolo colorato e assegna alcune pagine: la linguetta laterale deve portare alla prima pagina del capitolo.
6. Inserisci un elenco con un sottoelenco, quindi prova la conversione in mappa. Chiudi e riapri il quaderno per verificare il mantenimento dei contenuti.

Per il collaudo delle ottimizzazioni precedenti: prova un tuo PDF pesante, scrivi sul foglio e scorri le pagine. I test automatici su simulatore non misurano la fluidità della tua Pencil e dei tuoi documenti sul dispositivo fisico.
