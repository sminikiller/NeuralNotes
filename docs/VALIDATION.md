# Validazione della consegna 0.8.2

Correzioni descritte in [FIXES_0_8_2.md](FIXES_0_8_2.md). Controlli locali PASS: struttura, grammatica di 100 file Swift, integrità pacchetto iPad e sette test backend senza chiamate esterne. Sono presenti 151 metodi XCTest (77 core, 60 integrazione, 14 UI). La nuova compilazione e le suite Apple sono in corso: il PASS sottostante appartiene alla precedente 0.8.1. Nessuna prova fisica della Pencil o del runner Swift Playground.

## Evidenza storica 0.8.1

# Validazione della consegna 0.8.1

Data: 20 ottobre 2026. Controlli locali su Windows/PowerShell, Python 3.13 e Node 22; build e test Apple su GitHub Actions macOS 15, Xcode 16.4, Swift 6.1.2, SDK/simulatore iPadOS 18.5 (iPad Pro 11 M4). Non è una prova dell’iPad fisico dell’utente né del suo runner Swift Playground.

## Controlli locali

- Grafo Xcode: 196 oggetti, riferimenti e membership dei sorgenti, package locale e schema unit/UI.
- Plist/privacy, orientamenti iPad e scene, UIBackgroundModes/audio nei plist Xcode e Playground, capability camera/microfono/Speech, asset e checksum PNG.
- Parsing grammaticale dei 100 file Swift con tree-sitter 0.26 / tree-sitter-swift 0.7.4. Nessun type checking, macro, linking o availability verificati da questo controllo.
- Generazione deterministica del progetto e validità sintattica degli script Python.
- ZIP iPad: 86 file canonici sorgente/risorsa/plist copiati senza riscrivere Swift, più manifest; confronto byte per byte e insieme esatto, risorse e singolo @main. Manifest generato verificato grammaticalmente.
- ZIP sorgenti con progetto, test e documentazione, escludendo cache locali, .git, node_modules, DerivedData e file .env; checksum e file confrontati.

## Suite automatica

**Esito Apple: PASS.** [Esecuzione 39406620801](https://github.com/sminikiller/NeuralNotes/actions/runs/39406620801), commit sorgenti `a2799927e89f0d42ed6b1e847afb4b7803124a2a`.

- macOS `swift test`: 74 test, zero errori.
- Simulatore iPad: suite unit/integrazione da 127 metodi, 125 eseguiti con zero errori e due esclusi perché richiedono l’alias Darwin `/private/var`; entrambi sono stati eseguiti su macOS.
- UI iPad: tutti i 13 test eseguiti con zero errori, inclusi export separato da rinomina, Fine sopra la tastiera e ripristino dell’editor dopo il riavvio.
- `xcodebuild test` Debug: TEST SUCCEEDED. Build Release per dispositivo iOS generico, senza firma: BUILD SUCCEEDED.
- I sette test backend Node, struttura/grammatica e verifica del pacchetto iPad sono passati anche nel job portable.

Log integrale locale: `.verification/apple-validation-0.8.1.log`; log e bundle `.xcresult` sono negli artifact della run, con conservazione di 14 giorni. Il manifest AppleProductTypes del Playground e il dispositivo fisico non sono compilati/eseguiti da questa CI: app Xcode e Playground copiano gli stessi sorgenti canonici, ma hanno runner e manifest diversi. La consegna aggiorna successivamente soltanto i documenti di stato, mantenendo invariati i sorgenti verificati.

140 metodi XCTest: 74 core, 53 integrazione, 13 UI. La 0.8.1 aggiunge 11 regressioni su riconoscimento, catalogo/backup/cleanup e salvataggi interrotti o concorrenti. La 0.8 aggiunge 14 prove su workspace/palette, direzioni e riconoscimento delle forme, salvataggio/clone, righello e focus. La 0.7.1 aggiunge due prove per zoom a larghezza esatta, ripetizione/rotazione e pagina attiva nelle tre navigazioni, e aggiorna il test UI e il controllo geometrico incorporato. La 0.7 aggiunge sei prove per geometria continua, formati misti e offset, input preparato sicuro e completamento curl senza alterare i tratti. La 0.6.1 aggiunge quattro regressioni su viewport unico/dimensioni/assenza di scroll antenati, input ammessi per pan/pinch/swipe, blocco navigazione durante scrittura e dimensioni UI invarianti. La 0.6 aggiunge quattordici regressioni per zoom, navigazione, input testo, ordine dei callback PencilKit, giri/segni verticali, testo trascritto recuperabile/vuoto, retry e rinomina. Nella 0.5.1 si aggiungono sette regressioni per zig-zag piccoli, maschere successive persistenti, cancellazione di una parola digitata, adattamento pagina, undo/redo e apertura esclusiva dei due pannelli Audio. Le prove UI usano una fixture di soli metadati in uno storage DEBUG isolato. Nuove prove: piano di finestre per due ore senza buchi, export per minuto/ora, correzioni preservate durante nuovi chunk, default pagina/JSON/orientamento, distinzione scratch da linea/cerchio; PDF dalla libreria e rollback PDF invalido; cambio carta con undo e avanzamento solo all’ultima pagina; focus che nasconde/ripristina gli strumenti.

La fixture AudioTranscriptionTests usa un CAF sintetico reale di 95 secondi con riconoscitore iniettato: verifica fallimento dopo il primo chunk, checkpoint su disco, ricreazione controller, ripresa senza rieseguire quel chunk, rinomina e correzione conservata. Non verifica accuratezza, permessi o comportamento reale di Apple Speech.

26 controlli temporanei in Verifica sul dispositivo. La 0.8.1 aggiunge il recupero del catalogo con conservazione di originali e media. Restano inclusi geometria del fit/maschera riaperta, testo trascritto recuperato/vuoto, distacco e pagina visibile del layout continuo, PDF come nuovo quaderno, modelli carta e correzioni/export della trascrizione. Non simulano Pencil fisica o Scribble. Prova di carico facoltativa invariata: 50 pagine, CAF sintetico 60 s, PDF e backup reimportato. Nessun microfono acceso dai controlli ordinari.

Build e test automatici sono eseguiti dalla CI tramite tools/verify_macos.sh; l’esito complessivo è riportato sotto. Camera/Pencil fisiche, ASR reale, standby/background e prestazioni su iPad 10 della 0.8.1: NON ESEGUITI dall’agente. Percorso solo iPad: CONSOLIDATION_0_8_1.md, TESTING_0_8.md, FIXES_0_7_1.md, TESTING_0_7.md e regressioni precedenti.

## Evidenze dell’utente

Dopo la 0.6.1 l’utente ha risposto «perfetto» e ha richiesto scorrimento verticale continuo con poco distacco e voltata orizzontale a libro. È un riscontro manuale generale sulla precedente consegna; non verifica le nuove animazioni 0.7. Nessuna prova fisica di questa nuova versione è stata eseguita dall’agente.

La 0.6 è stata provata dall’utente: canvas ridotto in un secondo riquadro scorrevole e Pencil che sposta le pagine, impedendo la scrittura. Questa è una regressione confermata, non un dubbio teorico. La 0.6.1 rimuove quel contenitore e filtra l’input; la correzione non ha ancora una prova hardware. I precedenti PASS di struttura/ZIP non attestavano il funzionamento del layout.

Nella 0.5.1 l’utente segnala ancora doppio tocco e scarabocchio inefficaci, testo trascritto non visibile e navigazione soltanto tramite pulsanti. Questi sono i trigger della 0.6; nessuna conferma manuale della nuova consegna è stata ricevuta. La precedente conferma di sintassi/ZIP non equivaleva al funzionamento di questi gesti sul dispositivo.

La segnalazione precedente sulla registrazione in standby/background ha portato alla rimozione della pausa esplicita e alla dichiarazione della modalità audio nella 0.5.1. Il supporto background del runner Swift Playground deve essere verificato sul bundle effettivo e ascoltando una registrazione reale.

Le nuove immagini mostrano libreria/editor con immagini e inchiostro della versione precedente. L’utente segnala il PDF della libreria passato al decoder backup: corretto instradamento nella 0.5. Dopo la segnalazione iniziale sulle trascrizioni lunghe ha scritto «ora pare che funzioni»; questa è evidenza manuale del precedente percorso di riconoscimento, non un PASS della nuova gestione a checkpoint.

Il backend non è modificato: sette test Node superati anche in questa consegna e in CI, nessuna chiamata live. Cloud, backend configurato e distribuzione restano separati dal gate corrente. Non è stato prodotto un IPA firmato.

La 0.8 non ha conferme hardware dell’utente. I tre nuovi controlli incorporati verificano workspace su catalogo temporaneo, estremi direzionali e riconoscimento geometrico; non convalidano il monitor touch o l’anteprima live Pencil.

La foto dell’utente conferma un errore di type checking di HeldShapeRecognition nella 0.8. La 0.8.1 semplifica le espressioni; il parser grammaticale precedente non poteva rilevare quel problema. Il workflow Apple è attivo; l’esito effettivo è registrato anche in .verification/release-0.8.1.json. Nessun esito Apple viene dedotto dai controlli Python.
