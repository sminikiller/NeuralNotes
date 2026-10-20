# Architettura NeuralNotes

## Confini della Fase 1

Modular monolith organizzato per feature. Un package locale `NeuralNotesCore` contiene dominio e formato su file; il target app integra SwiftData e SwiftUI. Nessuna dipendenza di rete o libreria esterna. Le directory feature non sono moduli binari separati: questa separazione potrà essere estratta quando misure di build e dimensioni lo giustificheranno.

Flusso delle dipendenze:

```text
NeuralNotesApp → AppController (composition root)
  → LibraryViewModel → LibraryRepository (protocollo del dominio)
                       ↑
          SwiftDataLibraryRepository → ModelContext
                                     → NativeDocumentStore
LibraryView / NotebookOverview → snapshot immutabili Notebook, LibraryFolder
```

Il ViewModel usa Observation e riceve il repository tramite initializer injection. Non passa oggetti SwiftData alla UI. Il repository e il ViewModel sono confinati al MainActor; le operazioni della Fase 1 riguardano solo metadati e manifest piccoli. Swift concurrency checking è impostato su `complete` in language mode Swift 5; l’assenza di warning deve essere controllata nel build Apple.

### Distribuzione dei sorgenti per il solo iPad

È aggiunto un secondo contenitore di build, `NeuralNotes.swiftpm`, per Swift Playground su iPad. `tools/package_ipad.py` copia gli stessi sorgenti in due target locali: `NeuralNotesCore` e l’eseguibile `App`. Nessuna sostituzione di SwiftData con storage temporaneo, nessun servizio remoto. L’unica differenza condizionale del sorgente riguarda il lookup dei colori: `Bundle.module` nella build SwiftPM e bundle principale nella build Xcode.

Il manifest `.iOSApplication` segue la struttura di un sample Apple ufficiale. Le impostazioni Info.plist del target Xcode non vengono importate nell’App Playground: il lifecycle è quello generato da Swift Playground e va verificato sul dispositivo. Per ora usare una sola esecuzione del progetto. Questa consegna rende possibile tentare una build sul solo iPad, ma non costituisce evidenza che sia già compilata. La suite XCTest/XCUITest rimane nel progetto Xcode, non viene presentata come eseguita nel Playground.

## SwiftData anziché Core Data

Scelta: **SwiftData, iPadOS 17 minimo**. Offre modelli tipizzati, integrazione con gli strumenti Apple e versionamento dichiarativo con poco codice d’infrastruttura. Non servono deployment precedenti, batch su milioni di oggetti o uno stack Core Data esistente, che avrebbero favorito Core Data. Si usano `VersionedSchema`, `SchemaMigrationPlan` e `ModelConfiguration` con URL esplicito e CloudKit disabilitato.

`LibrarySchemaV1` è una versione immutabile dopo il primo rilascio. Attualmente il migration plan contiene solo V1 e **nessuna migrazione storica è stata implementata o testata**, perché non esiste una release precedente. Ogni V2 richiederà una nuova schema class, uno stage e fixture reali di V1 con test di aggiornamento. Mai cancellare un database per risolvere un errore di migrazione.

Le foreign key `folderID`/`parentID` sono UUID opzionali e validate dal repository. Non sono relazioni gestite automaticamente da SwiftData: il repository controlla esistenza, impedisce cancellazioni di cartelle non vuote e crea sottocartelle solo sotto genitori esistenti. Non è esposta un’operazione di reparenting delle cartelle: non si possono creare cicli tramite la UI. Un quaderno ripristinato da una cartella rimossa ritorna alla radice. Vincoli unici UUID locali: andranno rivalutati prima di un’eventuale sincronizzazione automatica SwiftData/CloudKit.

## Persistenza e interruzioni

Il database conserva esclusivamente metadati. Il documento ha un’identità UUID distinta dal quaderno. Per ora un quaderno possiede un solo documento nativo, senza pagine. Il pacchetto `.nnbook` non è ancora registrato come tipo importabile/esportabile: la registrazione UTType appartiene alla Fase 3.

Creazione:

1. Validare nome, cartella e UUID.
2. Creare il pacchetto e le directory per tipo di contenuto.
3. Scrivere `manifest.json` con `Data.write(options: .atomic)`.
4. Inserire il record e chiamare esplicitamente `ModelContext.save()`.
5. Se il commit fallisce, rollback del contesto e rimozione del solo pacchetto appena creato. Se anche la pulizia fallisce, errore di recupero esplicito.

File system e SQLite **non formano una singola transazione atomica**. L’ordine impedisce che una creazione interrotta prima del commit lasci un record apparentemente valido senza contenuto. Un crash fra file e commit può lasciare un pacchetto orfano: l’integrity scan lo segnala senza rimuoverlo. Un crash prima del manifest può lasciare una directory incompleta, anch’essa conservata. Nessun recupero automatico con perdita di metadati.

Rinomina, spostamento, copertina e preferiti coinvolgono solo il database. L’UI mostra l’esito dopo il save; un errore causa rollback, senza fingere successo. L’autosave implicito SwiftData è disabilitato per evitare commit parziali delle modifiche; tutte le azioni confermate salvano subito. Le bozze nei form non vengono salvate prima di premere Salva.

L’eliminazione di un quaderno scrive un tombstone `deletedAt`, conserva il pacchetto e supporta ripristino dell’ultima eliminazione. I tombstone persistono dopo il riavvio; la UI del cestino e il purge non sono ancora presenti. La duplicazione attuale è limitata ai documenti vuoti; rifiuta manifest con pagine per evitare copie incomplete. Non è una duplicazione generalizzata di futuri PDF/media.

Per la Fase 2: writer actor per IO, snapshot immutabili `Data` di `PKDrawing`, numero di revisione monotono per pagina e coalescenza dei salvataggi. Scrivere prima lo snapshot vettoriale in una nuova revisione atomica, poi il manifest che la referenzia; il reader ignora revisioni non committate. Conservare l’ultima revisione valida per recupero. Flush atteso su chiusura pagina e passaggio in background con task di durata limitata, senza assumere che iOS conceda un callback di terminazione. I backup e la loro policy di quota dovranno precedere contenuti utente importanti.

## Modello dati attuale e destinazione

UUID per ogni identità. Date in UTC nel modello; UI formattata secondo il dispositivo. Le durate audio useranno la timeline della registrazione, mai la sola data di calendario. La seguente tabella distingue il codice già presente dallo schema **progettato**, che non è stato introdotto prematuramente nel database.

| Entità | Campi/relazioni essenziali | Stato |
|---|---|---|
| Notebook | id, documentID, title, folderID, cover, favorite, createdAt, updatedAt, deletedAt | Modello persistito V1 |
| Folder | id, parentID, title | Modello persistito V1 |
| Document | id, notebookID, schemaVersion, createdAt, pageIDs ordinati | Manifest nativo V1; nessuna pagina |
| DocumentMetadata | titolo/copertina, preferiti, cartella, date; futuro revision, source, tags | Attualmente campi di NotebookRecord; nessuna entità duplicata |
| Page | id, documentID, ordine nel manifest, dimensioni in punti, sfondo, sourcePDFPage, revision | Progettato, Fasi 2–3 |
| Drawing | id, pageID, revision, percorso `.drawing`, hash; indice tratti separato | Progettato, Fase 2; dati PKDrawing originali |
| TextElement | id, pageID, testo/attributi, rect e trasformazione in coordinate pagina | Progettato, Fase 3 |
| ImageElement | id, pageID, assetID, rect, trasformazione | Progettato, Fase 3 |
| Attachment | id, documentID, relativePath, UTType, byteCount, SHA256, sourceFilename | Progettato, Fase 3 |
| AudioSession | id, documentID, mediaPath, sampleRate, frameCount, stato, startedAt | Progettato, Fase 4 |
| AudioTimelineSegment | id, sessionID, mediaStartFrame, hostClockStart, durata frame, motivo pausa/interruzione | Progettato, Fase 4 |
| StrokeAnchor | id, drawingID, revision, strokeID/indice, audioSessionID, segmentID, audioFrameOffset | Progettato, Fase 4; necessario sin dalla prima registrazione |
| TranscriptSegment | id, sessionID, start/end audioFrameOffset, testo, lingua, confidence, engineVersion | Progettato, Fase 5 |
| AIArtifact | id, documentIDs, task, provider/modelVersion, revision sorgenti, citazioni, percorso contenuto | Progettato, Fase 6 |

Percorsi relativi confinati al pacchetto: i reader futuri devono rifiutare `..`, percorsi assoluti e riferimenti esterni. PDF, immagini e audio non saranno attributi blob di un singolo record SwiftData. Nessun hash, embedding o indice semantico finto è salvato oggi.

## Editor futuro: PencilKit + UIKit

La Fase 1 apre una scheda quaderno autentica, senza canvas simulato. La Fase 2 introdurrà un `PKCanvasView` tramite `UIViewRepresentable` con coordinator, stato strumenti separato dalla persistenza e undo manager del canvas. Si usa prima il tool picker PencilKit di sistema: penna, spessori/colori, evidenziatore, gomma e lazo. API da verificare nello specifico SDK Mac prima di implementare; nessun metodo presunto.

`drawingPolicy = .pencilOnly` sarà il default dove appropriato: touch dedicato a pan/zoom, con opzione esplicita per disegnare col dito e accessibilità. Render di un numero limitato di pagine attive, riutilizzo delle view e cache con limite. Il callback di disegno non deve scrivere su disco, chiamare AI o eseguire OCR. Conservare `.drawing` vettoriali; miniature raster solo come cache derivabile.

Coordinate canoniche di pagina in punti, indipendenti da orientamento e zoom. Sfondo e canvas condividono la stessa trasformazione. In Fase 3 il mapping PDF include crop/media box e rotazione del PDF, con test sugli angoli e sui round trip. Il PDF originale è un allegato immutabile, annotazioni in layer separati; l’export compone i layer solo su richiesta. Core Graphics per sfondi/export; Metal escluso finché una misura non ne dimostri la necessità.

Le schede di più documenti, la gestione memoria dei canvas e il pannello laterale AI richiederanno stato di workspace distinto dai dati del documento. L’app attuale usa una sola scena per evitare scritture concorrenti fra ModelContext e file writer non ancora coordinati. Split View riguarda la dimensione della singola scena e non richiede più finestre.

## Audio e sincronizzazione della scrittura

Non implementati. AVFoundation gestirà file segmentati, interruzioni AVAudioSession e recovery. Ogni ripresa genera un segmento con mapping host clock monotono → frame audio. Un tratto scritto durante una pausa non deve essere falsamente collegato al minuto successivo. Gli anchor saranno catturati al commit del tratto e registrati in un sidecar revisionato, distinguendo copia/cancellazione di tratti e modifiche successive. Stabilire e testare l’identità dei tratti con le API PencilKit effettivamente disponibili; non assumere UUID persistenti forniti dal framework.

Seek da un appunto → segmento/frame; trascrizione → stessi offset. Non bloccare il canvas se recorder, permessi o trascrizione falliscono. Test: pausa/ripresa, interruzioni, cambi rotta, storage pieno, riavvio e drift misurato contro campioni noti.

## AI, OCR e ricerca

Architettura progettata, nessun provider o risultato simulato nel codice. Contratti da introdurre nelle Fasi 5–6:

| Contratto | Responsabilità |
|---|---|
| AIProvider | `async throws`: richieste tipizzate, cancellazione, capability e output con citazioni; no accesso diretto al canvas |
| LocalAIProvider | Adattatore a Foundation Models/Core ML solo su OS/hardware supportati, con capability check e availability guard |
| RemoteAIProvider | Client di un backend autenticato che sceglie provider LLM intercambiabili; nessuna API key del provider nell’app |
| OCRService | Vision, testo e bounding box in coordinate pagina con confidence/versione |
| TranscriptionService | Apple Speech, segmenti con timestamp audio, permessi e supporto lingua/offline espliciti |
| EmbeddingService | Vettori con modello/versione e dimensione; rigenerazione indice su cambio modello |
| DocumentIndexingService | Chunking incrementale per revisione, OCR/PDF/trascrizioni, indice ricostruibile |
| RetrievalService | Ricerca per documento/cartella con filtri, ranking e riferimenti pagina/minuto |

Non sono protocolli con implementazioni vuote dichiarate operative. La futura API pubblica dovrà separare job di OCR/trascrizione, retrieval e generazione. Task AI cancellabili con priorità bassa, snapshot del contenuto e budget; salvataggio e scrittura non dipendono da disponibilità AI/rete.

Riassunti di lezioni/PDF/selezioni, mini schemi da foto, tutor su documento/cartella, flashcard/quiz, ricerca semantica, classificazione e confronto fra fonti saranno task distinti. Output con riferimenti a documentID/pageID o audioSessionID/frameOffset e revisione delle fonti. Un contenuto modificato rende obsoleto l’artefatto. Credenziali della sessione backend in Keychain; policy di consenso, retention e invio dei contenuti esplicita prima della prima richiesta remota.

## CloudKit: progettazione, nessuna sincronizzazione attiva

Scrittura locale sempre autorevole. Nessun entitlement iCloud, `cloudKitDatabase: .none`, nessuna dipendenza di rete. Una successiva outbox transazionale dei metadati porterà changeID, entityID, revisione base, operazione, retry e dipendenze dagli asset. Non viene creata oggi una coda che nessuno consuma.

Opzione prevista: adattatore CloudKit esplicito per record piccoli e asset separati. Un solo responsabile del sync, evitando doppi writer SwiftData automatico + CloudKit manuale. Conflitti semplici di metadati risolvibili per campo; pagine/disegni divergenti preservati come revisioni alternative o copie, mai perdita silenziosa per last-write-wins. Tombstone con retention, trasferimenti riprendibili, backoff e quota. Indisponibilità iCloud non deve impedire un commit locale. Collaborazione in tempo reale fuori dallo scope iniziale.

## Fonti Apple e limiti di verifica

API confrontate con documentazione ufficiale, **non** con un SDK installato, che manca in questo ambiente:

- [SwiftData ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer)
- [ModelContext e persistenza](https://developer.apple.com/documentation/swiftdata/modelcontext)
- [ModelConfiguration con URL](https://developer.apple.com/documentation/swiftdata/modelconfiguration/init(_:schema:url:allowssave:cloudkitdatabase:))
- [VersionedSchema](https://developer.apple.com/documentation/swiftdata/versionedschema)
- [Disabilitare il sync gestito CloudKit](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct/none)
- [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [Data.WritingOptions](https://developer.apple.com/documentation/foundation/data/writingoptions)
- [Privacy manifest e required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)

La validità sintattica non assicura compatibilità, type checking, espansione delle macro SwiftData/Observation, rendering SwiftUI o correttezza runtime. Il gate resta la build/test sul Mac e l’accettazione su iPad.
