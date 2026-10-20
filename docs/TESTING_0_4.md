# Prove iPad — NeuralNotes 0.4

Queste prove si eseguono nella nuova versione, su quaderni temporanei. Non sono già state completate qui. Conserva il vecchio progetto con i suoi quaderni; nessun passaggio richiede di eliminare i dati dell’app.

## Primo avvio e controlli incorporati

1. Decomprimi NeuralNotes-iPad-0.4.1.zip in una nuova cartella di File. Apri NeuralNotes.swiftpm intero in Swift Playground, poi Esegui app.
2. Sidebar → Verifica sul dispositivo → Esegui controlli sul mio iPad. Attendi tutti i **16 risultati**. Condividi il report con il pulsante incorporato in caso di errore.
3. Controlla soprattutto **Backup completo**, precedentemente rosso, e **Colori dell’inchiostro**. In caso di FAIL il messaggio deve indicare la fase; l’originale deve restare conservato.
4. In chiaro e scuro scrivi nero, bianco su un tratto colorato, blu ed evidenziatore. Colore scelto e tratto devono corrispondere; il foglio resta chiaro.

I controlli usano documenti separati e temporanei. Le prove audio della diagnostica ordinaria verificano metadati e timestamp, senza accendere il microfono.

## Editor e foto

Crea il quaderno “Prova 0.4” e apri Scrivi e studia.

| Azione | Risultato atteso |
|---|---|
| Tocca penna/evidenziatore/gomma/lazo e colori/spessori | Selezione immediata e pulsanti con etichetta accessibile |
| Tocca tavolozza e Concentrazione | Palette richiudibile; in concentrazione spariscono schede/barra pagine, resta accessibile REC |
| Inserisci testo, modifica e salva | Testo sul foglio; il pannello Oggetti scorre alla selezione |
| Inserisci da Foto e trascina un rettangolo nell’anteprima | Sul foglio compare soltanto l’area scelta |
| Seleziona l’immagine → Ritaglia → Tutto | Ritorna l’immagine completa normalizzata |
| Ruota, trascina e ridimensiona con la maniglia | Crop e rapporto dell’immagine coerenti, nuova geometria salvata |
| Fotocamera → scatta → usa ritaglio | Stesso percorso della foto importata; il consenso viene chiesto all’uso |
| Nega il consenso camera | Messaggio comprensibile e scrittura ancora utilizzabile |
| Inserisci cerchio, rettangolo, linea, freccia | Forme visibili e selezionabili; il pannello modifica colore, spessore e geometria |

La fotocamera reale non è provabile su un simulatore senza camera. Il ritaglio conserva la copia normalizzata dell’immagine, non RAW/EXIF.

## Selezione mista e cronologia

1. Disegna tre tratti distanziati; aggiungi un testo, un’immagine e una forma.
2. Tocca **Oggetti** → **Seleziona con un rettangolo**. Racchiudi un solo tratto e due oggetti. Si selezionano tratti interi il cui bounding box interseca il rettangolo.
3. Trascina uno degli elementi selezionati: si muovono insieme. Il tratto esterno resta fermo. Tocca un punto vuoto per togliere la selezione.
4. Ripeti con Selezione multipla/Seleziona tutto; copia, incolla, duplica ed elimina. Incolla anche su un’altra pagina e in un’altra scheda.
5. Dopo ciascuna azione premi **Annulla** e **Ripristina** nella toolbar. Geometria, crop, testo e tratti devono tornare esattamente allo stato precedente/successivo.
6. Aggiungi, duplica, riordina ed elimina pagine; prova anche a eliminare l’unica pagina. Annulla e ripristina: ordine, pagina selezionata e contenuti devono restare coerenti.
7. Modifica due pagine diverse e poi annulla: l’editor deve raggiungere la pagina dell’azione interessata. Prova anche undo delle pagine importate da PDF/backup.
8. Chiudi e riapri il quaderno: contenuto salvato, cronologia della sessione terminata. Non è una cronologia persistente tra avvii.

Il budget è 60 azioni/48 MB stimati: una modifica molto grande può svuotare la cronologia. Usa le frecce della toolbar per l’undo comune; tre dita di PencilKit e undo mentre si scrive nel TextEditor rimangono locali al controllo. I tratti incollati hanno nuove identità e non copiano le vecchie associazioni audio.

## Schede e finestre

1. Apri tre quaderni con il + della barra schede. Lascia il secondo sulla pagina 3; passa tra le schede e scrivi in ognuna. Verifica salvataggio e pausa dell’audio al cambio.
2. Lascia il secondo selezionato, attendi lo stato Salvato, termina e riapri lo stesso progetto. Controlla schede disponibili, selezione e ultima pagina.
3. Dal menu editor usa **Nuova finestra**. Se il runner non supporta più scene, annota il messaggio: non è un PASS della prova multiwindow.
4. Se disponibile, apri due quaderni diversi nelle due finestre, cambia filtri e rinomina: navigazione indipendente, libreria aggiornata.
5. Prova ad aprire lo stesso quaderno nell’altra finestra. Deve avvisare che è già aperto, senza attivare un secondo writer. Chiudi la sua scheda nella prima finestra, poi riaprilo nella seconda.
6. Prova a spostare nel cestino dall’altra finestra un quaderno aperto: deve chiedere di chiuderlo. Una rinomina fatta nell’altra finestra non deve essere annullata quando l’editor torna alla libreria.

Il ripristino dipende dalla scena iPadOS. Non provare usando un’altra copia del Playground: potrebbe avere un container differente.

## PDF e backup

1. Importa un PDF con pagine portrait/landscape e rotazioni; conserva il file sorgente. Scrivi vicino ai quattro angoli, aggiungi testo, foto ritagliata e forme.
2. Zooma, ruota l’iPad, cambia pagina e riapri. Annotazioni e immagini devono rimanere ancorate alle coordinate corrette.
3. Esporta **PDF**, aprilo in File e ingrandisci molto i tratti. Il PDF ricostruisce la geometria in vettori; il brush può differire dal rendering PencilKit. Controlla pagina, margini, testo ricercabile, colore e rotazione.
4. Confronta **PDF con aspetto PencilKit**: l’inchiostro di questa opzione è raster, con aspetto più fedele. Le foto restano raster in entrambi gli export.
5. Esporta il nativo .nnbackup, torna alla libreria e reimportalo. Apri tutte le pagine: crop, forme, PDF, audio e testo devono essere presenti. Modifica la copia e verifica l’originale intatto.
6. Prova a importare lo stesso backup in un quaderno esistente: pagine aggiunte, precedenti intatte; undo delle pagine importate e successivo redo.

Un undo delle pagine importate nasconde le pagine conservandone i file; non annulla automaticamente cataloghi audio/allegati/flashcard aggiunti dal merge. Non eliminare l’originale finché la copia non è stata controllata.

## Recupero e spazio

1. In un quaderno temporaneo elimina una pagina contenente inchiostro e foto. Menu → **Spazio e recupero** → ripristina la pagina: deve riapparire con i suoi contenuti. Anche questo ripristino è annullabile durante la sessione.
2. Chiudi il quaderno nelle finestre. Dalla libreria, menu contestuale del quaderno → Spazio e recupero. Controlla categorie e totale; i file delle pagine rimosse sono protetti dalla pulizia ordinaria.
3. Se scegli di eliminare definitivamente le pagine rimosse, controlla la conferma. Solo una successiva pulizia può rimuovere i loro media non condivisi. Esegui questa prova esclusivamente sul quaderno temporaneo.
4. Se la diagnostica segnala orfani, sidebar → **Recupero quaderni**. Recupero dell’orfano e ripristino dell’indice devono conservare i file esistenti. La simulazione sicura di indice interrotto è già nella diagnostica: non corrompere manualmente i tuoi quaderni.
5. Termina l’app dopo lo stato Salvato e riapri. Ripeti su un quaderno temporaneo durante un’operazione. Atteso: apertura valida o errore/recupero esplicito; nessun reset silenzioso. I dati non ancora salvati non sono garantiti.

## Carico sintetico e prove reali

**Facoltativa:** Verifica sul dispositivo → Prova di carico facoltativa → Avvia. Genera 50 pagine con vettori e audio CAF sintetico di 60 secondi, esporta PDF, crea/reimporta un backup e confronta contenuti/durata audio. Mostra tempo e spazio finale e rimuove i temporanei. Il pulsante Interrompi richiede cancellazione cooperativa; una pagina molto densa può ritardarla.

**Registrazione reale:** su un quaderno temporaneo registra una lezione di almeno 60 minuti. Scrivi marcatori riconoscibili all’inizio e ogni 10 minuti; usa pausa/ripresa e controlla navigazione dai tratti e playback. Misura differenza tra momento udito e tratto, riavvia dopo aver fermato e verifica tutta la durata. Ripeti con interruzione audio, cambio scheda e passaggio in background; il microfono deve andare in pausa senza riprendere da solo. Non è ancora una prova superata.

**Documento grande:** importa gradualmente un PDF reale di 200–1000 pagine entro 100 MB, aggiungi foto e inchiostro su pagine distanti. Annota apertura, cambio pagina, export, backup/reimport e responsività con 1/3/6 schede. Controlla chiusure da memoria e attendibilità del conteggio pagine. Non c’è ancora una soglia prestazionale misurata per questo iPad.

**Spazio scarso:** annota spazio libero dalle impostazioni e prova solo su dati temporanei quando lo spazio è naturalmente ridotto. Il salvataggio deve mostrare errore e permettere di riprovare, senza segnare falsamente Salvato o eliminare documenti. Non riempire artificialmente l’iPad personale per questo test. Errori IO riproducibili sono anche coperti dai test automatici forniti.

In portrait/landscape e finestra stretta verifica tutte le azioni raggiungibili scorrendo le toolbar; prova VoiceOver, Dynamic Type e tastiera. Latenza, memoria di picco, drift e prestazioni richiedono misure reali; la presenza del codice non certifica questi obiettivi.

## Test automatici su un futuro Mac

`bash tools/verify_macos.sh` esegue swift test per il core, unit/UI test su simulatore iPad e build Release senza firma. Sono forniti **69 metodi**: 44 core, 22 integrazione e 3 UI, non eseguiti qui. Conservare log e .xcresult. L’accettazione della camera e delle registrazioni hardware resta su iPad fisico.

Registrare risultati e problemi in [ACCEPTANCE.md](ACCEPTANCE.md). [Stato effettivo della validazione](VALIDATION.md).
