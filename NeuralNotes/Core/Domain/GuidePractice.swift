// Exercise IDs use the order within each lesson. Append new exercises to preserve saved progress.
enum GuidePractice {
    static let catalog: [String: [GuideExercise]] = [part1, part2, part3, part4, part5, part6]
        .reduce(into: [:]) { result, part in result.merge(part) { _, new in new } }

    private static let part1: [String: [GuideExercise]] = [
        "study-kit": [
            .init(
                "Crea una mappa Causa e conseguenza, un elenco puntato e un richiamo Da ripassare. Chiudi e riapri il quaderno di prova.",
                "La mappa ha rami collegati, l’elenco conserva il rientro e il post-it è ancora presente nella pagina."
            ),
        ],
        "page-layers": [
            .init(
                "Scrivi BASE sul livello Base. Apri Livelli, crea Ripasso e scrivi EXTRA. Spegni l’occhio di Ripasso, riaccendilo e poi chiudi il lucchetto.",
                "Scompare solo EXTRA. Riattivando l’occhio torna visibile. Sul livello bloccato la penna non lascia nuovi segni."
            ),
            .init(
                "Sblocca Ripasso, cambia la sua opacità e spostalo sopra o sotto Base. Usa Annulla dopo il riordino.",
                "Cambia solo l’aspetto del livello scelto. Annulla ripristina l’ordine precedente."
            ),
        ],
        "handwriting-refine": [
            .init(
                "Scrivi tre righe irregolari con Penna. Cerchiale con Lazo libero, apri Grafia e prova Raddrizza. Chiudi la prima anteprima con Annulla, poi riaprila e applica.",
                "La prima chiusura lascia la grafia com’era. Dopo Applica le basi risultano più allineate e un solo Annulla ripristina i tratti."
            ),
            .init(
                "Riseleziona due righe, apri Riadatta alla larghezza e avvicina le maniglie. Prova Uniforma dimensione o Spazio tra le righe su una copia.",
                "Le parole si spostano intere nell’anteprima. La grafia resta inchiostro selezionabile. Nessuna modifica compare prima di Applica."
            ),
        ],
        "text-scripts": [
            .init(
                "Scrivi H2O e x2 in una casella. Seleziona il 2 di H2O e applica Pedice, poi seleziona il 2 di x2 e applica Apice.",
                "Il primo 2 scende e il secondo sale. Gli altri caratteri mantengono lo stile. Annulla rimuove una formattazione alla volta."
            ),
            .init(
                "Copia del testo in grassetto da un’app compatibile. Incollalo in due caselle, nella prima con Incolla, nella seconda con ⇧⌘V da tastiera.",
                "Il primo incollato conserva il grassetto se la fonte ha copiato RTF. Il secondo adotta lo stile della destinazione."
            ),
        ],
        "subject-palettes": [
            .init(
                "Crea un set Anatomia con tre colori, selezionalo e passa dalla Penna all’Evidenziatore. Riapri Palette e poi torna al set precedente.",
                "Compaiono i campioni del set. I recenti dei due strumenti restano distinti e la selezione di un set non cancella i recenti."
            ),
        ],
        "marker-rectangle": [
            .init(
                "Scrivi una riga con Penna, poi imposta Rettangolo in Evidenziatore. Trascina fra due angoli sopra la riga e sposta il rettangolo con il lazo.",
                "Il riquadro si sposta intero e il testo sottostante rimane leggibile. Puoi regolarne l’opacità."
            ),
            .init(
                "Su una pagina PDF importata prova Aggancia alle righe del PDF su due righe. Passa Gomma Solo evidenziatore sulla prima zona.",
                "L’aggancio usa le righe riconosciute. La cancellazione rimuove il colore toccato e conserva il PDF."
            ),
        ],
        "zoom-writing": [
            .init(
                "Apri Finestra di scrittura su carta a righe. Scrivi nella finestra, sposta il riquadro turchese e usa Nuova riga. Chiudi con il comando dedicato.",
                "L’inchiostro è nella zona indicata del foglio. Nuova riga cambia la posizione della finestra. I tratti restano dopo la chiusura."
            ),
            .init(
                "Regola lo zoom, attiva Avanza dopo il tratto e scrivi vicino al margine destro. Chiudi la finestra e prova Annulla.",
                "La zona ingrandita avanza. Annulla agisce sul tratto della pagina, anche a finestra chiusa."
            ),
        ],
        "audio-replay-modes": [
            .init(
                "Registra una prova di 15 secondi scrivendo un tratto all’inizio e uno alla fine. Riascolta con Segui in tempo reale, poi Mostra tutto.",
                "La prima modalità segue i tratti nel tempo. La seconda li mostra tutti e segnala quello corrispondente all’ascolto."
            ),
            .init(
                "Aggiungi un segnalibro audio durante una prova. Apri Punti chiave e passa al punto successivo.",
                "La posizione di ascolto salta al punto disponibile. Il file audio conserva la sua durata."
            ),
        ],
        "sections-outline": [
            .init(
                "Crea due sezioni, rientra la seconda sotto la prima, comprimi il ramo e riaprilo. Riordina la sezione padre.",
                "La sottosezione si nasconde e riappare con il ramo. Quando trascini il padre, la figlia lo segue e le pagine restano associate."
            ),
        ],
        "drawing-squares": [
            .init(
                "Scegli Squadra 45° dal + cerchiato, ruota e ingrandisci, poi traccia vicino a un bordo e allontana leggermente la punta durante il tratto.",
                "La linea rimane agganciata al bordo scelto fino al rilascio. Spostare la guida dopo il rilascio lascia il tratto dov’è."
            ),
            .init(
                "Sostituisci la guida con Squadra 30°/60°, apri le opzioni dal catalogo e disegna sui due bordi obliqui.",
                "Vedi la nuova squadra al posto della precedente. I due tratti seguono i bordi scelti."
            ),
        ],
        "snap-align": [
            .init(
                "Crea due rettangoli. Attiva le guide di aggancio nelle opzioni di scrittura, trascina un oggetto vicino al bordo o al centro dell’altro e poi selezionali insieme.",
                "La guida segnala il punto di aggancio. Allinea nella selezione mette i due bordi in linea."
            ),
            .init(
                "Crea un terzo rettangolo, seleziona tutti e usa il comando di distribuzione. Poi annulla.",
                "Le distanze si uniformano. Annulla ripristina le posizioni disuguali."
            ),
        ],
        "about": [
            .init(
                "Apri Informazioni su NeuralNotes in libreria e annota versione e build prima di scrivere una segnalazione.",
                "Il numero di build distingue la versione che stai usando da quella di un altro dispositivo."
            ),
        ],
        "shape-tools": [
            .init(
                "Crea un poligono, una stella e un arco. Cambia un parametro geometrico in ciascuno e applica uno stile diverso a due figure selezionate.",
                "Ciascuna forma conserva i suoi parametri. Stile forme modifica le figure selezionate e Annulla ripristina lo stile in un passo."
            ),
        ],
        "shape-recognition": [
            .init(
                "Confronta Disattivo, Tieni ferma la punta e Automatico disegnando tre volte lo stesso cerchio con Penna.",
                "Disattivo conserva l’inchiostro originale. In Tieni ferma la punta la correzione richiede la sosta, mentre Automatico valuta il tratto al rilascio."
            ),
            .init(
                "In Forme da riconoscere scegli Rettangolo, prova Forma modificabile e poi Tratto di penna su due prove simili.",
                "Oggetti permette di modificare il primo come forma. Il secondo rimane inchiostro. L’avviso Annulla recupera il tratto originale."
            ),
        ],
    ]

    private static let part2: [String: [GuideExercise]] = [
        "library": [
            .init(
                "Crea il quaderno Laboratorio, spostalo in una cartella, aggiungi un tag e marcane il preferito. Cerca il nome in libreria.",
                "Il quaderno compare nella cartella scelta e nei preferiti. La ricerca restituisce il quaderno."
            ),
        ],
        "cover": [
            .init(
                "Imposta una copertina con motivo e colore, poi prova l’anteprima dell’ultima pagina modificata. Riapri il quaderno.",
                "Cambia la copertina in libreria. Le pagine mantengono il proprio contenuto."
            ),
        ],
        "tabs": [
            .init(
                "Apri due quaderni di prova dal menu del titolo. Scrivi A nel primo e B nel secondo. Passa due volte fra le schede e chiudi la seconda.",
                "Ogni quaderno conserva la propria pagina e il suo tratto. La scheda chiusa scompare dopo il salvataggio."
            ),
        ],
        "pen": [
            .init(
                "Scrivi una riga sottile blu e una più spessa rossa. Cambia all’Evidenziatore e torna alla Penna.",
                "I tratti già scritti mantengono colore e spessore. I recenti della penna sono ancora disponibili."
            ),
        ],
        "marker": [
            .init(
                "Scrivi una parola nera e passa l’evidenziatore sopra. Scegli Gomma → Solo evidenziatore e passa nella stessa zona.",
                "Il colore sparisce. La parola scritta con Penna rimane."
            ),
        ],
        "eraser": [
            .init(
                "Traccia due segmenti lunghi. Taglia il primo a metà con Gomma parziale e tocca il secondo con Tratto intero. Poi prova Annulla.",
                "Il primo è interrotto nella zona cancellata. Il secondo sparisce per intero e Annulla lo ripristina."
            ),
            .init(
                "Aggiungi una foto e una forma vicino a un tratto. Prova Solo immagini con Cancella anche gli oggetti attivo e passa sui tre elementi.",
                "Si elimina l’immagine toccata. La forma e l’inchiostro restano. Annulla recupera l’immagine."
            ),
        ],
        "undo": [
            .init(
                "Scrivi X, tocca Annulla, poi Ripristina. Annulla di nuovo e scrivi Y.",
                "X scompare e ritorna. Dopo il nuovo tratto Y, Ripristina non riporta in vita X."
            ),
            .init(
                "Inserisci una forma e cambia colore o stile. Usa le frecce in alto anche in Solo foglio.",
                "Le azioni si annullano nell’ordine inverso e si ripristinano fino allo stato precedente. Il foglio resta aperto."
            ),
        ],
        "lasso": [
            .init(
                "Scrivi due parole e aggiungi una foto. Tieni premuto Lazo, scegli Solo inchiostro e cerchia una parola con la foto. Ripeti con Lazo libero: inchiostro e oggetti.",
                "Nella prima modalità la foto non entra nella selezione; nella seconda si muove insieme ai tratti selezionati."
            ),
            .init(
                "Prova Area e Aggiungi alla selezione, poi applica uno spessore a tratti e forme che lo supportano. Tocca fuori e usa Annulla.",
                "Vengono modificati soltanto i contenuti selezionati. Annulla ripristina lo spessore."
            ),
        ],
        "objects": [
            .init(
                "Inserisci un testo e una foto sovrapposti. Tocca la foto con Oggetti, spostala, ruotala e cambia l’ordine davanti o dietro.",
                "Le maniglie agiscono sulla foto. L’ordine cambia quando i due elementi si sovrappongono."
            ),
            .init(
                "Blocca un elemento e prova a muoverlo. Sbloccalo dal menu, poi copialo come immagine.",
                "L’oggetto bloccato resta fermo. La copia PNG contiene la selezione, con trasparenza al posto della carta."
            ),
        ],
        "text": [
            .init(
                "Inserisci una casella, scrivi titolo e corpo, applica due stili e un colore. Tocca Fine e riapri la casella.",
                "La formattazione rimane modificabile. Il resto del foglio rimane visibile."
            ),
            .init(
                "Tieni premuto Testo, disattiva Resta attivo, crea una casella e chiudila. Ripeti con Resta attivo.",
                "Dopo Fine il comportamento cambia con l’opzione. Quando Testo resta attivo puoi toccare un secondo punto per creare un’altra casella."
            ),
        ],
        "shapes": [
            .init(
                "Trascina una Freccia da sinistra a destra e un Triangolo tra due angoli. Seleziona ogni forma con Oggetti.",
                "La punta della freccia è al punto di rilascio. Entrambe le figure sono oggetti con maniglie."
            ),
        ],
        "held-shapes": [
            .init(
                "Con Penna e Tieni ferma la punta, traccia una retta leggermente ondulata. Fermati circa mezzo secondo alla fine e rilascia dopo l’anteprima.",
                "Il tratto diventa diritto. Una seconda linea tracciata senza sosta in questa modalità conserva l’andamento libero."
            ),
            .init(
                "Disegna un cerchio quasi chiuso e un rettangolo, fermandoti alla fine. Dopo la correzione scrivi un segno vicino e annulla una volta.",
                "Resta la figura corretta. Annulla rimuove il segno successivo senza far ricomparire il tratto storto."
            ),
        ],
        "ruler": [
            .init(
                "Sposta, ruota e pizzica il righello con le dita. Con Penna inizia vicino al bordo e allontanati leggermente mentre disegni.",
                "La penna resta agganciata al bordo iniziato. Disattiva Righello e verifica che un tratto libero non si agganci più."
            ),
        ],
        "protractor": [
            .init(
                "Seleziona Goniometro 180°, traccia un arco al bordo e un raggio dal centro. Passa a 360° dalle opzioni.",
                "L’arco è regolare e il raggio parte dal centro. Cambia la guida senza cambiare i tratti già disegnati."
            ),
            .init(
                "Attiva Misura e traccia due raggi che formano circa 90°. Esci da Misura.",
                "Compare un valore prossimo a 90°. Il gesto di misura non lascia inchiostro permanente."
            ),
        ],
    ]

    private static let part3: [String: [GuideExercise]] = [
        "selection-transfer": [
            .init(
                "Seleziona una forma con Oggetti e usa Copia o sposta in un’altra pagina. Copiala nella pagina 2, poi sposta l’originale su una pagina nuova.",
                "La copia rimane in pagina 2 e lo spostamento svuota soltanto la posizione d’origine. Un Annulla ripristina l’ultima operazione."
            ),
            .init(
                "Apri Trascina sulle miniature, scegli Copia e tieni premuta la selezione, poi trascinala sulla miniatura.",
                "La pagina di destinazione contiene una copia e l’originale è ancora presente."
            ),
        ],
        "type-deletion": [
            .init(
                "Nel quaderno di prova metti un’immagine e un tratto in due pagine. Apri Elimina elementi per tipo, scegli queste pagine e seleziona soltanto immagini.",
                "Il conteggio corrisponde alle immagini selezionate. I tratti restano e un Annulla ripristina le immagini."
            ),
        ],
        "workspace": [
            .init(
                "Duplica un’attività, sposta la toolbar sul lato e cambiane due preferiti. Riattiva il profilo precedente.",
                "Ogni profilo mantiene posizione e strumenti propri. Il quaderno conserva le preferenze dopo la riapertura."
            ),
        ],
        "focus": [
            .init(
                "Attiva Solo foglio e apri gli strumenti essenziali. Seleziona un preferito, annulla un tratto e torna alla vista normale.",
                "I comandi restano in alto e l’area di scrittura usa più altezza. La barra delle pagine torna nella vista normale."
            ),
        ],
        "zoom": [
            .init(
                "Ruota l’iPad in orizzontale. Fai doppio tocco per passare alla larghezza e ripetilo per tornare a pagina intera. Pizzica e spostati con le dita.",
                "I margini laterali diminuiscono in modalità larghezza e ritornano in pagina intera. La penna continua a scrivere sulla pagina."
            ),
            .init(
                "Su tre pagine passa da Verticale continuo a Sfoglio orizzontale e naviga con le dita. Ripeti con Scrittura con il dito e due dita.",
                "Il verso di navigazione cambia con la modalità e il gesto non lascia inchiostro quando usi il numero di dita previsto."
            ),
        ],
        "scrubber": [
            .init(
                "Crea cinque pagine nel quaderno di prova. Trascina l’indicatore verso la quarta, guarda l’anteprima, rilascia e poi usa il contatore per tornare alla seconda.",
                "Il numero è visibile durante il gesto. La pagina cambia al rilascio e Vai apre la pagina digitata."
            ),
        ],
        "paper": [
            .init(
                "Imposta quadretti su pagina 1 e puntini su pagina 2. Torna a pagina 1 e prova un colore della carta diverso.",
                "Cambia solo la pagina a cui applichi il modello. Inchiostro e oggetti sono ancora sopra lo sfondo."
            ),
        ],
        "page-trash": [
            .init(
                "Nel quaderno di prova seleziona due pagine dalla griglia e spostale nel cestino. Apri Pagine eliminate e ripristinane una.",
                "Entrambe spariscono dalla griglia attiva, poi torna soltanto quella ripristinata."
            ),
        ],
        "sections": [
            .init(
                "Assegna un titolo e un segnalibro a pagina 2, aggiungila a una sezione e aprila dall’indice. Chiudi e riapri il quaderno.",
                "Il titolo e il segnalibro aiutano a ritrovarla. La sezione punta alla pagina giusta e la pagina recente viene ricordata."
            ),
        ],
        "photo": [
            .init(
                "Inserisci da Foto una foto prospettica di un foglio. Prova Raddrizza, sposta gli angoli, ruota e conferma. Riapri Raddrizza dalla selezione.",
                "La foto appare dritta nel quaderno. Puoi cambiare ancora le correzioni e annullarle. L’originale in Foto rimane intatto."
            ),
            .init(
                "Scegli una seconda foto e un ritaglio rettangolare stretto. Poi seleziona la foto sul foglio e spostala.",
                "Si vede soltanto la zona ritagliata. L’immagine resta un oggetto indipendente."
            ),
        ],
        "scanner": [
            .init(
                "Su iPad fisico scansiona due fogli con ⋯ → Inserisci → Scansiona documento. Poi affianca File e trascina una foto di prova.",
                "Le scansioni sono inserite nel quaderno dopo la conferma. Il trascinamento inserisce la foto nella pagina scelta."
            ),
        ],
        "pdf-import": [
            .init(
                "Salva in File un PDF con tre pagine e importalo dalla libreria. Annota pagina 2, chiudi, riapri e verifica anche il PDF originale in File.",
                "Il quaderno ha tre pagine, l’annotazione compare solo sulla seconda e il file originale resta uguale."
            ),
        ],
        "pdf-study": [
            .init(
                "In un quaderno già aperto affianca un PDF digitale, cerca una parola e vai al risultato successivo. Se è presente un indice, apri una voce.",
                "Il pannello salta alle occorrenze e alle pagine dell’indice. La pagina del quaderno può restare la stessa."
            ),
            .init(
                "Attiva Seleziona con la Lente nel menu del pannello e cerchia un termine con Pencil. Controlla l’anteprima e chiudila.",
                "Il pannello propone la parola selezionata. Il PDF esterno rimane consultabile senza nuove annotazioni."
            ),
        ],
        "export": [
            .init(
                "Esporta un quaderno di prova come PDF e come backup nativo. Apri il PDF in File e importa il backup come copia dalla libreria.",
                "Il PDF riproduce le pagine. La copia nativa resta modificabile e ha una sua identità."
            ),
        ],
    ]

    private static let part4: [String: [GuideExercise]] = [
        "record": [
            .init(
                "Registra una prova di 30 secondi, passa in Solo foglio, tocca REC, metti in pausa, riprendi e premi Stop. Riascolta.",
                "Il timer resta raggiungibile. La sessione contiene entrambi i segmenti di parlato con la pausa esclusa dal tempo registrato."
            ),
            .init(
                "Su iPad fisico e app firmata, avvia una prova separata, blocca brevemente lo schermo e riprendi il controllo. Arresta e ascolta la parte centrale.",
                "Controlla che il parlato durante il blocco si senta. Se manca, verifica la sessione per identificare un’interruzione di iPadOS."
            ),
        ],
        "audio-link": [
            .init(
                "Durante una registrazione scrivi INTRO, aspetta dieci secondi e scrivi FINE. Dopo Stop usa Collegamento audio toccando FINE; poi usa −15 s.",
                "L’ascolto riparte vicino al momento in cui hai scritto FINE. Il salto indietro raggiunge il contesto precedente."
            ),
        ],
        "audio-import": [
            .init(
                "Da Memo Vocali salva un breve M4A in File, apri Audio → Importa registrazione e selezionalo. Chiudi e riapri il quaderno.",
                "Il titolo e la riproduzione sono disponibili anche dopo la riapertura. L’audio originale resta in File."
            ),
        ],
        "transcript": [
            .init(
                "Trascrivi una clip chiara, correggi una parola, rinomina il testo e riaprilo. Esporta testo e confronta i riferimenti temporali.",
                "Titolo e correzione restano salvati. Il file esportato include il testo corretto e i tempi."
            ),
            .init(
                "Se hai una registrazione lunga di prova, interrompi a elaborazione avviata e prova a riprendere. Apri la parte già disponibile.",
                "Le parti completate rimangono consultabili mentre riprendi le finestre rimaste. La registrazione resta riproducibile."
            ),
        ],
        "audio-storage": [
            .init(
                "Esporta una clip, poi comprimi una registrazione PCM conclusa dal pannello spazio. Verifica durata, riproduzione e riferimento audio.",
                "La copia esportata si apre in File. La compressione riduce lo spazio mantenendo la registrazione ascoltabile e il riferimento utilizzabile."
            ),
        ],
        "search": [
            .init(
                "Inserisci la parola mitocondrio come Testo in pagina 2, scrivila anche a mano in pagina 3 e avvia Riconosci testo pagina. Cerca la parola nel quaderno.",
                "Trovi subito il testo digitato e trovi la grafia se riconosciuta. Toccando un risultato arrivi alla pagina corrispondente."
            ),
        ],
        "lens": [
            .init(
                "Su una parola digitata, tocca con Lente per selezionarla; prova poi a sottolineare e cerchiare zone diverse. Verifica il testo selezionato prima di chiedere.",
                "L’anteprima risponde alla zona scelta. Puoi aprire, annullare o modificare l’azione prima di salvare una nota."
            ),
            .init(
                "Con un servizio AI configurato, chiedi di spiegare un termine neutro. Chiudi la prima risposta e salva la seconda come nota o inseriscila nel foglio.",
                "Solo l’azione esplicita crea il contenuto permanente. La nota salvata si può riaprire."
            ),
        ],
        "ai-connection": [
            .init(
                "Apri il pannello di connessione. Con un account configurato prova la verifica del motore e una domanda breve; senza servizi configurati osserva lo stato mostrato.",
                "L’app distingue una connessione disponibile da una mancante o non valida. Un errore del servizio non impedisce di scrivere sul foglio."
            ),
        ],
        "study": [
            .init(
                "Crea due pagine intitolate Cellula e Tessuti, con due frasi ciascuna. Seleziona una fonte nel pannello Studia e genera una sintesi locale.",
                "I punti rimandano al testo disponibile. Aprendo un riferimento puoi controllarne la pagina d’origine."
            ),
            .init(
                "Con un motore configurato genera glossario o mappa da una breve pagina di prova. Confronta termini e riferimenti col quaderno.",
                "Le voci usano la fonte scelta e puoi esaminare la risposta prima di conservarla."
            ),
        ],
        "flashcards": [
            .init(
                "Crea una scheda con domanda e risposta, avvia il ripasso e mostra la risposta. Registra un esito di difficoltà e riapri la scheda.",
                "La risposta è coperta finché non la riveli. L’esito modifica il prossimo ripasso previsto."
            ),
        ],
        "links": [
            .init(
                "Con due pagine crea un collegamento dalla prima alla seconda. Aprilo dal foglio, poi controlla i riferimenti in entrata nella destinazione.",
                "Il collegamento naviga alla pagina scelta. Il riferimento inverso riporta alla pagina di origine."
            ),
        ],
        "account": [
            .init(
                "Apri Informazioni account. Se il servizio è configurato, accedi con un’email di prova, verifica profilo e pannello privacy, poi esci.",
                "Il profilo mostra lo stato dell’accesso. In assenza di un servizio configurato la guida resta consultabile e la libreria locale si apre."
            ),
        ],
        "account-sync": [
            .init(
                "Con due dispositivi autorizzati e un account configurato invia un piccolo quaderno di prova. Scaricalo sul secondo dispositivo e aprilo.",
                "Le pagine e i contenuti modificabili arrivano sul secondo dispositivo. In caso di conflitto puoi esaminare entrambe le copie."
            ),
        ],
        "icloud": [
            .init(
                  "Con una build abilitata a CloudKit e lo stesso Account Apple, sincronizza un quaderno di prova sul primo iPad e poi premi Sincronizza tutti sul secondo.",
                  "Il secondo iPad riceve lo stesso quaderno. Se la build non abilita CloudKit, il pannello indica come salvare la copia in File."
            ),
              .init(
                  "Da Account Apple e iCloud salva una copia di un quaderno chiuso su iCloud Drive. Modifica l’originale, poi ripristina il file .nnbackup.",
                  "La libreria mostra sia l’originale con la modifica sia una copia indipendente nello stato del backup."
              ),
        ],
    ]

    private static let part5: [String: [GuideExercise]] = [
        "backup": [
            .init(
                "Esporta una copia nativa di un quaderno di prova in File. Fai una modifica e ripristina la copia come nuovo quaderno.",
                "Il quaderno ripristinato contiene lo stato precedente e quello originale rimane disponibile."
            ),
        ],
        "status": [
            .init(
                "Scrivi un tratto, osserva l’icona di stato e apri i dettagli. Usa Salva adesso dal menu Documento, chiudi e riapri.",
                "Lo stato mostra la modifica finché è in corso, poi conferma il salvataggio. Il nuovo tratto è ancora presente."
            ),
        ],
        "diagnostics": [
            .init(
                "Nella versione di sviluppo apri Account e servizi → Assistenza sui quaderni → Verifica sul dispositivo ed esegui i controlli. Consulta i risultati prima di tornare al quaderno.",
                "Puoi distinguere verifiche superate, non disponibili e fallite. La prova non aggiunge modifiche ai tuoi quaderni."
            ),
        ],
        "laser": [
            .init(
                "Da ⋯ attiva Puntatore laser, indica due parole e attendi la dissolvenza. Poi disattivalo.",
                "L’indicazione scompare senza un segno permanente. Riprendendo la Penna puoi scrivere normalmente."
            ),
        ],
        "study-tape": [
            .init(
                "Scrivi tre parole e coprile con scotch. Avvia Ripasso, scopri la prossima risposta, usa Ricopri e poi Fine.",
                "Le risposte si scoprono una alla volta. Ricopri le nasconde di nuovo. Fine riattiva lo strumento precedente."
            ),
        ],
        "diagrams": [
            .init(
                "Crea due forme con etichetta, trascina da un punto blu del primo alla seconda. Cambia il connettore in Curvo e sposta un blocco.",
                "Il collegamento resta attaccato anche dopo lo spostamento. Puoi cambiare etichetta e forma del connettore."
            ),
        ],
        "marker-words": [
            .init(
                "Su un PDF digitale seleziona Parole e sottolinea una sola parola, poi fai un passaggio vuoto a fianco. Prova Annulla.",
                "Cambia colore soltanto la parola riconosciuta. Il passaggio nel vuoto non lascia segni. Annulla toglie l’evidenziazione."
            ),
            .init(
                "Passa a Tratto libero, scegli 1 pt e traccia una riga. Cambia zoom e aggiungine un’altra con la stessa impostazione.",
                "Lo spessore fisico del tratto sul documento resta uguale; lo zoom cambia solo come lo vedi."
            ),
        ],
        "pdf-highlight": [
            .init(
                "Importa un PDF digitale, aprilo affiancato come fonte interna e seleziona due righe. Usa Evidenzia o Sottolinea e poi controlla la pagina nell’editor.",
                "L’annotazione è allineata al testo della pagina. Lo stesso comando su PDF esterno è disabilitato."
            ),
        ],
        "tool-options": [
            .init(
                "Tocca Gomma una volta, poi tienila premuta. Apri quindi Goniometro tramite i cursori del catalogo invece di aggiungerlo ai preferiti.",
                "Il tocco seleziona lo strumento. La pressione prolungata apre modalità e dimensione, mentre i cursori aprono le opzioni del goniometro."
            ),
            .init(
                "Entra in Solo foglio, apri gli strumenti essenziali e tieni premuta la gomma. Cambia da Tratto intero a Parziale e chiudi.",
                "Le opzioni si aprono anche qui e la gomma cambia modalità senza uscire da Solo foglio."
            ),
        ],
        "scratch": [
            .init(
                "Scrivi ROSSO e VERDE con tratti separati e spazio fra le parole. Passa in uno zig zag serrato solo sopra ROSSO. Poi annulla.",
                "Spariscono i tratti di ROSSO raggiunti dallo scarabocchio, VERDE resta e Annulla recupera l’inchiostro tolto."
            ),
            .init(
                "Crea una casella con Alfa Beta Gamma e chiudi la modifica. Con Penna scarabocchia Beta, poi ripeti la cancellazione in una casella attiva usando Scrivi a mano.",
                "Fuori dalla casella agisce la cancellazione di NeuralNotes sul livello modificabile. Nel campo attivo interviene la conversione di iPadOS. Le parole vicine restano leggibili."
            ),
        ],
        "pencil-gestures": [
            .init(
                "Pizzica, scorri con un dito e fai doppio tocco con Scrittura con il dito disattivata. Attiva l’opzione e ripeti con due dita.",
                "L’ingrandimento cambia senza lasciare linee. Con l’opzione attiva un dito è disponibile per scrivere."
            ),
            .init(
                "Abilita Trascina oltre il fondo per avanzare e prova sull’ultima pagina in navigazione verticale. Se la tua Pencil supporta il doppio tocco sul corpo, imposta il cambio gomma e provalo.",
                "Aggiungi una nuova pagina trascinando oltre il fondo. Su hardware compatibile il gesto della Pencil alterna la gomma con l’ultimo strumento da disegno."
            ),
        ],
        "keyboard-editor": [
            .init(
                "Con tastiera fisica e campo di testo chiuso premi P, E, H, L, T, S, G e R. Prova le frecce e ⇧⌘N in un quaderno di prova.",
                "Le lettere cambiano strumento, le frecce cambiano pagina se esiste e ⇧⌘N aggiunge un foglio."
            ),
            .init(
                "Prova ⌘+, ⌘−, ⌘0 e ⌘.; usa ⌘F, ⇧⌘F e ⌘K; apri e chiudi una scheda con ⌘T e ⌘W.",
                "Zoom e Solo foglio reagiscono. Si aprono la ricerca del quaderno e quella globale; la Lente alterna il proprio stato. I comandi scheda agiscono sul quaderno aperto."
            ),
            .init(
                "Con una forma di prova usa ⌘A per selezionarla, ⌘C e ⌘V per copiarla e incollarla, ⌘D per duplicarla e ⌘X per tagliare. Prova poi ⌘Z e ⇧⌘Z.",
                "Vedi gli oggetti comparire o sparire come previsto e la cronologia ripercorre taglio e incolla. In un campo testo le lettere normali continuano a scrivere."
            ),
        ],
        "pen-presets": [
            .init(
                "Scegli due tipi diversi fra quelli disponibili e crea un preset con colore insolito e spessore marcato. Cambia impostazioni, poi richiama il preset.",
                "Il richiamo ripristina insieme punta, colore e spessore sui nuovi tratti. I tratti già disegnati non cambiano."
            ),
            .init(
                "Passa all’Evidenziatore, scegli un colore e torna alla Penna. Richiama il preset 1 da tastiera se collegata.",
                "Ogni strumento conserva i propri recenti e il numero richiama il preset salvato."
            ),
        ],
        "pdf-snippet": [
            .init(
                "Apri un PDF esterno affiancato, attiva il ritaglio e trascina sulle sole parti di una figura. Sposta l’immagine inserita con Oggetti e poi usa Annulla.",
                "Il quaderno riceve un oggetto immagine della sola area scelta. Il PDF originario non cambia; Annulla ripercorre spostamento e inserimento."
            ),
            .init(
                "Nello stesso PDF seleziona con le maniglie una frase e tocca Inserisci testo. Riapri il risultato con Testo e modifica una parola.",
                "Il risultato è una casella modificabile e resta indipendente dall’immagine ottenuta con Ritaglia."
            ),
        ],
    ]

    private static let part6: [String: [GuideExercise]] = [
        "shape-line-arrow": [
            .init(
                "Disegna una Linea e una Freccia. Muovi un estremo con Oggetti e cambia le punte o il tratteggio della freccia.",
                "Le maniglie spostano l’estremo senza cambiare quello opposto. La freccia mantiene lo stile applicato dopo averla deselezionata."
            ),
        ],
        "shape-closed": [
            .init(
                "Crea un’ellisse larga, un rettangolo, un triangolo e un rombo. Riempi due figure, arrotonda il rettangolo e ruota il triangolo.",
                "Le figure restano distinte e modificabili con Oggetti. La rotazione del triangolo non cambia il rombo."
            ),
        ],
        "shape-polygons": [
            .init(
                "Disegna un poligono a sei lati, una stella, un arco e un poligono libero con quattro vertici. Cambia la geometria di ciascuno.",
                "Il poligono regolare cambia numero di lati, la stella cambia le punte, l’arco cambia apertura e il poligono libero segue i suoi vertici."
            ),
        ],
        "text-scribble": [
            .init(
                "Con Scrivi a mano attivo crea una casella e scrivi uno due tre. Cancella due con uno zig zag e inserisci nuovo nello spazio con la pressione prolungata.",
                "Il campo conserva testo digitato contenente uno e tre. La parola aggiunta compare nella posizione in cui hai scritto."
            ),
            .init(
                "Seleziona una parola della casella con un cerchio o doppio tocco. Unisci o separa due caratteri con una linea verticale e poi tocca Fine.",
                "L’azione modifica il testo editabile. Quando esci dal campo torni a gestire la pagina."
            ),
        ],
        "study-maps": [
            .init(
                "Scrivi una voce principale e due sotto-voci con due spazi. Inseriscile come checklist e trasformale in una mappa separata.",
                "La checklist conserva rientri e caselle come testo. Nella mappa le due sotto-voci partono dal nodo principale."
            ),
            .init(
                "Crea una mappa da un modello, rinomina un nodo con doppio tocco e collegalo a una seconda pagina.",
                "L’etichetta cambia, la freccia segue il nodo spostato e il link apre la pagina di destinazione."
            ),
        ],
        "study-notes": [
            .init(
                "Crea un post-it Dubbio rosa e uno Esempio di un altro colore. Richiudi il primo, vai a un’altra pagina e riaprilo dall’elenco.",
                "Le due note si distinguono. L’elenco porta alla pagina giusta e conserva il testo del post-it richiuso."
            ),
            .init(
                "Crea due capitoli colorati e assegna loro due pagine diverse. Tocca le linguette laterali in ordine inverso.",
                "Ogni linguetta apre la propria sezione e conserva il colore dopo la riapertura del quaderno."
            ),
        ],
        "layer-exports": [
            .init(
                "Disegna due segni su livelli separati. Nascondi il secondo, esporta PDF dei soli visibili e controlla il file in File.",
                "Il PDF contiene solo il segno visibile. La versione nativa del quaderno conserva entrambi i livelli."
            ),
            .init(
                "Crea uno scotch sopra una risposta e prepara due PDF, uno con risposte coperte e uno senza scotch.",
                "Nel primo la risposta resta nascosta. Nel secondo è leggibile e l’appunto originale rimane coperto nel quaderno."
            ),
        ],
        "quick-note": [
            .init(
                "Tocca Nota rapida, scrivi un promemoria e torna in libreria. Rinomina il quaderno da Inbox, spostalo in una cartella e ritrovalo.",
                "Il promemoria è ancora nel quaderno dopo l’archiviazione."
            ),
            .init(
                "Sposta il quaderno di prova nel Cestino della libreria e ripristinalo da lì.",
                "Torna il quaderno con tutte le sue pagine."
            ),
        ],
        "clipboard-selection": [
            .init(
                "Seleziona una forma e un tratto, copiali e incollali. Taglia la copia e annulla. Esporta poi la sola selezione come PNG.",
                "L’originale rimane. Annulla recupera la copia tagliata. Il PNG mostra la selezione senza lo sfondo della pagina."
            ),
        ],
        "document-attachments": [
            .init(
                "Aggiungi un documento di prova con Aggiungi allegato e confronta il numero di pagine. Importa poi un PDF come pagine nel quaderno.",
                "L’allegato conserva il file senza aggiungere fogli. L’importazione PDF incrementa il numero di pagine."
            ),
        ],
        "lecture-notes": [
            .init(
                "In una trascrizione passa fra Per minuto e Per capitoli. Tocca un riferimento e controlla l’inizio dell’ascolto, poi esporta capitoli.",
                "Audio e riferimenti concordano. Il Markdown conserva il testo e le indicazioni temporali."
            ),
            .init(
                "Con un servizio idoneo configurato, genera una sbobina da una clip senza dati personali. Apri la lettura, ascolta un blocco, poi inserisci come pagine nel quaderno di prova.",
                "I blocchi si possono confrontare con l’audio. Le pagine vengono create dopo aver scelto l’inserimento."
            ),
        ],
        "search-global": [
            .init(
                "Aggiungi il termine mitocondrio a due quaderni. Cerca prima nel documento aperto e poi con Cerca negli appunti in libreria.",
                "La ricerca locale restituisce soltanto il quaderno aperto. Quella in libreria trova i due quaderni."
            ),
        ],
        "study-session": [
            .init(
                "Crea tre domande e copri le risposte con scotch di colori o stili diversi. Avvia Ripasso e prova Scopri prossima, Ricopri e Fine.",
                "La domanda resta leggibile. Scopri prossima rivela in sequenza, Ricopri nasconde e Fine riattiva lo strumento."
            ),
        ],
        "pencil-navigation-rail": [
            .init(
                "Da pagina 2 di un quaderno di quattro fogli usa ⋯ in basso per inserire una pagina bianca dopo quella corrente, poi trascina il cursore fino all’ultima.",
                "Il nuovo foglio compare dopo pagina 2. L’anteprima si aggiorna durante il gesto e la pagina cambia al rilascio."
            ),
        ],
    ]
}
