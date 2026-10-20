# NeuralNotes 0.6 — build 11

**Superata dalla 0.6.1:** il contenitore verticale descritto sotto ha causato una regressione reale di layout/input. È stato rimosso e sostituito dallo sfoglio nel canvas principale. Per layout e navigazione seguire [FIXES_0_6_1.md](FIXES_0_6_1.md). Le sezioni su trascrizioni, testo e scarabocchio restano prove delle altre funzioni.

Questa consegna risponde ai problemi ancora presenti nella 0.5.1: doppio tocco inefficace, testo delle trascrizioni non visibile, navigazione limitata ai pulsanti e cancellazione tramite scarabocchio. Implementazione e controlli locali completati; compilazione Apple e prove reali restano da eseguire sul dispositivo.

## Prima di aprire la nuova copia

Conserva la copia precedente del Playground. Esporta i quaderni importanti dal suo editor con **⋯ → Esporta quaderno nativo** e salva i .nnbackup in File. Le copie possono usare dati separati: aprire lo ZIP nuovo non trasferisce i quaderni. Nella nuova versione importa i backup dalla libreria e controllali prima di abbandonare l’originale. Non eliminare i dati dell’app per risolvere un errore di compilazione.

Decomprimi NeuralNotes-iPad-0.6.zip e apri NeuralNotes.swiftpm intero. Esegui **Verifica sul dispositivo**: ora ci sono **21 controlli**, due in più per geometria/maschere e recupero/assenza del testo trascritto. Questi controlli non simulano tocchi, Scribble o riconoscimento vocale reale.

## Zoom e pagina intera

Ingrandisci con due dita, sposta il foglio e fai doppio tocco con un dito. Deve tornare alla pagina intera. Con scrittura tramite dito attiva usa il doppio tocco a due dita; con un puntatore prova il doppio clic. Il comando **Pagina intera**, icona con frecce diagonali nella barra superiore, fornisce lo stesso risultato. Prova anche in focus, dopo rotazione e nelle tre modalità di navigazione.

La precedente integrazione lasciava il gesto in competizione con i riconoscitori interni del canvas. Ora i riconoscitori sono sul canvas, consentono la simultaneità con i gesti PencilKit e separano dito/puntatore da Apple Pencil. Serve una verifica con tocchi reali; il test UI fornito ingrandisce e verifica il ritorno alla scala minima.

## Navigazione decisa per quaderno

Usa **Navigazione pagine** nella barra superiore o **Carta e formato → Navigazione delle pagine**:

- **Scorrimento verticale**, predefinito: pagine una sotto l’altra. Scorri con le dita; la pagina più visibile diventa modificabile dopo una breve pausa, oppure toccane una. Un solo canvas scrive nel documento; le altre pagine hanno anteprime. Per iniziare un tratto su una pagina non ancora attiva, toccala prima. Le pagine sono adattate al viewport; pizzica la pagina attiva per ingrandirla. Quando è ingrandita scorri dentro il foglio, poi usa Pagina intera per tornare allo scorrimento del documento. In fondo c’è Aggiungi pagina.
- **Sfoglia orizzontalmente**: a pagina intera, scorri a sinistra per andare avanti e a destra per tornare indietro. Lo swipe non crea pagine oltre l’ultima; usa + Pagina. Quando sei ingrandito, il gesto sposta il foglio.
- **Pagina singola**: mantiene la navigazione con i pulsanti e il trascinamento oltre il fondo configurabile per avanzare/creare una pagina.

Con scrittura tramite dito attiva usa due dita per lo scorrimento/sfoglio. La preferenza viene ricordata per documento in questa installazione; non viene trasferita dal backup.

Crea tre pagine con contenuti diversi. Prova avanti/indietro, cambio modalità, salto con i pulsanti, riapertura e undo dopo un cambio pagina. Non devono scomparire contenuti o apparire pagine duplicate. Verifica anche un PDF con pagine di proporzioni differenti e la continuità della registrazione mentre cambi pagina.

## Scarabocchio sulla grafia

Seleziona **Penna** e controlla **Carta e gesti rapidi → Scarabocchio per cancellare**. Ripassa avanti e indietro almeno più volte, oppure annerisci con più giri continui la zona di una parola, poi solleva Pencil. Sono ora accettati passaggi verticali e giri ripetuti oltre agli zig-zag orizzontali. Una linea o un cerchio singolo non bastano. La valutazione attende il disegno definitivo consegnato da PencilKit; la versione precedente poteva valutare prima dell’arrivo del tratto.

La cancellazione agisce sulla geometria dell’inchiostro nella zona, preservando il resto dei tratti collegati. Sul testo digitato rimuove le parole attraversate. Non interpreta semanticamente le parole manoscritte. Immagini e forme non sono rimosse. I tratti distinti separati da sollevamenti non vengono aggregati in un unico scarabocchio; il riconoscimento rimane euristico.

Prova su due parole collegate, su una parte di lettera e sul testo digitato. Controlla Annulla/Ripristina, due cancellazioni successive, riapertura ed export PDF. Fai anche disegni normali per verificare cancellazioni indesiderate. Il test di regressione consegna il disegno dopo il callback di fine strumento, come può accadere nell’app reale.

## Testo con Pencil e gesti di iPadOS

Lo strumento **Testo con Pencil**, icona con cursore di testo, permette di toccare una casella sul foglio e modificarla direttamente; toccando uno spazio libero crea una casella. Il bordo indica il campo attivo. Scrivi con Apple Pencil o tastiera, seleziona/correggi il testo e premi Fine o scegli un altro strumento. Il campo è un UITextView standard: Scribble, selezione, inserimento e cancellazione del testo convertito sono forniti da iPadOS quando abilitati e disponibili per lingua/Pencil. Verifica l’impostazione Scribble/Scrivi a mano nelle impostazioni Apple Pencil del dispositivo.

La grafia libera di Penna resta inchiostro PencilKit. Per modificarla si usano gomma, lazo e scarabocchio dell’app; i gesti di modifica del testo di sistema richiedono un campo di testo. Riferimento: [UIScribbleInteraction e UITextInput](https://developer.apple.com/documentation/uikit/uiscribbleinteraction).

Prova scrittura, cancellazione con Scribble e selezione nel campo; cambia pagina, riapri e controlla testo, posizione e undo. Non dichiarare superata la prova del gesto Pencil usando soltanto la tastiera o i test di metadati.

## Trascrizione visibile e risultato vuoto

In Audio, **Visualizza trascrizione** apre il testo completo in un lettore scorrevole, con selezione/copia e pulsanti timestamp per ascoltare. Rinomina / correggi ed Esporta testo mantengono pannelli separati. I blocchi duraturi vengono usati come sorgente leggibile se il vecchio catalogo contiene il testo nei checkpoint ma ha la proiezione vuota.

Un riconoscimento completato senza parole mostra **Analisi completata senza testo riconosciuto** e **Riprova trascrizione**. Non viene chiamato Trascrizione salvata e l’export resta disabilitato. La ripetizione rielabora i blocchi vuoti. I dati già presenti non vengono cancellati per ritentare. È corretto anche il caso di una rinomina con testo presente ma array dei chunk vuoto, che poteva svuotare la proiezione.

Prova una registrazione parlata di più minuti, apri il lettore, scorri fino in fondo, copia e confronta il TXT. Rinomina, riapri e verifica che il testo sia conservato. Prova anche audio senza parole: deve esserci un messaggio esplicito, non un risultato invisibile indicato come salvato. La disponibilità e la qualità di Speech restano da provare sul dispositivo.

## Evidenza delle verifiche

Forniti **103 XCTest**: 56 core, 37 integrazione e 10 UI, nessuno eseguito su Windows. Quattordici regressioni aggiunte per classificazione scarabocchi, testo recuperato/vuoto, ordine dei callback PencilKit, navigazione/persistenza, testo in pagina, conflitti dei riconoscitori, retry audio, rinomina e UI di zoom/navigazione/lettore/input. I test audio usano file CAF sintetici e un riconoscitore iniettato; non provano Apple Speech reale.

[Validazione locale](VALIDATION.md) · [Gate di accettazione](ACCEPTANCE.md) · [Regressioni precedenti](TESTING_0_5.md). Le prove hardware di standby/background della [0.5.1](FIXES_0_5_1.md) restano necessarie.
