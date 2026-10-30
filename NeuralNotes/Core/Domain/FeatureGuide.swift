import Foundation

public enum GuideCategory: String, CaseIterable, Sendable {
    case library = "Libreria", writing = "Scrittura", pages = "Pagine e PDF", audio = "Audio", study = "Studio e AI", protection = "Account e protezione"
}
public struct FeatureGuide: Identifiable, Sendable {
    public let id: String
    public let category: GuideCategory
    public let title: String
    public let icon: String
    public let summary: String
    public let steps: [String]
    public let tools: [WorkspaceTool]
    public init(_ id: String, _ category: GuideCategory, _ title: String, _ icon: String, _ summary: String,
                _ steps: [String], tools: [WorkspaceTool] = []) {
        self.id = id; self.category = category; self.title = title; self.icon = icon; self.summary = summary; self.steps = steps; self.tools = tools
    }
    public func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        let content = ([title, summary, category.rawValue] + steps).joined(separator: " ")
        return words.allSatisfy { content.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
    public static func completedIDs(_ stored: String) -> Set<String> {
        let ids = (try? JSONDecoder().decode([String].self, from: Data(stored.utf8))) ?? []
        return Set(ids).intersection(Set(catalog.map(\.id)))
    }
    public static func store(_ ids: Set<String>) -> String {
        String(data: (try? JSONEncoder().encode(ids.intersection(Set(catalog.map(\.id))).sorted())) ?? Data(), encoding: .utf8) ?? "[]"
    }
    public static let catalog: [FeatureGuide] = [
        .init("snap-align", .writing, "Aggancio e allineamento", "align.horizontal.left", "Sposta con precisione e distribuisci gli oggetti.", [
            "Nel Workspace apri Aggancio. Scegli oggetti, griglia, linee guida e Mantieni proporzioni. Le opzioni sono separate per attività.",
            "Con Oggetti trascina vicino a bordi, centri, margini o griglia. Le guide sottili indicano gli allineamenti; due segni = mostrano spaziature uguali tra oggetti.",
            "Appoggia un secondo dito durante il trascinamento, o tieni premuto ⌥, per sospendere l’aggancio. Avviare lo scorrimento con due dita continua a spostare la pagina.",
            "Seleziona almeno due oggetti e apri Allinea e distribuisci nella barra di selezione o nel menu contestuale. Per distribuire servono tre oggetti. Un solo Annulla ripristina tutta l’operazione.",
            "Il lazo tratta i tratti selezionati come un riquadro. Gli oggetti bloccati o ruotati non attraggono il trascinamento." ], tools: [.objects, .lasso]),
        .init("about", .library, "Informazioni e crediti", "info.circle", "Controlla versione e build prima di inviare una segnalazione.", [
            "Nella libreria apri Informazioni su NeuralNotes, accanto alla guida; la trovi anche in Account e servizi.",
            "Leggi versione e build oppure premi Copia informazioni. Il testo contiene solo versione, sistema e modello del dispositivo, senza appunti o dati dell’account.",
            "Consulta ringraziamenti, privacy e licenze. Se l’indirizzo è configurato, usa Invia un feedback o Segnala un problema." ]),
        .init("shape-tools", .writing, "Forme e maniglie", "square.on.circle", "Rombi, poligoni, stelle e archi modificabili.", [
            "Tieni premuto uno strumento forma o apri Inserisci foto o forma. Scegli la figura; per poligoni e stelle imposta il numero di lati o punte nelle opzioni.",
            "Trascina tra due angoli. Per frecce e linee parti dalla coda; per un arco trascina tra gli estremi della corda.",
            "Passa a Oggetti e seleziona il contorno. Trascina angoli, rotazione o maniglie specifiche. Sul poligono libero tieni premuto un lato per aggiungere un vertice, o un vertice per rimuoverlo.",
            "Con una o più forme selezionate apri Stile forme. Scegli contorno, riempimento, tratteggio e punte, poi Applica. Annulla ripristina lo stile precedente in un passo." ], tools: [.line, .arrow, .ellipse, .rectangle, .triangle, .objects]),
        .init("shape-recognition", .writing, "Riconoscimento automatico delle forme", "wand.and.stars", "Scegli quando correggere e se ottenere una forma o inchiostro.", [
            "Nel Workspace apri Riconoscimento forme. Scegli Spento, Tieni ferma la punta oppure Automatico al rilascio; puoi farlo anche dalle opzioni della penna.",
            "Scegli quali figure riconoscere e se ottenere una Forma modificabile o un Tratto di penna. L’evidenziatore rimane un tratto diritto.",
            "In modalità Tieni ferma la punta disegna la figura, fermati per circa mezzo secondo e solleva. In Automatico solleva normalmente: le figure riconosciute con sicurezza si correggono.",
            "L’avviso Corretto in… offre Annulla per ripristinare il tratto originale. Il riconoscimento è prudente vicino alla scrittura; puoi sempre usare gli strumenti forma espliciti." ], tools: [.pen, .marker]),
        .init("library", .library, "Crea e organizza i quaderni", "books.vertical", "Cartelle, tag, preferiti e recenti.", [
            "Dalla libreria premi + per creare un quaderno e scegli titolo e cartella.",
            "Usa il menu del quaderno per rinominarlo, spostarlo o gestire tag e preferiti. Crea cartelle dalla barra laterale.",
            "Ritrova gli ultimi quaderni nei recenti; usa Cerca e l’ordinamento per ridurre l’elenco." ]),
        .init("cover", .library, "Personalizza la copertina", "book.closed", "Colori, motivi, foto e anteprima degli appunti.", [
            "Apri il menu del quaderno e le opzioni della copertina.",
            "Scegli colore, motivo o un’immagine; puoi usare l’ultima pagina modificata come anteprima.",
            "Torna in libreria e verifica la copertina. La scelta cambia l’aspetto senza alterare le pagine." ]),
        .init("tabs", .library, "Schede aperte e finestre", "rectangle.on.rectangle", "Cambia quaderno dal titolo.", [
            "Nell’editor tocca il titolo del quaderno per mostrare quelli aperti.",
            "Scegli un altro quaderno o aprine uno dalla libreria. La croce chiude la scheda dopo aver salvato.",
            "Puoi affiancare finestre dai controlli iPadOS. Lo stesso quaderno resta protetto da modifiche simultanee in due editor." ]),
        .init("pen", .writing, "Penna e colori recenti", "pencil.tip", "Inchiostro, spessore e palette per strumento.", [
            "Seleziona la penna e scrivi con Pencil; le dita possono scorrere il foglio.",
            "Tieni premuta l’icona per le opzioni di penna e spessore. Tocca un colore o la palette per personalizzarlo.",
            "I colori e gli spessori recenti sono separati per strumento. Nel workspace puoi salvare i preferiti per attività." ], tools: [.pen]),
        .init("marker", .writing, "Evidenziatore", "highlighter", "Colori dedicati e cancellazione selettiva.", [
            "Scegli l’evidenziatore e il colore: i suoi recenti sono indipendenti dalla penna.",
            "Tieni premuto lo strumento per regolare lo spessore; passa sopra gli appunti per evidenziarli.",
            "Per togliere solo il colore usa la gomma con Solo evidenziatore: l’inchiostro della penna viene conservato." ], tools: [.marker]),
        .init("eraser", .writing, "Gomma e scarabocchio", "eraser", "Cancella parti di inchiostro o tratti con un gesto.", [
            "Tieni premuta la gomma per scegliere modalità, dimensione e cancellazione del solo evidenziatore.",
            "Per cancellare con la penna abilita Scarabocchio nel workspace e fai passate ravvicinate sopra i tratti da eliminare.",
            "Usa Annulla in caso di errore. Il testo convertito usa invece i gesti Scribble di iPadOS quando disponibili." ], tools: [.eraser]),
        .init("undo", .writing, "Annulla e ripristina", "arrow.uturn.backward", "Cronologia di inchiostro, testo, immagini e pagine.", [
            "Dopo aver concluso un tratto o una modifica premi la freccia Annulla nella toolbar.",
            "Ripristina riapplica l’azione annullata. Una nuova modifica dopo Annulla scarta il ramo da ripristinare.",
            "Le modifiche della pagina corrente appaiono subito e poi vengono salvate. Le operazioni fra pagine attendono anche il disco; controlla l’icona di stato." ]),
        .init("lasso", .writing, "Seleziona con il lazo", "lasso", "Muovi, ruota, ridimensiona e ricolora una selezione.", [
            "Scegli il lazo e circonda l’inchiostro o gli oggetti; tieni premuta l’icona per le modalità disponibili.",
            "Trascina la selezione e usa i controlli di trasformazione per dimensione e rotazione.",
            "Dal menu selezione puoi copiare, tagliare, duplicare, eliminare o cambiare colore dove supportato. Annulla ripristina la trasformazione." ], tools: [.lasso]),
        .init("objects", .writing, "Immagini e oggetti sul foglio", "cursorarrow.square", "Selezione diretta e disposizione degli inserimenti.", [
            "Scegli Oggetti e tocca una foto, una forma o un testo.",
            "Trascina per spostare; usa i controlli della selezione per ridimensionare, ruotare o regolare l’ordine.",
            "Il menu della selezione offre le azioni compatibili con quell’elemento. Tocca fuori per terminare." ], tools: [.objects]),
        .init("text", .writing, "Testo con Pencil e tastiera", "textformat", "Scrittura trasparente e formattazione.", [
            "Scegli Testo e tocca il foglio o una casella esistente. Scrivi con Pencil tramite Scribble di iPadOS oppure con la tastiera.",
            "Seleziona il testo per grassetto, corsivo, stili Titolo e Corpo, colore ed evidenziazione. I gesti Scribble agiscono nel campo attivo.",
            "Tocca Fine o cambia strumento. Se Pencil non converte la scrittura verifica Scrivi a mano nelle impostazioni Apple Pencil di iPadOS." ], tools: [.text]),
        .init("shapes", .writing, "Forme da punto a punto", "square.on.circle", "Rette, frecce, cerchi, rettangoli e triangoli.", [
            "Tieni premuto lo strumento forme e scegli la figura desiderata.",
            "Appoggia Pencil nel punto iniziale e trascina al secondo punto: per la freccia parti dalla coda e termina sulla punta.",
            "Rilascia per inserire la figura. Selezionala con Oggetti per modificarla o usa Annulla per rimuoverla." ], tools: [.line, .arrow, .ellipse, .rectangle, .triangle]),
        .init("held-shapes", .writing, "Riconosci una forma trattenuta", "scribble.variable", "Raddrizza una linea o regolarizza una figura.", [
            "Nel workspace attiva il riconoscimento delle forme trattenute.",
            "Con penna o evidenziatore disegna una retta, un cerchio o un rettangolo e mantieni ferma la punta alla fine per un istante.",
            "Attendi l’anteprima corretta e rilascia per confermare. Se la figura è troppo irregolare rimane il tratto originale." ]),
        .init("ruler", .writing, "Righello e aggancio del tratto", "ruler", "Guida orientabile per disegnare rette.", [
            "Attiva Righello dalla toolbar. Spostalo e ruotalo con le dita; usa i controlli disponibili per la dimensione.",
            "Inizia il tratto vicino al bordo con la penna e scorri lungo la guida: l’aggancio mantiene la linea sul bordo.",
            "Disattiva Righello per tornare alla scrittura libera. Usa Annulla se desideri rifare una linea." ], tools: [.ruler]),
        .init("workspace", .writing, "Workspace e toolbar personale", "slider.horizontal.3", "Profili per scrittura, matematica, lettura e disegno.", [
            "Apri Workspace dalle opzioni dell’editor e scegli il profilo dell’attività.",
            "Organizza strumenti preferiti, posizione della toolbar, palette e gesti senza cambiare gli altri profili.",
            "Personalizza anche gli strumenti di Solo foglio: fino a cinque, incluso il lazo. Le preferenze vengono salvate nel quaderno." ]),
        .init("focus", .writing, "Solo foglio e mini toolbar", "arrow.up.left.and.arrow.down.right", "Libera lo schermo conservando gli strumenti essenziali.", [
            "Tocca Solo foglio per nascondere le barre principali e continuare con lo strumento attivo.",
            "Tocca il piccolo overlay per espandere i preferiti. Il punto rosso segnala una registrazione anche in questa modalità.",
            "Usa il comando per tornare alla toolbar completa. Cambia i preferiti della mini toolbar nel workspace." ]),
        .init("zoom", .pages, "Zoom e navigazione", "arrow.up.left.and.arrow.down.right", "Pagina intera, larghezza schermo e scorrimento.", [
            "Pizzica con due dita per ingrandire e trascina con le dita per muoverti; Pencil resta dedicata alla scrittura.",
            "Il doppio tocco alterna pagina intera e zoom alla larghezza disponibile, riducendo i margini laterali.",
            "Dal menu Navigazione scegli pagina singola, verticale continuo o sfoglio orizzontale. Lo zoom si adatta alla rotazione." ]),
        .init("scrubber", .pages, "Cambia pagina dalla barra minima", "slider.horizontal.below.rectangle", "Scorri l’indicatore o vai direttamente a un numero.", [
            "Trascina la piccola barra inferiore: il numero della pagina si ingrandisce durante il gesto.",
            "Rilascia per aprire la pagina scelta. Tocca il contatore per digitare un numero e premi Vai.",
            "Per la vista d’insieme apri la griglia pagine. Il pulsante + aggiunge una pagina; il menu contiene le altre azioni." ]),
        .init("paper", .pages, "Carta e modelli per pagina", "square.grid.3x3", "Righe, quadretti, puntini, colori e formati.", [
            "Apri le opzioni Carta o Modello della pagina corrente.",
            "Scegli formato, sfondo, righe, griglia o puntini. Le impostazioni riguardano la pagina selezionata; puoi scegliere il modello per le successive.",
            "Per usare un PDF come modello scegli la relativa azione dopo l’importazione. Scrittura e oggetti rimangono sopra lo sfondo." ]),
        .init("page-trash", .pages, "Elimina e ripristina le pagine", "trash", "Selezione multipla e cestino dedicato.", [
            "Apri la griglia pagine, attiva la selezione e scegli una o più pagine.",
            "Premi Elimina per spostarle nel cestino pagine. Il menu della pagina corrente offre anche l’eliminazione singola.",
            "Apri Pagine eliminate e scegli Ripristina. La rimozione definitiva è separata; il cestino in libreria riguarda interi quaderni." ]),
        .init("sections", .pages, "Sezioni, titoli e segnalibri", "bookmark", "Organizza un quaderno lungo.", [
            "Dalla gestione pagine assegna un titolo e un segnalibro ai punti importanti.",
            "Apri Sezioni per creare raggruppamenti e assegnare le pagine selezionate.",
            "Usa l’elenco per navigare. Alla riapertura il quaderno riprende la pagina ricordata." ]),
        .init("photo", .pages, "Foto, ritaglio e raddrizzamento", "camera", "Correggi la prospettiva senza modificare l’originale.", [
            "Usa Inserisci immagine per scegliere da Foto oppure Scatta foto; al primo utilizzo consenti l’accesso richiesto da iPadOS.",
            "Nel pannello foto scegli Rettangolo per ritagliare o Raddrizza per rilevare i bordi: trascina i quattro angoli aiutandoti con la lente. Puoi ruotare di 90 gradi e attivare Migliora.",
            "Conferma e seleziona l’immagine con Oggetti per spostarla. Raddrizza nella barra o nel menu riapre le correzioni; Annulla recupera lo stato precedente. Anche Foto e chiedi usa la foto corretta." ]),
        .init("scanner", .pages, "Scanner e trascinamento", "doc.viewfinder", "Acquisisci documenti e materiale da altre app.", [
            "Apri Scansiona documento dal menu di inserimento e inquadra il foglio.",
            "Correggi i bordi e conferma. Scanner e fotocamera richiedono un dispositivo fisico e il relativo permesso.",
            "Con un’altra app affiancata trascina contenuti compatibili nel quaderno; verifica l’inserimento prima di chiudere la fonte." ]),
        .init("pdf-import", .pages, "Importa PDF come quaderno", "doc.richtext", "Annota le pagine del PDF originale.", [
            "Dalla libreria scegli Importa e seleziona un PDF in File; per aggiungere pagine al quaderno aperto usa l’importazione dell’editor.",
            "Attendi il completamento: file grandi o in cloud devono essere scaricati e copiati nello spazio locale.",
            "Annota con Pencil sopra le pagine. L’originale viene conservato. Il limite di importazione locale è distinto da quello del backup account." ]),
        .init("pdf-study", .pages, "PDF affiancato e ricerca di concetti", "rectangle.split.2x1", "Consulta fonti senza importarle nel quaderno.", [
            "Apri la vista PDF affiancata e scegli un documento da File.",
            "Usa la selezione del testo, l’indice e i collegamenti disponibili nel PDF. Puoi copiare il testo negli appunti.",
            "Attiva la ricerca concetti per cerchiare o sottolineare con Pencil una parola, poi scegli la ricerca. La modalità non modifica il PDF esterno." ]),
        .init("export", .pages, "Esporta PDF e backup nativo", "square.and.arrow.up", "Condivisione e recupero in formati distinti.", [
            "Apri Condividi o Esporta dal quaderno.",
            "Scegli PDF per sfondi, testo, immagini e inchiostro vettoriale. Il backup nativo conserva anche i dati modificabili.",
            "Salva in File e verifica la copia. Importare un backup manuale crea una nuova identità; la sincronizzazione conserva quella originale." ]),
        .init("record", .audio, "Registra una lezione lunga", "mic", "Segmenti, pause e indicatore sempre visibile.", [
            "Apri Audio e avvia la registrazione concedendo il permesso microfono. Il punto rosso rimane visibile anche in Solo foglio.",
            "Scrivi durante la lezione; usa Pausa e Riprendi. Nella build firmata il modo audio background permette di proseguire in standby, salvo interruzioni del sistema.",
            "Premi Stop e verifica la sessione. Playground e simulatore non sostituiscono prove fisiche di più ore, standby e interruzioni." ]),
        .init("audio-link", .audio, "Collega appunti e audio", "waveform.path", "Torna al momento della lezione dal tratto scritto.", [
            "Avvia la registrazione e prendi appunti: il quaderno conserva i riferimenti temporali disponibili.",
            "Scegli Collegamento audio e tocca un tratto associato per raggiungere quel momento.",
            "Dai controlli di ascolto usa −15 s e +15 s per riascoltare il contesto. Le pause non sono tempo di parlato." ], tools: [.audioLink]),
        .init("audio-import", .audio, "Importa registrazioni da iPhone", "waveform.badge.plus", "Trascrivi audio registrato su altri dispositivi.", [
            "Esporta da Memo Vocali o dall’app usata su iPhone e salva l’audio in File.",
            "Nel pannello Audio scegli Importa registrazione e seleziona un formato supportato.",
            "Attendi l’importazione, controlla durata e riproduzione, poi avvia la trascrizione. L’audio viene copiato nel quaderno." ]),
        .init("transcript", .audio, "Trascrivi e correggi il testo", "text.bubble", "Finestre audio, risultati parziali e titoli.", [
            "Dal pannello Audio seleziona una sessione e avvia Trascrivi. Gli audio lunghi sono elaborati a finestre e i risultati completati vengono salvati.",
            "Apri la trascrizione salvata; usa Rinomina e Correggi per titolo e testo, senza avviare l’esportazione.",
            "Scegli Esporta testo per un file con riferimenti temporali. Se il riconoscimento non è disponibile verifica permessi, lingua e stato nell’app." ]),
        .init("audio-storage", .audio, "Esporta, comprimi e organizza audio", "archivebox", "Riduci lo spazio delle registrazioni concluse.", [
            "Nel pannello Audio rinomina le sessioni, ascoltale ed esporta audio e trascrizioni in File.",
            "Da Spazio e archiviazione scegli Comprimi registrazioni per convertire PCM conclusi in AAC, quando non sono in uso.",
            "La conversione verifica durata e tempi prima di rimuovere il PCM. Elimina le sessioni inutili dal menu dopo aver conservato gli export." ]),
        .init("search", .study, "Ricerca e OCR", "magnifyingglass", "Trova testo e rendi ricercabile la grafia.", [
            "Usa Cerca nel quaderno oppure la ricerca del contenuto dalla libreria.",
            "Testo digitale e PDF leggibili possono essere indicizzati. Usa OCR per aggiungere al contenuto ricercabile la grafia o le immagini.",
            "Tocca un risultato per la pagina e il riferimento. Dopo una modifica attendi l’aggiornamento dell’indice o ripeti il riconoscimento dove necessario." ]),
        .init("lens", .study, "Lente AI: seleziona, chiedi, conserva", "sparkle.magnifyingglass", "Risposta nel popup senza creare note automaticamente.", [
            "Scegli la Lente e seleziona area o testo. Dopo la selezione ritorna alla modalità precedente per evitare richieste involontarie.",
            "Scegli spiegazione, sintesi o ricerca disponibile. La risposta appare nel popup; i servizi remoti richiedono una Connessione AI attiva.",
            "Decidi se inserire la risposta nel foglio, salvarla come nota o chiudere senza conservarla. Controlla le fonti web." ], tools: [.lens]),
        .init("ai-connection", .study, "Collega il servizio AI", "network", "Account gestito o motore configurato.", [
            "Apri Connessione AI nel pannello studio e scegli un motore disponibile.",
            "Per il servizio gestito accedi all’account NeuralNotes: il backend deve essere pubblicato e configurato. Le chiavi dei provider restano sul server.",
            "Prova una richiesta breve e controlla errori, crediti e fonti. Senza servizio attivo restano gli strumenti locali, senza simulare risposte generative." ]),
        .init("study", .study, "Sintesi, glossario e mappe", "sparkles", "Ripassa dalle fonti del quaderno.", [
            "Apri Studio e scegli le pagine o le fonti da usare.",
            "Genera una sintesi, estrai i termini del glossario o consulta le mappe disponibili.",
            "Apri i riferimenti per tornare alle fonti. Le funzioni locali usano anche estrazione del testo; la generazione richiede il motore AI attivo." ]),
        .init("flashcards", .study, "Flashcard, quiz e ripasso", "rectangle.on.rectangle.angled", "Domande, risposte e pianificazione.", [
            "Dal pannello Studio crea o genera carte dalle fonti e controlla domanda e risposta.",
            "Avvia il ripasso, rispondi prima di mostrare la soluzione e valuta la difficoltà.",
            "Consulta scadenze e statistiche oppure usa quiz ed esercizi. I riferimenti alle pagine aiutano a correggere gli errori." ]),
        .init("links", .study, "Collegamenti fra pagine e web", "link", "Mantieni i riferimenti alle fonti.", [
            "Apri i collegamenti della pagina e crea un riferimento a una pagina o a un indirizzo web.",
            "Scegli un titolo che descriva il contenuto e verifica la destinazione prima di salvare.",
            "Tocca il collegamento per tornare alla fonte. Controlla anche i link dei risultati AI come qualsiasi altra fonte esterna." ]),
        .init("account", .protection, "Account, accesso email e privacy", "person.crop.circle", "Codice di accesso, profilo, dati ed eliminazione.", [
            "Dalla barra della libreria apri Account e servizi → Account NeuralNotes. Nella stessa scheda trovi centro sincronizzazione, iCloud e motore AI. Serve un backend NeuralNotes HTTPS configurato con servizio email attivo.",
            "Inserisci l’email, richiedi il codice e confermalo. La sessione è nel portachiavi; dal profilo gestisci nome, crediti e uscita.",
            "Esporta i dati o richiedi l’eliminazione con nuova verifica. Uscire non elimina i quaderni locali: su dispositivi condivisi gestiscili separatamente." ]),
        .init("account-sync", .protection, "Sincronizza con l’account NeuralNotes", "arrow.triangle.2.circlepath.icloud", "Invio, ricezione e conflitti fra dispositivi.", [
            "Accedi allo stesso account sui dispositivi e apri Account e servizi → Centro sincronizzazione. Chiudi i quaderni e scegli Sincronizza adesso per collegarli a questo account.",
            "Attiva il backup alla chiusura e, se vuoi, Solo Wi-Fi: sui quaderni già collegati prepara una copia e la mantiene in coda fino a una rete adatta. Il limite è 100 MB per quaderno; cartelle e cestino restano locali.",
            "I badge mostrano cloud, coda o conflitto. Da Versioni precedenti puoi scaricare una revisione come quaderno indipendente. Risolvi i conflitti conservando entrambe le copie o scegliendo una versione: prima della sostituzione locale viene conservato un backup." ]),
        .init("icloud", .protection, "iCloud privato", "icloud", "Sincronizzazione separata dall’account NeuralNotes.", [
            "Serve una build firmata configurata con CloudKit e un account iCloud attivo. Nel Playground o senza abilitazione la funzione può non essere disponibile.",
            "Apri Cloud e sincronizzazione e avvia iCloud privato per i quaderni chiusi.",
            "Risolvi i conflitti conservando entrambe le copie o scegliendo una versione. La cancellazione locale non cancella la copia iCloud." ]),
        .init("backup", .protection, "Backup automatici e recupero", "externaldrive.badge.checkmark", "Versioni locali e copie esterne.", [
            "Apri Spazio e archiviazione per vedere i backup e configurare una cartella esterna per le copie automatiche.",
            "Conserva un export nativo in File prima di aggiornare o spostare il Playground. Copie diverse dell’app possono usare librerie locali separate.",
            "Se mancano quaderni apri Recupero quaderni o importa un backup. Non eliminare i dati dell’app per risolvere un errore di compilazione." ]),
        .init("status", .protection, "Stato del salvataggio e spazio", "checkmark.circle", "Dettagli a richiesta e conferme discrete.", [
            "Tocca l’icona di stato in basso per i dettagli e il comando Salva adesso.",
            "Le conferme appaiono pochi istanti. In caso di errore controlla spazio libero e permessi prima di chiudere.",
            "Da Spazio e archiviazione controlla audio e backup. Due copie recenti vengono protette anche se superano il budget calcolato." ]),
        .init("diagnostics", .protection, "Verifica sul dispositivo", "checkmark.seal", "Controlli isolati e collaudo fisico.", [
            "Dalla libreria apri Verifica sul dispositivo ed esegui i controlli integrati.",
            "I test usano documenti di prova e mostrano i risultati per area. Non sostituiscono il collaudo del tuo materiale reale.",
            "Prima della delivery verifica audio lungo, standby, fotocamera, PDF grandi e un aggiornamento conservando il backup dei quaderni." ]),
        .init("laser", .writing, "Puntatore laser", "scope", "Indica un punto senza aggiungere inchiostro permanente.", [
            "Dal menu dell’editor attiva Puntatore laser per spiegare o mostrare una parte del foglio.",
            "Muovi la punta sul contenuto da indicare. Il segno temporaneo aiuta a seguire la spiegazione e non diventa un appunto.",
            "Disattiva il puntatore per riprendere la scrittura. Verifica lo strumento attivo prima di aggiungere nuovi tratti." ]),
        .init("study-tape", .study, "Nastro per il ripasso", "rectangle.fill", "Nascondi una risposta e prova a ricordarla.", [
            "Dal menu di inserimento scegli Nastro per il ripasso per aggiungere una copertura sul foglio.",
            "Posiziona e ridimensiona il nastro sopra il testo da nascondere usando lo strumento Oggetti.",
            "Usa il controllo del nastro per mostrare o nascondere il contenuto mentre ripassi. Puoi spostarlo o eliminarlo dal menu della selezione." ]),
        .init("diagrams", .writing, "Diagrammi con i punti blu", "point.topleft.down.curvedto.point.bottomright.up", "Blocchi collegati, con testo modificabile.", [
            "Disegna una forma e selezionala con Oggetti: compaiono quattro punti blu. Tocca un punto per creare un blocco uguale collegato, a 48 punti di distanza se c’è spazio.",
            "Trascina un punto su un altro oggetto per collegarlo. Nel vuoto nasce un blocco; trattieni circa mezzo secondo per lasciare invece un estremo libero. Gli estremi seguono spostamenti, dimensioni e rotazione.",
            "Fai doppio tocco dentro un blocco o su un connettore per scrivere. Usa Aa per elenchi e rientri; puoi ridurre il carattere automaticamente. Dal menu del connettore scegli Dritto, Curvo, A gomito e lo stile.",
            "Copia più blocchi per includere anche i collegamenti interni. Le mappe create da uno schema AI si modificano con gli stessi strumenti. Annulla torna indietro di un’operazione." ], tools: [.objects]),
        .init("marker-words", .writing, "Evidenziatore sottile e parole PDF", "highlighter", "Larghezza reale e parole agganciate, senza coprire il testo.", [
            "Tieni premuto Evidenziatore: Larghezza reale scende fino a 1 punto. Questo valore è lo spessore effettivo sulla pagina, indipendente dallo zoom.",
            "Attiva Aggancia alle parole del PDF. Scorri sulle parole o appena sotto, come con la Lente: l’evidenziazione si adatta alle parole selezionate. Per un PDF scansionato senza testo digitale resta disponibile il tratto libero.",
            "Il colore viene composto con il foglio e il PDF senza schiarire le lettere nere; l’inchiostro della penna resta sopra. Lo stesso criterio si usa nelle anteprime e nell’esportazione. Un solo annulla rimuove l’intera evidenziazione." ], tools: [.marker]),
        .init("pdf-highlight", .pages, "Testo ed evidenziazioni del PDF", "highlighter", "Seleziona testo digitale e conserva i riferimenti.", [
            "Apri lo studio PDF e un documento con testo selezionabile. I PDF composti soltanto da scansioni possono richiedere OCR.",
            "Seleziona le righe da copiare o evidenziare con i controlli PDF disponibili; usa l’indice per raggiungere una sezione.",
            "Riporta le parti utili negli appunti e controlla il risultato. Per un tratto libero sopra la pagina usa invece l’evidenziatore dell’editor." ])
    ]
}

