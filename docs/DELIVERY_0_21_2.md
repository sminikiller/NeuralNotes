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

## Segnalazione successiva: «Build failed» su iPad

Il 23 ottobre è stato segnalato un blocco della compilazione direttamente in Playgrounds, senza il dettaglio del compilatore. Il difetto non è stato riprodotto: non viene dichiarato risolto.

Esteso `tools/verify_playground_macos.sh` per compilare il pacchetto estratto anche con destinazione `generic/platform=iOS`, senza firma, oltre al simulatore. La [run 40012111732](https://github.com/sminikiller/NeuralNotes/actions/runs/40012111732), revisione `32c486f`, ha completato entrambe le compilazioni con `BUILD SUCCEEDED`. I contenuti di tutti i 226 file dello ZIP coincidono byte per byte con l'archivio già consegnato; app, manifest e risorse non sono cambiati. Il vecchio ZIP resta conservato con la stessa impronta.

Questa verifica aggiuntiva controlla il codice per il dispositivo e il pacchetto reale. Non verifica firma, cache, risorse disponibili o compilazione interna di Playgrounds sull'iPad. Non è disponibile un collegamento al registro del dispositivo. La sola dicitura «Build failed» non identifica il file o la causa.

Passi diagnostici reversibili: conservare il progetto attuale; chiudere e riaprire Playgrounds; estrarre lo ZIP in una nuova cartella locale di File → Sul mio iPad e aprire il pacchetto completo `NeuralNotes.swiftpm`. In caso di nuovo blocco, l'icona rossa degli errori in Playgrounds mostra il dettaglio utile, invece del solo titolo generico. Non è necessaria la cancellazione dei dati dell'app per queste prove.

## Anteprima funzionante, pulsante Play bloccato: verifica dell'app dello ZIP

L'utente ha poi confermato che l'app nell'anteprima funziona ed è fluida, mentre il pulsante Play continua a fallire. Questo distingue i due percorsi di esecuzione ma non dimostra una causa specifica: firma, compilazione/collegamento, installazione e primo avvio nell'ambiente del dispositivo restano da discriminare.

La CI ora offre `playground_launch`: installa sul simulatore l'app generata dal pacchetto reale e avvia `neuralnotes.swiftpm.NeuralNotes`. Non avvia il diverso binario del progetto Xcode usato dai test UI precedenti. Conserva stdout/stderr, registro di sistema, schermate, esito JSON e un campione delle attività del processo.

- [Run 40022602434](https://github.com/sminikiller/NeuralNotes/actions/runs/40022602434): compilazioni e sopravvivenza del processo passate. La prima schermata mostrava ancora «Apertura libreria». Questa prova da sola **non** confermava che la libreria fosse pronta.
- [Run 40023821079](https://github.com/sminikiller/NeuralNotes/actions/runs/40023821079), revisione `19957bf`: compilazioni, processo in esecuzione durante le 60 iterazioni d'attesa e libreria/guida visibili passati. Il controllo Vision OCR è passato e la schermata finale è stata anche ispezionata visivamente. Le iterazioni non sono un limite preciso del tempo totale di avvio: si aggiungono lancio, campionamento e acquisizione delle immagini.
- I 226 file del pacchetto verificato coincidono byte per byte con lo ZIP 0.21.2 già consegnato. App, editor, manifest e dati non sono stati modificati in questa indagine.

È una verifica dell'avvio del pacchetto reale su simulatore, non una prova di interazione completa né dell'anteprima o del pulsante Play di Playgrounds sull'iPad fisico. Il blocco specifico del pulsante Play resta non riprodotto e non viene dichiarato risolto. Il controllo con un compilatore precedente non è stato eseguito: il primo tentativo di dispatch della nuova workflow dedicata era stato rifiutato perché assente dal ramo predefinito; nessun risultato di quella prova viene rivendicato.

Per l'uso attuale vale la verifica fisica comunicata dall'utente sull'anteprima. Prima di cambiare copia del progetto è utile conservare backup nativi dei quaderni, perché copie diverse del Playground possono usare librerie separate.
