# NeuralNotes — Fase 1

Progetto **nativo iPadOS**, SwiftUI + SwiftData. Identità originale verde laguna, copertine geometriche, sidebar adattiva e dark mode di sistema. Nessuna web app, servizio remoto o dipendenza di terze parti nell’app.

**Stato al 19 ottobre 2026: codice della Fase 1 implementato, build Apple e accettazione su iPad ancora da eseguire. La Fase 2 non è iniziata.** Non è una versione già certificata per distribuzione.

## Hai soltanto un iPad?

È disponibile anche **NeuralNotes-iPad.zip**, contenente l’app nativa in formato **NeuralNotes.swiftpm** per **Swift Playground**. Il tuo iPad di decima generazione con iPadOS 18.7.8 soddisfa il requisito dichiarato dalla versione attuale di Swift Playground. Installa l’app Apple, estrai lo ZIP in File, apri il progetto e premi Esegui: [istruzioni solo iPad](docs/IPAD.md).

Il pacchetto iPad usa gli stessi sorgenti del progetto Xcode, con due target locali e risorse SwiftPM. Non richiede un Mac per la prima esecuzione tramite Swift Playground, ma questa compilazione deve ancora essere verificata sul dispositivo. Non è un IPA già installabile dalla schermata Home.

## Aprire e installare

1. Copia questa cartella su un Mac con Xcode e apri **`NeuralNotes.xcodeproj`**. Il progetto è già incluso: non serve eseguire generatori.
2. Seleziona lo schema condiviso **NeuralNotes** e un simulatore iPad con iPadOS 17 o successivo. Esegui **Product → Run**.
3. Per il dispositivo fisico, in **Signing & Capabilities** seleziona il tuo Team e imposta un Bundle Identifier univoco. I tre target hanno identificativi iniziali `com.neuralnotes.*`; aggiorna quelli dei test se necessario.
4. Collega l’iPad, selezionalo come destinazione, abilita la modalità sviluppatore sul dispositivo se richiesta e avvia l’app.

L’archivio per distribuzione richiede firma, certificati e provisioning del proprio account. Non sono inclusi segreti, API key o credenziali Apple. Usa un Xcode che supporti la versione di iPadOS del dispositivo e i requisiti di invio correnti di Apple.

## Ambiente e compatibilità

| Voce | Rilevazione / scelta |
|---|---|
| Ambiente disponibile | Windows, PowerShell, Python 3.13.7, Git; repository inizialmente vuoto |
| Xcode / `xcodebuild` / `xcrun` | Non disponibili |
| Compilatore Swift / SDK iPadOS | Non disponibili; nessuna API verificabile contro un SDK locale |
| Deployment target | iPadOS 17.0; solo famiglia iPad (`TARGETED_DEVICE_FAMILY = 2`) |
| Baseline del sorgente | Swift 5.9, language mode Swift 5, package tools 5.9, Xcode 15 come baseline teorica |
| Verifica reale della compatibilità | Da effettuare con il proprio Xcode; non affermata per nessuna versione |
| Dipendenze dell’app | SwiftUI, Observation, Foundation, SwiftData; package locale NeuralNotesCore |
| Non aggiunti | PencilKit, PDFKit, audio, AI, iCloud: saranno introdotti nelle rispettive fasi |

La baseline deriva dalle API iPadOS 17 impiegate; non equivale al requisito attuale per pubblicare su App Store. La [tabella ufficiale Xcode/SDK](https://developer.apple.com/xcode/system-requirements/) permette di verificare il proprio abbinamento Mac, Xcode e dispositivo.

## Funzioni presenti nel codice

- Libreria inizialmente vuota: nessun documento di esempio che nasconda problemi di persistenza.
- Creazione, apertura, rinomina, modifica della copertina con cinque colori e spostamento dei quaderni fra cartelle.
- Cartelle e sottocartelle, rinomina e rimozione delle cartelle vuote; azioni nel menu contestuale.
- Preferiti, ricerca per nome, ordinamento per nome/creazione/modifica, griglia/elenco. Ordinamento e layout sono preferenze persistenti.
- Duplicazione dei **quaderni vuoti della Fase 1**, con nuove identità documento/quaderno.
- Eliminazione logica con conferma e annullamento dell’ultima eliminazione nella sessione. Nessuna cancellazione fisica automatica dei pacchetti.
- Scheda quaderno con verifica del manifest su disco, date e versione del formato. **Zero pagine: l’editor non è ancora disponibile.**
- Errori di storage espliciti, controllo di integrità all’avvio, nessun reset automatico della libreria.
- Sidebar adattiva, orientamenti iPad, colori di sistema per dark mode, etichette VoiceOver e scorciatoia ⌘N. Questi aspetti attendono verifica visiva/runtime.

Copertine fotografiche, editor, schede di documenti simultanei, import/export, PDF, audio, OCR, trascrizione, AI e CloudKit **non sono implementati**. L’annullamento di una cancellazione non è ancora un cestino persistente navigabile; i record eliminati e i file sono comunque conservati.

## Verifiche

Controlli ripetibili su Windows o Mac, Python standard library:

```sh
python tools/check_project.py
```

Il controllo legge realmente il plist OpenStep del progetto, verifica riferimenti, target, sorgenti, schema di test, package locale, plist XML, asset e checksum PNG. **Non compila Swift e non esegue i test dell’app.**

Su Mac con Xcode completo selezionato, Python 3 e runtime simulatore iPad installato:

```sh
bash tools/verify_macos.sh
```

Lo script mostra Xcode/Swift/SDK disponibili, esegue `swift test`, i test XCTest/UI su simulatore e una build Release per dispositivo senza firma. Produce un `.xcresult` in `.verification/`. Per scegliere il simulatore:

```sh
xcrun simctl list devices available
NEURALNOTES_SIMULATOR_ID="UUID-DEL-SIMULATORE" bash tools/verify_macos.sh
```

Comandi singoli equivalenti:

```sh
xcodebuild -version
xcrun swift --version
xcodebuild -showsdks
xcodebuild -project NeuralNotes.xcodeproj -scheme NeuralNotes -showdestinations
swift test
xcodebuild test -project NeuralNotes.xcodeproj -scheme NeuralNotes \
  -destination 'platform=iOS Simulator,id=UUID-DEL-SIMULATORE' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project NeuralNotes.xcodeproj -scheme NeuralNotes \
  -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Segue la verifica sul dispositivo descritta in [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md). Il risultato dell’ambiente corrente è in [docs/VALIDATION.md](docs/VALIDATION.md).

Sono forniti test per round trip del manifest, corruzione/versioni future, identità, pacchetti orfani, validazione dei nomi, persistenza SwiftData su disco, cartelle, duplicazione, eliminazione/ripristino, fallimenti di scrittura e riavvio del processo UI. **Non sono stati eseguiti qui.**

## File e recupero

```text
Application Support/NeuralNotes/
  Library.store                 # metadati SwiftData; conservare anche eventuali -wal/-shm
Documents/Notebooks/
  <document-uuid>.nnbook/
    manifest.json               # schemaVersion, documentID, notebookID, createdAt, pageIDs
    pages/ drawings/ images/ audio/ attachments/
```

Il database è la fonte autorevole di titoli, copertine, preferiti, cartelle e date. Il manifest identifica il documento; **il pacchetto isolato non è ancora un export completo**. Le directory dei contenuti sono predisposte ma vuote in Fase 1. I nomi dei file usano UUID, mai testo inserito dall’utente.

Se un manifest è illeggibile o manca, l’app segnala il problema e conserva il record. Se rimane un pacchetto senza record dopo un’interruzione, l’app lo segnala e lo mantiene nella posizione originale. Non ricostruisce automaticamente titoli/cartelle dal manifest, che non li contiene. Per recuperare: non reinstallare l’app; su Mac scarica il container tramite Xcode **Devices and Simulators → Download Container** e conserva **l’intero container** prima di intervenire. Ripristino assistito dei pacchetti orfani e cestino persistente sono sviluppi successivi.

I test UI Debug usano un’area distinta `NeuralNotes-UITests`; il reset di test non tocca i quaderni normali. Non abilitare più scene prima di aggiungere coordinamento e test di concorrenza fra finestre.

## Organizzazione

```text
NeuralNotes/App/                         composizione dipendenze e bootstrap
NeuralNotes/Core/Domain/                 valori di dominio e contratto repository
NeuralNotes/Core/Storage/                formato e pacchetti nativi
NeuralNotes/Infrastructure/Persistence/  SwiftData, schema versionato e transazioni
NeuralNotes/Features/Library/            ViewModel, libreria e form
NeuralNotes/Features/Notebook/           apertura e riepilogo documento
NeuralNotes/DesignSystem/                colori e copertine originali
NeuralNotes/Resources/                   icona, Info.plist, privacy manifest
Tests/NeuralNotesCoreTests/              test Foundation, anche via Swift Package Manager
NeuralNotesTests/                        test di integrazione iPadOS
NeuralNotesUITests/                      test ciclo di vita dell’app
tools/                                  generazione riproducibile e verifiche
```

Se aggiungi nuovi sorgenti dell’app o test, aggiorna il progetto in Xcode oppure rigenera con `python tools/generate_project.py`. Il generatore sovrascrive il progetto e gli asset prodotti: conserva prima eventuali modifiche manuali, inclusa la firma. Nessun generatore è necessario per aprire il progetto fornito.

Decisioni e modello futuro: [ARCHITECTURE.md](ARCHITECTURE.md). Milestone e criteri: [ROADMAP.md](ROADMAP.md).
