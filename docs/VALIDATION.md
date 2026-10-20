# Validazione della consegna 0.8

Data: 20 ottobre 2026. Windows/PowerShell, Python 3.13 e Node 22. Swift/Xcode/SDK Apple non disponibili; nessuna build Apple della nuova versione eseguita qui.

## Controlli locali

- Grafo Xcode: 194 oggetti, riferimenti e membership dei sorgenti, package locale e schema unit/UI.
- Plist/privacy, orientamenti iPad e scene, UIBackgroundModes/audio nei plist Xcode e Playground, capability camera/microfono/Speech, asset e checksum PNG.
- Parsing grammaticale dei 98 file Swift con tree-sitter 0.26 / tree-sitter-swift 0.7.4. Nessun type checking, macro, linking o availability verificati da questo controllo.
- Generazione deterministica del progetto e validità sintattica degli script Python.
- ZIP iPad: 85 file canonici sorgente/risorsa/plist copiati senza riscrivere Swift, più manifest; confronto byte per byte e insieme esatto, risorse e singolo @main. Manifest generato verificato grammaticalmente.
- ZIP sorgenti con progetto, test e documentazione, escludendo cache locali, .git, node_modules, DerivedData e file .env; checksum e file confrontati.

## Test forniti, non eseguiti qui

129 metodi XCTest: 67 core, 49 integrazione, 13 UI. La 0.8 aggiunge 14 prove su workspace/palette, direzioni e riconoscimento delle forme, salvataggio/clone, righello e focus. La 0.7.1 aggiunge due prove per zoom a larghezza esatta, ripetizione/rotazione e pagina attiva nelle tre navigazioni, e aggiorna il test UI e il controllo geometrico incorporato. La 0.7 aggiunge sei prove per geometria continua, formati misti e offset, input preparato sicuro e completamento curl senza alterare i tratti. La 0.6.1 aggiunge quattro regressioni su viewport unico/dimensioni/assenza di scroll antenati, input ammessi per pan/pinch/swipe, blocco navigazione durante scrittura e dimensioni UI invarianti. La 0.6 aggiunge quattordici regressioni per zoom, navigazione, input testo, ordine dei callback PencilKit, giri/segni verticali, testo trascritto recuperabile/vuoto, retry e rinomina. Nella 0.5.1 si aggiungono sette regressioni per zig-zag piccoli, maschere successive persistenti, cancellazione di una parola digitata, adattamento pagina, undo/redo e apertura esclusiva dei due pannelli Audio. Le prove UI usano una fixture di soli metadati in uno storage DEBUG isolato. Nuove prove: piano di finestre per due ore senza buchi, export per minuto/ora, correzioni preservate durante nuovi chunk, default pagina/JSON/orientamento, distinzione scratch da linea/cerchio; PDF dalla libreria e rollback PDF invalido; cambio carta con undo e avanzamento solo all’ultima pagina; focus che nasconde/ripristina gli strumenti.

La fixture AudioTranscriptionTests usa un CAF sintetico reale di 95 secondi con riconoscitore iniettato: verifica fallimento dopo il primo chunk, checkpoint su disco, ricreazione controller, ripresa senza rieseguire quel chunk, rinomina e correzione conservata. Non verifica accuratezza, permessi o comportamento reale di Apple Speech.

25 controlli temporanei in Verifica sul dispositivo; i due nuovi controllano geometria del fit/maschera riaperta e distinzione fra testo recuperato e analisi vuota. Non simulano eventi touch o Scribble. Il ventiduesimo verifica distacco e pagina visibile del layout continuo, non il movimento reale. Restano inclusi PDF come nuovo quaderno, modelli carta e correzioni/export della trascrizione. Prova di carico facoltativa invariata: 50 pagine, CAF sintetico 60 s, PDF e backup reimportato. Nessun microfono acceso dai controlli ordinari.

Build Debug/Release, XCTest/UI, nuova camera/gesti, ASR reale, standby/background e prestazioni 0.8: NON ESEGUITI in questo ambiente. Comandi futuri Mac: tools/verify_macos.sh. Percorso solo iPad: TESTING_0_8.md, FIXES_0_7_1.md, TESTING_0_7.md e regressioni precedenti.

## Evidenze dell’utente

Dopo la 0.6.1 l’utente ha risposto «perfetto» e ha richiesto scorrimento verticale continuo con poco distacco e voltata orizzontale a libro. È un riscontro manuale generale sulla precedente consegna; non verifica le nuove animazioni 0.7. Nessuna prova fisica di questa nuova versione è stata eseguita dall’agente.

La 0.6 è stata provata dall’utente: canvas ridotto in un secondo riquadro scorrevole e Pencil che sposta le pagine, impedendo la scrittura. Questa è una regressione confermata, non un dubbio teorico. La 0.6.1 rimuove quel contenitore e filtra l’input; la correzione non ha ancora una prova hardware. I precedenti PASS di struttura/ZIP non attestavano il funzionamento del layout.

Nella 0.5.1 l’utente segnala ancora doppio tocco e scarabocchio inefficaci, testo trascritto non visibile e navigazione soltanto tramite pulsanti. Questi sono i trigger della 0.6; nessuna conferma manuale della nuova consegna è stata ricevuta. La precedente conferma di sintassi/ZIP non equivaleva al funzionamento di questi gesti sul dispositivo.

La segnalazione precedente sulla registrazione in standby/background ha portato alla rimozione della pausa esplicita e alla dichiarazione della modalità audio nella 0.5.1. Il supporto background del runner Swift Playground deve essere verificato sul bundle effettivo e ascoltando una registrazione reale.

Le nuove immagini mostrano libreria/editor con immagini e inchiostro della versione precedente. L’utente segnala il PDF della libreria passato al decoder backup: corretto instradamento nella 0.5. Dopo la segnalazione iniziale sulle trascrizioni lunghe ha scritto «ora pare che funzioni»; questa è evidenza manuale del precedente percorso di riconoscimento, non un PASS della nuova gestione a checkpoint.

Il backend non è modificato: sette test Node superati nella consegna precedente, nessuna chiamata live. Cloud, backend configurato e distribuzione restano separati dal gate corrente. Non è stato prodotto un IPA firmato.

La 0.8 non ha conferme hardware dell’utente. I tre nuovi controlli incorporati verificano workspace su catalogo temporaneo, estremi direzionali e riconoscimento geometrico; non convalidano il monitor touch o l’anteprima live Pencil.
