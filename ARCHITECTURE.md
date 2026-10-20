# Architettura NeuralNotes 0.9

## Estensione 0.9

`DocumentWorkspace` rimane il writer serializzato. L’indice persistente e la cache OCR risiedono in Caches, includono la revisione della pagina e sono ricostruibili: non sostituiscono i documenti. I backup a versioni vengono completati prima della rotazione; non includono registrazioni ancora in scrittura. La manutenzione dell’editor attende una pausa per l’OCR e non cambia la revisione degli appunti per salvare dati derivati.

Il canvas PencilKit unico resta montato. `VisiblePaperDetail` ridisegna PDF e testo solo nel viewport con budget di pixel, mentre `DocumentRenderCache` condivide sorgenti PDF immutabili e immagini con costo limitato. Le anteprime continue restano limitate alle pagine vicine; per le pagine piccole pulite esiste un caricamento nativo sincrono al primo contatto. Il percorso asincrono protetto resta necessario per i casi grandi o con salvataggio in corso.

Testo RTF e rotazione sono campi opzionali del formato esistente. Scanner e drop normalizzano le immagini; lo scanner salva una pagina alla volta. Le annotazioni PDF sono dati del quaderno, senza riscrittura dell’allegato originale. Il pannello di studio usa un PDFDocument separato, e il renderer/export applica i markup nelle coordinate della pagina. La conversazione AI è nel catalogo, con rimappatura delle fonti alla duplicazione e all’importazione di pagine native.

La Lente usa le fonti della selezione e un provider intercambiabile. Il client HTTPS riceve eventi NDJSON e verifica il risultato finale; il backend inoltra lo streaming Responses ed estrae il testo provvisorio. La risposta viene persistita soltanto dopo la validazione dei riferimenti. Token del backend nel portachiavi, chiave del provider sul server; il provider offline rimane estrattivo.

CloudKit usa snapshot `.nnbackup` in parti immutabili e un record condizionale della revisione. La politica confronta locale, remoto e checkpoint; modifiche concorrenti producono un conflitto esplicito. Una lease impedisce di sostituire un quaderno aperto e l’impronta locale viene ricontrollata al commit. Backup e recupero `.cloudPrevious` proteggono la sostituzione. L’app firmata e il contenitore devono ancora essere attivati: le prove del modello di conflitto e della sostituzione sul filesystem non sono una prova del servizio CloudKit live.

I documenti di stato e i limiti della build corrente sono in [VALIDATION.md](docs/VALIDATION.md) e [STUDY_WORKSPACE_0_9.md](docs/STUDY_WORKSPACE_0_9.md). Le sezioni seguenti conservano l’architettura e i numeri storici delle consegne precedenti.

## Architettura storica 0.5

## Estensione 0.5

Il repository discrimina PDF per estensione/UTType prima del decoder nativo. Prepara package e pagine PDF separatamente dal record SwiftData, registra solo dopo import completo e rimuove il solo package appena creato in caso di errore. I PDF importati rimangono sfondi originali annotabili.

PageTemplate e PaperAppearance sono dati Codable nel catalogo/pagina; campi opzionali, schema SwiftData invariato. Creazione quaderno salva il modello; la prima pagina è generata all’apertura. Addizione e avanzamento rispettano il modello, oppure ereditano la carta attuale quando il quaderno precedente non ha un default. Il cambio formato scala inchiostro, oggetti e testo e registra una sola azione nella cronologia. Preferenza per le nuove pagine separata dall’undo del contenuto corrente. La carta PDF originale non è sostituita dal modello.

FocusControl conserva posizione nella scena, nasconde tutte le barre e non cambia lo strumento. CanvasHost mostra una soglia di avanzamento solo al fit di pagina; la navigazione avviene al rilascio e passa dal lock e dall’undo già esistenti. ScratchGesture è un classificatore geometrico conservativo opt-in: intercetta zig-zag ripetuti e rimuove tratti/caselle intersecati, registrando prima e dopo. Non interpreta parole o contenuti delle immagini.

AudioController possiede il task di trascrizione, quindi la chiusura di AudioPanel non lo cancella. ASR on-device conservato, finestre da 45 s, un retry e checkpoint dopo ogni finestra nel catalogo. UI di avanzamento e pausa; ricreando il controller si saltano i chunk già completati. Background/chiusura richiedono cancellazione cooperativa: nessuna garanzia di elaborazione in background. Errori conservano i blocchi già salvati. La fixture di test può iniettare un riconoscitore di finestra; soltanto nei test viene usato un risultato controllato.

TranscriptText raggruppa le parole per minuto e produce export testuali con hh:mm:ss. Correzioni manuali per minuto persistite separatamente: al ricalcolo dai chunk vengono riapplicate. Il titolo è condiviso da registrazione e trascrizione; cambiare il testo non modifica l’audio. Il bucket temporale approssimato può anticipare di meno di un minuto la prima parola della sezione; non è un allineamento parola per parola dopo la correzione. I chunk aumentano la dimensione del catalogo: prestazioni reali su lezioni lunghe da misurare.

89 XCTest forniti (51 core, 27 integrazione, 4 UI), 19 controlli incorporati. Nessuna build Apple della 0.5 eseguita qui. Le parti seguenti descrivono le basi mantenute.

## Moduli e concorrenza

Modular monolith per feature: NeuralNotesCore contiene dominio Codable e storage Foundation; il target app contiene SwiftUI/UIKit e integrazioni Apple. SwiftData V1 mantiene identità, metadati, cartelle e tombstone; i contenuti sono file separati. PDF/audio non diventano attributi giganti del database. Nessuna dipendenza app esterna.

AppController compone un repository MainActor condiviso; ogni LibraryScene ha il proprio LibraryViewModel per filtri e navigazione. WindowGroup identifica la scena library. Il repository mantiene un DocumentWorkspace actor per quaderno; EditorLeases consente un solo editor scrivibile per documento nel processo. Le lease contengono riferimenti deboli, non mantengono editor chiusi in vita. Una revisione osservabile aggiorna le altre librerie dopo i commit. La chiusura dell’editor aggiorna soltanto updatedAt, senza sovrascrivere una rinomina fatta in un’altra finestra. Spostare nel cestino un quaderno con writer attivo viene rifiutato.

NotebookDesk monta il canvas della sola scheda attiva, conserva fino a sei editor e sospende l’audio al cambio. SceneStorage codifica ID delle schede e selezione; UserDefaults conserva l’ultima pagina per documento. Il ripristino filtra ID eliminati/duplicati. La persistenza della scena dipende dal sistema ospitante; non è sync. Canvas e disegni inattivi rimangono in memoria e richiedono profilazione.

## Editor, immagini e selezione

PencilKit conserva i vettori originali, gestisce penna/evidenziatore/gomma/lazo e zoom. PaperInk risolve colori fisici e aspetto chiaro del foglio indipendentemente dal tema dell’app. PageSurfaceView disegna PDF, carta, immagini, forme e testo; non invalida la superficie per ogni punto del tratto.

CanvasInteraction opera nelle coordinate non zoomate del foglio. Tap, selezione multipla e marquee raccolgono oggetti e indici dei tratti. I tratti vengono inclusi interi per intersezione del renderBounds. Spostare un gruppo applica una trasformazione ai tratti selezionati e trasla gli oggetti. Il disegno iniziale viene catturato una volta all’inizio del drag. Handle per dimensioni degli oggetti; le immagini mantengono il rapporto. Il lazo nativo rimane separato e limitato all’inchiostro.

CameraCapture usa UIImagePickerController; Foto usa PhotosPicker. Input limitato a 100 MB, anteprima ridotta a 2400 px e normalizzazione all’import. NormalizedCrop memorizza un rettangolo 0…1; ImageElement conserva crop e rotazione, senza riscrivere l’asset al ritaglio. La copia conservata è quella normalizzata, non un archivio RAW/EXIF della fotocamera. ShapeElement contiene geometria, RGB e spessore per cerchio/ellisse, rettangolo, linea e freccia. Nuovi campi opzionali: decodifica dei precedenti JSON V1 conservata.

EditorContentState confronta contenuto senza nomi dei file di salvataggio/revisione. EditHistory mantiene coppie prima/dopo per oggetti/inchiostro e ordine/selezione per pagine. Budget 60 comandi/48 MB stimati; nessuna cronologia su disco. Undo/redo effettua flush, ripristina con la revisione corrente e conferma lo spostamento del comando solo dopo il salvataggio. L’ordine delle pagine usa compare-and-swap contro il manifest atteso. I pulsanti della toolbar governano la cronologia comune; undo nativo dentro i controlli UIKit e gesto a tre dita non sono unificati con essa.

Clipboard interno al processo: testo, immagini, forme e vettori; copia cross-documento degli asset, nuove identità e traslazione. Limite 32 MB per l’inchiostro copiato. I tratti incollati non ricevono le vecchie associazioni audio. Layer attuali: immagini, forme, testi, poi inchiostro; non è ancora un sistema di z-order arbitrario.

## Commit e recupero

Il package .nnbook contiene manifest, page JSON, drawings, images, attachments, audio, catalog e artifacts. UUID distinti per notebook/document/page. Tutti i percorsi sono relativi, confinati alla root; traversal e symlink sotto il pacchetto sono rifiutati. PackageFiles visita i figli da una root con percorsi relativi espliciti, evitando differenze Darwin tra URL assoluti. Backup/merge condividono la scansione; vengono ignorati soltanto i sidecar Finder/resource fork previsti.

Salvataggio: nuovo drawing atomico, header pagina atomico, conservazione del drawing precedente. Revisioni obsolete rifiutate. Manifest: conservazione atomica del precedente valido prima del nuovo commit. Autosave 700 ms; flush su navigazione/chiusura/export/background. L’ultimo gesto ancora in memoria può andare perso se il processo termina prima del commit. DB e filesystem non costituiscono un’unica transazione; gli orfani sono conservati.

Recupero UI: scansione dei package senza record, validazione, registrazione con identità originale e nessuna cancellazione del package. Ripristino dell’indice precedente solo se formato e identità corrispondono; copia dell’indice danneggiato in recovery. Un formato nuovo non viene retrocesso a V1. Recupero della revisione PKDrawing precedente all’apertura con avviso e richiesta di salvataggio.

WorkspaceMaintenance calcola spazio e raggiungibilità dai cataloghi e da TUTTI gli header pagina, compresi quelli rimossi. Protegge drawing corrente/precedente, PDF, immagini, cover e audio. Header illeggibili o mancanti attivi bloccano la pulizia. Pulizia esplicita soltanto a quaderno chiuso dalla UI; niente pulizia durante registrazioni. Purge delle pagine rimosse separato e confermato, mai delle pagine attive. Prima del purge viene fissato un indice precedente che non dipende dalle pagine eliminate. Il cestino globale dei quaderni non viene svuotato fisicamente.

NativeArchive usa container NNBOOK01, CRC32, blocchi da 256 KB, limite 16 GB/50.000 file. NativePackageInspector verifica geometrie, formati, riferimenti e media prima della registrazione; non decodifica ogni payload Apple. NativeImport e PackageCloner creano nuove identità; DocumentMerge prepara i file prima di aggiornare l’ordine e non sostituisce le pagine esistenti. Un’interruzione può lasciare file non referenziati recuperabili. Il backup non è uno schema di migrazione automatica tra versioni future.

## PDF

Import: originali immutabili con hash, crop box e rotazione normalizzati in coordinate pagina, annotazioni separate. Limiti PDF 100 MB/1000 pagine. Export tramite CGContext PDF su file, una pagina in autoreleasepool e Task.yield tra le pagine, nessun contesto UIKit lasciato attivo durante await. MediaBox specifico per ogni pagina, verifica finale del numero di pagine, cancellazione e rimozione del PDF incompleto in caso di errore.

VectorInkRenderer interpola i percorsi PencilKit, conserva trasformazioni e maschere, ricostruisce geometria con ellissi e quadrilateri e gestisce l’evidenziatore con trasparenza/moltiplicazione. Sono primitive PDF vettoriali; il brush proprietario PencilKit è approssimato. L’export alternativo mantiene l’aspetto PencilKit tramite immagine per pagina; il nativo conserva sempre PKDrawing originale. Foto raster intenzionali, testo e PDF sorgente rimangono PDF. Rendering di una pagina molto densa può ancora occupare il MainActor: prestazioni da misurare.

Riferimenti: [MediaBox come CFData di CGRect](https://developer.apple.com/documentation/coregraphics/kcgpdfcontextmediabox), [CGContext PDF](https://developer.apple.com/documentation/coregraphics/cgcontext/init(consumer:mediabox:_:)), [PencilKit](https://developer.apple.com/documentation/pencilkit).

## Audio, riconoscimento e studio

CAF PCM mono 44,1 kHz/16 bit, segmento nuovo a ogni ripresa; timestamp host monotono e tempo campioni nel modello. Indice aggiornato ogni due secondi e su pausa/fine. Interruzioni audio e chiusura del quaderno sospendono il microfono senza riavvio implicito. Dalla 0.5.1 scenePhase in background salva i metadati senza fermare il recorder; UIBackgroundModes/audio è presente nei due plist. Al ritorno viene verificato isRecording; la disponibilità nel runner richiede prova hardware. Speech viene sospeso in background. Recupero delle durate CAF leggibili al lancio. Firma dei tratti basata su creationDate e occorrenza: gesti complessi/copie PencilKit possono creare ambiguità, da verificare. Nessuna promessa di recuperare byte audio mai scritti.

Vision OCR da snapshot pagina/area. Apple Speech esclusivamente on-device con finestre da 45 s, timestamp ricomposti, timeout/cancellazione e permesso verificato. FileDocumentIndexingService produce chunk con pagina/revisione o sessione/minuto. Ricerca lessicale predefinita; AppleEmbeddingService usa veri modelli italiani Natural Language se disponibili, altrimenti mostra un errore. Nessun embedding inventato.

ExtractiveStudyProvider seleziona frasi delle fonti per sintesi/schema/quiz; non è generazione LLM. Artefatti e flashcard persistono con fonti e revisioni. RemoteAIProvider richiede HTTPS, consenso e token in Keychain; valida le citazioni rispetto alle fonti inviate. Backend Node con adapter Responses, HMAC a scadenza, limiti e timeout; non distribuito, senza prova live o quote distribuite. LocalAIProvider generativo e classificazione/visione automatica rimangono da implementare.

## Packaging, qualità e Cloud

Generatore Xcode deterministico con target app/core/test e schema condiviso. Playground dagli stessi sorgenti, Core separato, risorse Bundle.module; capability microfono/camera/Speech e Info.plist aggiuntivo per scene multiple. Nuova finestra controlla supportsMultipleScenes del processo. La disponibilità nel runner Playground va verificata.

140 metodi XCTest, 26 controlli temporanei incorporati e prova sintetica 50 pagine/CAF60s/PDF/backup. Su Windows si eseguono controlli strutturali, grammatica e packaging; la CI privata esegue [verify_macos.sh](tools/verify_macos.sh) su macOS con SDK Apple, inclusi unit e UI test del simulatore. [Esiti effettivi e limiti fisici](docs/VALIDATION.md).

CloudKit disabilitato come previsto dal piano iniziale. Architettura futura: outbox transazionale, asset separati, retry/backoff, tombstone, revisioni alternative per conflitti e un solo writer di sync. Collaborazione separata. Firma, account e distribuzione App Store non configurati.

## Correzioni editor 0.5.1

CanvasInteraction riconosce il doppio tocco delle dita per adattare la pagina. ScratchGesture accumula le inversioni anche con campioni ravvicinati; InkScratchEraser sottrae l’area dalla maschera pre-transform del PKStroke, conservando percorso e creationDate. TextScratchEraser misura le parole con TextKit. Il renderer PDF rispetta il fill rule della maschera. AudioPanel usa righe borderless separate e un solo enum di presentazione per editor/esportazione.

## Navigazione, testo e riconoscimento 0.6

Dalla 0.6.1 DocumentPageViewport contiene sempre PencilCanvas a espansione completa. Rimossi lo ScrollView esterno, la selezione automatica tramite geometrie, il limite di larghezza e lo stack di anteprime della 0.6. Il PKCanvasView mantiene pan/pinch e sfoglio nello stesso viewport. I gesti delle pagine sono quattro UISwipeGestureRecognizer con soli touch direct, attivi secondo asse e scala minima; il pan accetta dita/puntatore e il pinch solo dita, mai Pencil. Con fingerDrawing il pan/sfoglio richiede due dita. turnPage e advanceOrAddPage rifiutano la navigazione durante uso dello strumento o modifica di testo. Default single; il caso vertical mantiene il raw value continuous per leggere le preferenze 0.6. Il cambio pagina passa dal flush del writer. Preferenza UserDefaults per documentID, non inclusa nel backup.

Il commit del gesto PencilKit attende 80 ms dall’ultima consegna dopo didEndUsingTool e conserva lo stato precedente se non è ancora arrivato un disegno modificato. Navigazione e undo finalizzano i gesti pendenti. ScratchGesture accetta anche inversioni verticali e giri ripetuti. Non aggrega tratti separati né esegue riconoscimento semantico della grafia.

CanvasTextInput mette un vero UITextView sopra la casella selezionata, nasconde soltanto il testo duplicato nel renderer e mantiene la proiezione nel modello. Le modifiche vengono registrate nella cronologia ai checkpoint/chiusura; il sistema fornisce Scribble/UITextInput in base alle impostazioni. Non si presenta l’inchiostro libero come testo modificabile con i gesti di sistema.

AudioSession.readableTranscript recupera dai chunk solo se la proiezione è priva di testo; hasCompletedTranscript distingue un riconoscimento vuoto. TranscriptReader osserva il controller e mostra i minuti completi; i blocchi vuoti di un’analisi conclusa possono essere ritentati. La rinomina preserva il testo legacy quando il campo chunks è presente ma vuoto.

## Flusso continuo e voltata 0.7

ContinuousPageLayout costruisce un sistema di coordinate per il documento con distacco di 12 punti. ContinuousCanvasFlow usa esclusivamente il pan nativo del PKCanvasView, estendendo gli inset per i fogli precedenti/successivi. Lo spazio di disegno attivo e i file .drawing restano locali alla pagina; le anteprime adiacenti sono viste passive nel CanvasHost, non ulteriori scroll view. Insets e margini verticali sono indipendenti dalla pagina attiva per mantenere stabili i limiti con formati misti. Il rebase sottrae l’origine della nuova pagina dall’offset globale, mantenendo scala e posizione.

A scroll fermo la pagina più visibile viene selezionata attraverso il writer esistente. Durante il trascinamento viene richiesto un flush; prefetch e immagini sono limitati alle pagine vicine. A touch-down una pagina preparata può diventare attiva sincronicamente soltanto se l’editor è pulito, non salva, non sta scrivendo e l’header coincide con quello corrente. Altrimenti il contatto apre la pagina e non genera un tratto nel file sbagliato; l’UI segnala l’apertura. Il gap non cattura inchiostro. Nessun contenuto viene traslato nelle coordinate del documento su disco.

EditorPagePresenter permette a select di mantenere navigating durante caricamento e animazione. CanvasHost presenta l’orizzontale con due immagini del foglio e una transizione UIKit curl su un contenitore ruotato; le immagini contro-ruotano per restare dritte. La cancellazione di una task non abbrevia artificialmente l’animazione, che completa e rilascia l’overlay; gli errori di caricamento rimuovono l’overlay e vengono propagati. Riduci movimento usa cross-dissolve. Non è una simulazione interattiva della piega guidata dal dito.

## Zoom con doppio tocco 0.7.1

CanvasHost alterna lo zoom minimo e la larghezza esatta della pagina attiva, eliminando gli inset laterali nella seconda vista. Il ritorno a Pagina intera ripristina gli inset e il centraggio. Il flusso verticale usa la stessa regola laterale e mantiene coordinate locali dell’inchiostro. Due nuove regressioni di integrazione e test UI aggiornato, non eseguiti con SDK Apple. [Prova iPad](docs/FIXES_0_7_1.md).

## Workspace e input 0.8

Il catalogo v1 aggiunge campi opzionali editorWorkspaces e coverDesign; gli endpoint normalizzati opzionali delle forme mantengono compatibilità con le diagonali precedenti. Workspace e palette per attività sono validati e salvati con mutatori del catalogo che conservano sessioni/media. Il monitor touch osserva PencilKit senza impedire i recognizer nativi, mostra anteprime e corregge un solo tratto dopo il commit. La toolbar è un overlay sul canvas; la mini toolbar focus usa i primi tre preferiti. Recenti della libreria locali, stile copertina incluso nel backup. [Prove e limiti](docs/TESTING_0_8.md).

## Consolidamento 0.8.1

Flush inchiostro/testo prima delle configurazioni e svuotamento delle modifiche concorrenti; blocco cambio pagina/strumento durante il tratto. Catalogo precedente dentro recovery, ripristino esplicito con conservazione dei byte interrotti e protezione dei media. Clone/import aggiorna le identità del catalogo recuperabile. Classificatore geometrico riscritto in operazioni Double esplicite dopo errore reale di Playground. Workflow macOS e baseline Git. [Prove](docs/CONSOLIDATION_0_8_1.md).
