# NeuralNotes 0.12.1, build 23 — compilazione della Lente

Riscontro reale dell’utente sull’iPad: la 0.12.0 non compila in `LensGeometry` con «Argument passed to call that takes no arguments» sulla costruzione del rettangolo. È presente anche il messaggio delle anteprime «AppController.swift not in a target»; non è una prova che i dati del quaderno siano danneggiati.

## Correzione

Il Core usa le geometrie di Foundation su Linux; sui sistemi Apple importa ora esplicitamente CoreGraphics, con compilazione condizionale. Coordinate, dimensioni e spazio della pagina usano `CGFloat` prima di costruire i rettangoli, senza affidarsi agli import transitivi dei framework UI. Anche il test delle geometrie importa CoreGraphics quando disponibile. [Inizializzatori documentati da Apple](https://developer.apple.com/documentation/corefoundation/cgrect).

Il comportamento della Lente resta invariato: cerchio completo, sottolineatura e clipping ai limiti del foglio. Aggiunta prova con coordinate frazionarie per controllare che la conversione non arrotondi né sposti l’area.

## Pacchetto

`NeuralNotes-iPad-0.12.1.zip` contiene il progetto `NeuralNotes.swiftpm` intero, con `AppModule` e `NeuralNotesCore` separati. Il generatore controlla l’appartenenza dei sorgenti, la sola entrata `@main` e l’uguaglianza dei file canonici con i file distribuiti. `App/AppController.swift` è incluso nel target dell’app.

Aprire il progetto `.swiftpm` e usare **Esegui app**. L’anteprima del singolo file non sostituisce la compilazione dell’app. Conservare la copia precedente e i suoi quaderni: la correzione non richiede «Elimina i dati dell’app». Una copia separata del Playground può avere un contenitore separato.

## Limiti della verifica

Le prove automatiche disponibili sono registrate in [ROADMAP_VALIDATION.md](ROADMAP_VALIDATION.md). Non è stato eseguito un compilatore con SDK Apple per questa patch: la conferma della build iPad e del messaggio delle anteprime resta aperta. La segnalazione dell’utente della 0.12.0 è conservata come fallimento reale, non sostituita da un PASS Linux.

Le altre funzionalità sono descritte nella [consegna 0.12.0](DELIVERY_0_12_0.md); il lavoro residuo rimane nell’[audit](CLAUDE_PLAN_AUDIT.md).
