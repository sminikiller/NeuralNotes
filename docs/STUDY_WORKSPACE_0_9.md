# NeuralNotes 0.9.0 — editor e strumenti per studiare

20 ottobre 2026, build 18. Questa consegna interviene sulle sette aree richieste. Gli esiti della compilazione e i limiti della prova sono in [VALIDATION.md](VALIDATION.md).

## Funzioni e stato effettivo

| Area | Implementato | Limiti ancora presenti |
| --- | --- | --- |
| Fluidità e nitidezza | Ridisegno del PDF e del testo nell’area visibile quando ingrandisci; cache dei PDF e delle immagini; limite di 8 milioni di pixel per il dettaglio visibile; attivazione immediata delle pagine native fredde fino a 8 MB quando non ci sono modifiche da salvare. | Prestazioni reali sull’iPad 10 da misurare. Una pagina molto grande o raggiunta durante un salvataggio usa ancora l’attivazione asincrona protetta: può richiedere un secondo contatto. Le anteprime non hanno ancora un’intera pipeline in background. |
| Protezione degli appunti | Backup automatici locali, cinque versioni, intervallo minimo dieci minuti durante l’uso; creazione manuale e condivisione delle versioni. Implementata sincronizzazione CloudKit facoltativa, confronto delle revisioni, conflitti espliciti, copia remota indipendente e backup prima di sostituire il locale. | iCloud richiede app firmata, contenitore registrato e prova reale. Non è attivo nel Playground. Le cartelle e le eliminazioni non sono propagate. I backup automatici nello stesso dispositivo vanno anche esportati. |
| Scrittura | Sei tipi di penna PencilKit, cinque preset, gomma regolabile parziale o per tratto, modalità solo evidenziatore e ritorno alla penna. Selezione mista con scala, rotazione e cambio colore, con undo. | I comandi incrementali sono disponibili sulla selezione dello strumento Oggetti, anche per l’inchiostro. Il lazo nativo PencilKit resta separato; non ci sono ancora maniglie libere con due dita per ogni oggetto. |
| Testo e inserimenti | Grassetto, corsivo, sottolineato, elenchi con punti, caselle, apici e pedici; RTF salvato e reso nel PDF; scanner multipagina, trascinamento di immagini/testo/URL e collegamenti apribili. Lo scarabocchio conserva la formattazione del testo rimasto. | Le checklist sono caselle di testo, non attività interattive. La continuazione automatica degli elenchi e il trascinamento di file PDF da altre app restano da aggiungere; i PDF si importano dal comando dedicato. Scanner e Pencil fisica richiedono la prova sul dispositivo. |
| PDF per studiare | Pannello affiancato PDF/appunti con selezione e copia del testo, evidenziazione per riga, sottolineatura, indice e navigazione dei link gestiti da PDFKit. Pagine bianche inseribili dopo quella corrente. Annotazioni salvate separatamente dall’originale e incluse nell’esportazione. | Un PDF scansionato senza livello testo richiede OCR; il pannello non inventa testo selezionabile. La risposta dei link PDF dipende anche dalla struttura del file. |
| Ricerca | Indice persistente ricostruibile, ricerca nell’intera libreria su testo, PDF, OCR e trascrizioni, apertura della pagina o del punto audio; OCR automatico nelle pause. | OCR automatico della pagina modificata, non elaborazione massiva retroattiva di tutta la grafia esistente. Qualità del riconoscimento da valutare sulla propria scrittura. |
| Lente AI | Area o selezione come fonte, pannello laterale, conversazione persistente, riferimenti navigabili, inserimento della risposta e flashcard. Streaming reale del backend con risultato finale validato; risposte parziali interrotte non diventano risposte salvate. | Nessun hosting o account provider configurato. Senza endpoint HTTPS e token resta disponibile l’estrazione offline, dichiarata come tale. Nessuna prova live del modello è stata eseguita. |

## Dove trovare i comandi

- Libreria → **Cerca negli appunti**, **iCloud e conflitti**; importazione PDF e backup restano separate.
- Editor → **Workspace e preferiti** → **Penne, preset e gomma**.
- Oggetti → seleziona anche l’inchiostro con l’area rettangolare → menu della selezione: ingrandisci, riduci, ruota o applica il colore corrente.
- Modifica un testo sul foglio oppure nel pannello Testi e immagini: la barra sopra la tastiera contiene formattazione, elenchi, caselle, apici/pedici e Fine.
- Azioni → **Inserisci** → **Scansiona documento**. Le pagine vengono elaborate e salvate una alla volta; un errore indica dove l’importazione si è fermata e conserva quelle già importate.
- Barra dell’editor → **PDF affiancato** oppure **Lente AI**. Il canvas principale rimane lo stesso; chiudendo il pannello recupera la larghezza disponibile.
- Azioni → spazio/archivio del documento: **Backup automatici** e versioni condivisibili.

## Backup e recupero

Le versioni automatiche sono `.nnbackup` nella cartella `AutomaticBackups/<documentID>` accanto ai documenti. La nuova versione viene completata prima di ruotare quelle precedenti. Errori di backup non trasformano un salvataggio riuscito in una perdita degli appunti. Il backup di una registrazione in corso viene rinviato alla pausa per evitare un archivio incoerente.

Il timer è legato ai salvataggi durante l’uso dell’editor: non è un’attività periodica garantita da iPadOS quando l’app è sospesa. Per ripristinare una versione, condividila in File e usa **Importa quaderno o backup**: viene creata una copia indipendente. Prima di aprire un nuovo Playground conserva il precedente ed esporta i quaderni: un nuovo progetto può avere un container diverso.

La sostituzione di un documento da iCloud controlla nuovamente l’impronta locale dopo il download. Se nel frattempo è cambiato, si ferma. La copia precedente viene archiviata prima della sostituzione; un’interruzione con cartella `.cloudPrevious` viene riconosciuta all’avvio.

## iCloud: configurato nel progetto, da attivare e provare

- Team ID fornito dall’utente: `64R668842U`.
- Bundle ID attuale del progetto: `com.neuralnotes.NeuralNotes`. Non è stato verificato né registrato nel portale Apple.
- Contenitore previsto: `iCloud.com.neuralnotes.NeuralNotes`; entitlement e configurazione Xcode predisposti.
- Database privato con record `NNLibrary`, `NNNotebook` e `NNChunk`; archivi in parti immutabili da 8 MB e aggiornamenti condizionali della revisione remota.
- Nessun certificato, profilo, credenziale Apple o firma di distribuzione è stato installato. La build CI resta senza firma.

L’attivazione richiede l’App ID e il contenitore nel team Apple, la firma con un profilo che li includa e la distribuzione dell’app firmata. La sola compilazione dei sorgenti e il Team ID non attivano CloudKit. La versione Playground mostra il limite prima di tentare la connessione.

Quando abilitata nell’app firmata, la sincronizzazione prova i quaderni chiusi mentre la libreria è attiva. Un quaderno aperto viene saltato. Un conflitto conserva entrambe le versioni e offre copia remota, mantieni locale o mantieni iCloud. Non avviene una fusione automatica di tratti o pagine. Le eliminazioni locali non eliminano la copia cloud, e le cartelle restano locali. Prima dell’uso quotidiano occorre provare due dispositivi e due modifiche offline concorrenti.

## Backend e Lente AI

Il backend riceve soltanto i chunk selezionati e riferimenti, usa la Responses API e restituisce eventi NDJSON quando il client li richiede. I frammenti sono testo provvisorio; il risultato finale è salvato solo dopo la validazione delle citazioni. Endpoint e token del backend si impostano nella Lente; la chiave del provider resta sul server. Il token del backend usa il portachiavi del dispositivo.

La connessione richiede consenso esplicito nel pannello. Il server deve essere pubblicato su HTTPS con autenticazione e limiti configurati: [istruzioni e contratto](../backend/README.md). Nessun servizio è stato distribuito e nessuna chiamata a pagamento è stata fatta per questa consegna. L’account Apple Developer non fornisce un servizio AI.

## Prova pratica su una copia degli appunti

1. Conserva ed esporta il vecchio quaderno. Apri il nuovo Playground in una cartella separata, importa la copia e verifica pagina, immagini, PDF e audio.
2. Zoom: passa ripetutamente da pagina intera a larghezza schermo e a un ingrandimento manuale; controlla testo/PDF nitidi, pan e inchiostro allineati. Scorri rapidamente dieci pagine e scrivi sulla prima pagina non preparata. Annota eventuali primi contatti persi.
3. Penne/gomma: prova stilografica e monolinea, salva e richiama un preset. Sovrapponi evidenziatore e penna, abilita **Solo evidenziatore**, cancella con un tocco e con una passata; verifica penna intatta e undo/redo. Ripeti scegliendo **Tratto intero**.
4. Seleziona tratti e testo, ruota/ridimensiona/ricolora, quindi undo/redo e riapertura. Prova lo scarabocchio su una sola parola di una frase formattata: le altre devono restare con lo stile precedente.
5. Testo: scrivi una frase con grassetto e apice, esporta il PDF e riapri il quaderno. Inserisci uno scan di più pagine e trascina una foto e un URL da un’altra app.
6. Importa un PDF testuale con indice, link e una pagina ruotata. Aprilo affiancato, copia una frase, evidenziala e sottolineala; cambia pagina, annulla/ripeti ed esporta. Controlla allineamento e originale invariato.
7. Cerca nella libreria una parola di un testo, di un PDF e di una trascrizione; apri ogni risultato. Scrivi una parola leggibile, attendi la pausa OCR e cercala. Disabilita l’OCR e verifica che gli appunti continuino a salvarsi.
8. Crea due versioni manuali del backup, modifica il quaderno e importa una versione precedente come copia. Durante una registrazione verifica che il backup sia rinviato; dopo la pausa riprova. Non simulare spazio esaurito sui quaderni originali.
9. Lente: seleziona una frase o cerchia una zona, apri il pannello, controlla la modalità offline, inserisci un estratto e crea una flashcard. Con un backend proprio configurato prova streaming, Stop, perdita rete e riferimenti. Un risultato interrotto non deve essere salvato come risposta completa.
10. Solo nell’app firmata: abilita iCloud su due dispositivi, prova upload/download e modifica offline su entrambi. Risolvi un conflitto creando prima una copia e controlla le versioni automatiche. La compilazione su simulatore non sostituisce questa prova.

Le prove automatiche coprono persistenza, isolamento dell’inchiostro, geometria, backup/recupero, indice, revisione cloud, PDF/RTF, apertura e chiusura dei pannelli e contratto streaming. Non misurano la qualità della grafia, l’ergonomia della Pencil o le prestazioni del proprio iPad.
