# NeuralNotes 0.20.7 / build 43 — ZIP successivo alla prima CI Apple

23 ottobre 2026. Il repository è pubblico per autorizzazione esplicita dell'utente; i job GitHub ora partono. Questa consegna impacchetta i sorgenti applicativi del commit `5efb2b3`, compilati realmente con Xcode. Dopo quel commit cambiano soltanto versione/build, documentazione e nomi degli archivi. Non vengono dichiarate corrette le sei prove ancora fallite.

## Modifiche applicative rispetto allo ZIP 0.20.6

- `NativeDocumentStore` risolve il percorso canonico della radice prima delle operazioni iniziali: su Darwin, creare una directory sul collegamento simbolico già presente poteva produrre ENOTDIR. La prova dedicata ora passa su macOS.
- Il backup verifica l'annullamento prima dell'operazione e dopo la scrittura dell'archivio temporaneo, prima di pubblicare e ruotare le copie.
- Il test di annullamento usa una Task già annullata invece di presumere che una copia richieda oltre 10 ms. Verifica deterministica di mancata pubblicazione/rotazione, non simulazione di ogni momento possibile di un'interruzione.
- Lo script CI raccoglie i risultati delle diverse fasi senza saltare la compilazione dell'app se un test Core fallisce; termina comunque con errore se una fase fallisce.

Il pacchetto conserva l'icona libro generata da Playgrounds e il catalogo esplicito introdotti nella 0.20.6. Nessuna modifica al formato dei quaderni o ai provider AI.

## Risultati reali Apple

[Run 39879092836, commit 5efb2b3](https://github.com/sminikiller/NeuralNotes/actions/runs/39879092836), Xcode 16.4 / Swift 6.1.2:

- Controlli portabili/backend/pacchetto: passati.
- Core su macOS: 260 XCTest, zero fallimenti; 98 test FSRS passati.
- Test nativi su simulatore: 382 eseguiti, due saltati, un fallimento.
- Test UI: 23 eseguiti, cinque fallimenti.
- Build Xcode Release per dispositivo, firma disabilitata: `BUILD SUCCEEDED`.
- Esito complessivo CI: **failure**, per i test. La build riuscita non è prova di correttezza di tutte le funzionalità.

## Sei test ancora aperti

1. Forma trattenuta: il test richiede due punti per la linea, mentre l'implementazione ora la campiona (62 nella prova). La geometria e la persistenza vanno verificate prima di correggere l'aspettativa.
2. Audio: raggiungibilità e apertura del lettore della trascrizione.
3. Audio: raggiungibilità e apertura della condivisione del testo.
4. Audio: raggiungibilità dei comandi per archiviare/ripristinare una trascrizione.
5. Testo sul foglio: l'elemento esiste ma il test tenta la digitazione senza focus tastiera.
6. Workspace: il test non trova il comando delle opzioni penna/gomma nel percorso atteso.

Queste sono le evidenze dei test: per i cinque casi UI occorre esaminare gerarchia e screenshot xcresult prima di attribuire ogni errore al prodotto o al test. Non sono stati semplicemente rimossi o saltati.

## Verifica della consegna

Controlli locali di struttura, membership, grammatica Swift, cataloghi/plist e ZIP con uguaglianza byte per byte. Nessuna nuova CI ripetuta per sole modifiche di versione/documentazione. La CI Xcode costruisce il progetto `.xcodeproj`, non il manifest App Playground: **compilazione e avvio su Playgrounds/iPad restano da verificare**. Non è una IPA firmata né un'attivazione dei servizi AI remoti.

Aprire `NeuralNotes.swiftpm` da `NeuralNotes-iPad-0.20.7.zip` decompresso in una cartella separata. Conservare vecchio progetto ed export; non eliminare i dati dell'app.
