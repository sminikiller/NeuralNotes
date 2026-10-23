# NeuralNotes 0.21.2 / build 47

## Scarabocchio: cancellazione per tratti

Lo scarabocchio con la penna applicava una maschera parziale ai tratti incontrati. Per questo rimanevano frammenti della stessa scrittura, come con una gomma a pixel. Adesso elimina per intero ciascun tratto attraversato, comprese le parti separate da una precedente cancellazione parziale.

Il contatto viene verificato sul percorso effettivo dello scarabocchio e sull'inchiostro ancora visibile, tenendo conto di trasformazioni e maschere. Il rettangolo di ingombro serve soltanto a escludere velocemente i tratti lontani: non viene usato come area da cancellare. I tratti nel centro vuoto di uno scarabocchio ad anello restano intatti; passare su un'area già cancellata non elimina il resto di un tratto senza contatto con l'inchiostro visibile.

La cancellazione parziale della gomma conserva il comportamento precedente. La modalità per tratti della gomma selettiva per evidenziatore usa lo stesso controllo di contatto, evitando di costruire una maschera che verrebbe subito scartata. La cancellazione delle parole di testo mantiene la propria soglia di copertura.

La cancellazione tramite scarabocchio resta un'unica azione di Annulla/Ripristina. Non cambia il formato dei documenti.

## Verifiche

Tre nuove regressioni native controllano:

- eliminazione di tutti i tratti distinti attraversati da uno scarabocchio, conservazione di quelli vicini e ciclo Annulla/Ripristina/salvataggio/riapertura;
- passaggio su un'interruzione già cancellata senza effetti e rimozione di tutti i frammenti dello stesso tratto quando viene toccata una parte visibile;
- contatto con tratti ruotati e ingranditi e con un punto isolato.

Aggiornate le prove esistenti dello scarabocchio ad anello, del disegno consegnato in ritardo da PencilKit e dell'annullamento. Restano attive anche le prove della cancellazione parziale.

Verifica Apple della revisione `520a4ac`: [run 40004819461](https://github.com/sminikiller/NeuralNotes/actions/runs/40004819461), conclusa con successo.

| Prova | Risultato |
| --- | --- |
| Core macOS | 265 XCTest e 98 FSRS passati. |
| Editor su iPad Simulator | 76 test passati: 46 integrazione e 30 affidabilità. Tutte e tre le nuove regressioni passate. |
| Interfaccia | Cinque test passati: quattro audio e il ciclo di input nativo/Annulla/nuovo tratto/Annulla/Ripristina, con confronto dei pixel. |
| Release iOS | `BUILD SUCCEEDED`. |
| App Playground | ZIP estratto e compilato con il proprio manifest, Xcode 16.4, simulatore iOS 18.5 arm64/x86_64: `BUILD SUCCEEDED`. |
| Controlli portabili | Struttura, grammatica Swift, pacchetto e 53 test Node passati. |

Il log nativo contiene anche diagnostici CoreGraphics su valori NaN ignorati e un identificatore di tratto non disponibile, durante la sequenza dei test di affidabilità. Nessun test è fallito e il runner non si è interrotto. L'origine di questi diagnostici non è accertata; non vengono presentati come errori risolti da questa patch.

## Consegna

`NeuralNotes-iPad-0.21.2.zip`: 506284 byte, 226 file. SHA-256: `27a5325a8f25b51cad795b525dc93f328fe2c0cc5da834b25267705f95cac2dd`.

L'archivio consegnato è quello compilato dalla CI, verificato tramite CRC e confronto dei contenuti con i sorgenti locali; per i soli file di testo vengono normalizzati i fine riga Windows/macOS. La versione precedente non viene sovrascritta.

Non è disponibile una Apple Pencil fisica collegata a questo ambiente: le prove native e UI sul simulatore non sostituiscono la verifica del gesto sull'iPad dell'utente.
