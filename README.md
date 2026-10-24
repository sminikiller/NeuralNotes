# NeuralNotes 0.22.0 — delivery iPad

**0.22.0/build 49 — navigazione compatta:** cursore delle pagine con numero ingrandito durante il trascinamento, salto numerico, messaggi temporanei e stato raccolto in un'icona. I quaderni aperti si scelgono dal titolo, senza una riga dedicata alle schede. [Verifica finale Apple](https://github.com/sminikiller/NeuralNotes/actions/runs/40047775770) PASS: 268 Core, 98 FSRS, 93 test nativi, cinque UI, Release e ZIP reale compilato e avviato. Anche [Swift 5.10 / Xcode 15.4](https://github.com/sminikiller/NeuralNotes/actions/runs/40047781343) PASS sulla revisione finale. [Consegna, schermate, esiti completi e limiti](docs/DELIVERY_0_22_0.md).

**0.21.2/build 47 — scarabocchio per tratti:** elimina per intero tutti i tratti attraversati, rispettando il percorso effettivo dello scarabocchio e le zone già cancellate. Conservati gomma parziale e Annulla/Ripristina. [Verifica Apple](https://github.com/sminikiller/NeuralNotes/actions/runs/40004819461) PASS: 265 Core, 98 FSRS, 76 test dell'editor, cinque UI, Release e ZIP App Playground. [Consegna e limiti](docs/DELIVERY_0_21_2.md).

**0.21.1/build 46 — Annulla e nuova scrittura:** chiusura del tratto PencilKit in arrivo prima di scegliere la voce della cronologia, sostituzione del disegno senza disattivare il responder nativo e protezione dai nuovi tocchi durante il ripristino. Aggiunte quattro regressioni native e una prova UI che confronta i pixel dei tratti annullati e nuovi. Verificati 265 Core, 98 FSRS e tutti i 73 test nativi dell’editor; [seguito UI](https://github.com/sminikiller/NeuralNotes/actions/runs/40001794761) PASS per tutte le cinque prove, con identità dei sorgenti dell’app imposta dalla CI. Release e ZIP App Playground compilati realmente nella verifica precedente sugli stessi sorgenti. [Dettagli e limiti](docs/DELIVERY_0_21_1.md).

**0.21.0/build 45 — account, affidabilità e test:** reset dei livelli al cambio pagina, code cloud isolate per account, profilo/esportazione/cancellazione account e condivisione esplicita delle trascrizioni. [Verifica finale Apple](https://github.com/sminikiller/NeuralNotes/actions/runs/39982456433) PASS: 265 Core, 98 FSRS, 26 test di affidabilità, quattro UI audio, Release e ZIP App Playground compilato. Le altre classi native/UI sono state eseguite nella suite completa precedente; i percorsi corretti sono stati riprovati. Auth email/database/Storage reali locali e aggiornamento del binario conservando il quaderno di controllo passati. Servizi pubblici e prove fisiche iPad ancora aperti. [Stato, hash e limiti](docs/DELIVERY_0_21_0.md).

**0.20.8/build 44 — ZIP App Playground compilato:** riprodotto il mancato AppIcon generato delle 0.20.6/0.20.7; ripristinata l'icona personalizzata nel catalogo alla radice. Semplificate tre espressioni misurate come lente dal compilatore. La [run 39942124235](https://github.com/sminikiller/NeuralNotes/actions/runs/39942124235) estrae e compila lo ZIP con il suo manifest AppleProductTypes: PASS per simulatore iOS arm64/x86_64. Consegnato l'archivio esatto della CI. Restano prova fisica su iPad e sei fallimenti della suite funzionale separata. [Evidenze e limiti](docs/FIXES_0_20_8.md).

**0.20.7/build 43 — pacchetto dopo la prima verifica Apple:** include la correzione dei percorsi della libreria su Darwin e i controlli di annullamento dei backup del commit `5efb2b3`. Su GitHub la build Xcode Release è riuscita e i 260 test Core macOS più 98 FSRS sono passati. Restano un fallimento nei test nativi delle forme e cinque nei test UI; Playgrounds su iPad non è ancora verificato. Da quel commit questa consegna cambia soltanto versione, documentazione e nomi degli archivi. [Risultati e limiti](docs/DELIVERY_0_20_7.md).

**0.20.6/build 42 — errore AppIcon in Playgrounds:** la foto identifica un errore del compilatore degli asset, non dimostra un timeout SwiftUI. Nel pacchetto iPad l'icona è ora il libro generato da Playgrounds, senza richiedere l'asset `AppIcon`. Catalogo alla radice del target e risorse dichiarate singolarmente; il progetto Xcode conserva l'icona personalizzata. Verifiche locali del pacchetto passate, compilazione Apple ancora da confermare. [Correzione e limiti](docs/FIXES_0_20_6.md).

**0.20.5/build 41 — build della Lente:** divise le espressioni SwiftUI del pannello e delle azioni in parti indipendenti, per contenere il rischio di timeout del compilatore. La causa del nuovo blocco segnalato sull'iPad non è accertata senza il messaggio di Playgrounds; questa non è una build SDK verificata. [Intervento ed evidenze](docs/BUILD_0_20_5.md).

**0.20.4/build 40 — Lente temporanea e note facoltative:** selezione evidenziata, ritorno allo strumento precedente, poi Spiega/Chiedi/Cerca/Copia. Risposte in anteprima con Inserisci o Scarta, senza note automatiche; Nuova selezione per riattivare la Lente. Icone più piccole con area di tocco separata. [Flusso e verifiche](docs/WORKFLOW_0_20_4.md).

**0.20.3/build 39 — errore reale di compilazione della Lente:** rinominata la proprietà `hidden` che collide con UIKit e corretto l'avviso della ricerca. Aggiunta una protezione mirata al controllo AST. La 0.20.2 mostrata sull'iPad non compilava; la nuova patch è verificata sintatticamente, senza build Apple. [Correzione e limiti](docs/FIXES_0_20_3.md).

**0.20.2/build 38 — parole, ricerca PDF e note formattate:** integrato il lavoro non salvato di Claude e completato l'editor RTF delle note. Lente con parole intere, lazo/area, barra sulla selezione e cache; ricerca del livello digitale dei PDF grandi con avanzamento e ripresa; trascinamento di singoli oggetti tramite anteprima limitata. Elenchi, grassetti e paragrafi nel pannello e nella nota. [Comandi, verifiche e limiti](docs/DELIVERY_0_20_2.md).


Editor SwiftUI/UIKit e PencilKit, libreria SwiftData, PDFKit/Core Graphics, AVFoundation, Vision e Apple Speech. iPadOS 17 minimo. FSRS-6 è incluso con licenza MIT; le altre funzioni dell’app usano i framework di sistema. Pacchetto App Playground per iPad 10 / iPadOS 18.7.8 e progetto Xcode con test.

**0.20.1/build 37 — Lente AI più comoda e note collegate:** la conversazione della Lente si apre in un pannello a destra (o in una finestra mobile da trascinare), mai sopra la pagina; la barra della Lente sta sotto la barra degli strumenti; foto ritagliata prima di chiedere; domande successive sulla stessa selezione. Le note della Lente sono collegate al testo che spiegano, si spostano trascinandole, si riducono a 💡 e si riaprono con un tocco, si modificano e hanno un elenco con salto alla pagina. [Consegna e verifiche](docs/DELIVERY_0_20_1.md).

**0.20.0/build 36 — funzioni AI complete, account e cloud:** scheda, quiz e flashcard anche con chiave personale (OpenAI, Claude, Gemini, DeepSeek) e ricerca web con OpenAI; Lente con inserimento accanto alla selezione e flashcard sensate; flashcard generate, Interrogami e valutazione Difficile; sbobina AI a capitoli riprendibile; piano e consumi dell'account; backup nel cloud NeuralNotes con coda e conflitti. Core e backend verificati su Linux e con servizi locali reali; compilazione Apple e servizi ospitati non ancora provati. [Consegna, verifiche e attivazione](docs/DELIVERY_0_20_0.md).

**0.19.0/build 35 — PDF grandi e account:** import locale fino a 1 GiB e 5.000 pagine con copia/hash in blocchi, testo dei PDF grandi su richiesta e correzione del caricamento delle pagine appena create/importate. Auth/email/database reali verificati in locale; DeepSeek simulato nel test, servizi pubblici non attivati. Blueprint hosting e collegamento app predisposti. [Consegna e limiti](docs/DELIVERY_0_19_0.md), [attivazione](backend/ACTIVATION.md).

**0.18.0/build 34 — primo lotto AI gestita:** accesso email con codice, sessione rinnovabile nel portachiavi, consenso/cache per account e collegamento delle azioni della Lente al gateway. Spiegazione automatica dopo un gesto Lente esplicito con account e consenso attivi. Nessun servizio pubblicato o AI remota già attiva; schermate native e Keychain reale non ancora provati con Apple. [Implementazione, test e attivazione](docs/AI_MANAGED_0_18_0.md). Include la correzione della linea della 0.17.2 e la barra compatta 0.17.1.

**0.17.2/build 33:** riconoscimento della retta trattenuta con tolleranza limitata a una piccola sbavatura iniziale; la linea corretta usa la stessa geometria in anteprima e nell’inchiostro salvato. Pieghe centrali/finali e scarabocchi restano esclusi. [Correzione e test](docs/FIXES_0_17_2.md).

**0.17.1/build 32:** corregge la regressione del layout mostrata sull’iPad nella 0.17.0: la barra delle pagine con LazyHStack occupava altezza senza limite e comprimeva il foglio. Altezza ora vincolata a 56 punti, mantenendo pulsanti da almeno 44 e creazione lazy. Predisposto test UI delle dimensioni in verticale/orizzontale, non eseguito con Apple. [Patch e verifiche](docs/FIXES_0_17_1.md).

**0.17.0/build 31:** corretta la conferma di eliminazione delle pagine, ripristino esplicito, righello più largo e ridimensionabile con due dita, ritaglio foto con presentazione legata ai dati, testo sul foglio senza autofocus della tastiera o reset dello zoom per la sola variazione di altezza. [Consegna e limiti](docs/DELIVERY_0_17_0.md). Backend locale ampliato con DeepSeek, account verificati, quote atomiche, community e revisioni cloud; servizi online e schermate account/community non attivati. [Piano completo e costi](docs/AI_COMMUNITY_PLAN_0_17.md), [configurazione server](backend/ENVIRONMENT.md).

**0.16.0/build 30:** eliminate le scansioni ripetute delle pagine all’apertura e al cambio foglio. Manutenzione dopo inattività, cancellabile durante l’uso; il flush pulito e la chiusura non lanciano backup. Recupero audio senza player sul thread UI, tre anteprime vicine limitate e tempi di apertura visibili in Spazio e recupero. [Analisi, benchmark 6/12/300 pagine e limiti](docs/PERFORMANCE_0_16_0.md). Non è una garanzia di apertura entro un secondo sull’iPad.

**0.15.2/build 29:** completa la correzione del righello con l’override di gestureRecognizerShouldBegin ereditato da UIView. La foto successiva prova il fallimento della 0.15.1; la patch corrente non è ancora compilata con Apple. [Dettagli](docs/FIXES_0_15_2.md).

**0.15.1/build 28:** corregge il conflitto Objective-C `move:` del righello mostrato sull’iPad. Azioni dedicate per spostamento e rotazione, senza override del metodo UIKit. [Patch e limiti della verifica](docs/FIXES_0_15_1.md). Compilazione Apple della patch non ancora eseguita.

**0.15.0/build 27:** recupero dei pacchetti locali senza indice e import da cartella; lettura File coordinata, ordine stabile e confronto dei percorsi nei backup. Cestino pagine con selezione multipla e trasferimento nativo, mini toolbar fino a cinque strumenti, righello vincolante, cache dei ritagli e testo direttamente sul foglio. [Comandi, recupero e limiti](docs/DELIVERY_0_15_0.md).

**0.14.1/build 26:** corregge i due errori reali di compilazione del PDF mostrati sull’iPad: conformità del delegato già ereditata da PDFView e metodo ridichiarato senza override. Il filtro Pencil è ora sul solo riconoscitore della Lente, lasciando intatti i delegati nativi. [Correzione e limiti della verifica](docs/FIXES_0_14_1.md). La compilazione Apple della patch resta da confermare.

**0.14.0/build 25:** eliminazione visibile delle pagine, mini toolbar personalizzabile, popup verso l’interno, stili e colori RTF, forme precise, salti audio ±15 s. Import PDF/foto preparati fuori dal thread UI; PDF esterno affiancato con estratti e ricerca del termine senza import. Compressione PCM → AAC mono 64 kbps dopo la registrazione, transazione riprendibile, limiti di spazio per i backup e comando per le vecchie lezioni. [Comandi, test e pacchetti](docs/DELIVERY_0_14_0.md), [piano AI e dipendenze](docs/AI_FUNCTIONAL_PLAN.md).

**Verifica attuale:** 260 XCTest Core (258 passati, due skip Darwin) e 98 FSRS passati su Swift Linux. Backend invariato: restano i 48 test e l'integrazione account locale della 0.20.2, con trasporto AI simulato. Nuove prove RTF/PDF/Pencil e flusso della Lente predisposte ma non eseguite con Apple. Il blocco di fatturazione GitHub impedisce ancora la build Apple. Nessuna conferma di funzionamento sull’iPad o attivazione AI remota è implicita nel pacchetto.

**0.12.2:** correzioni degli errori reali segnalati in `SelectionCommands`, `LibraryView` e `PencilControls`, con riduzione delle espressioni SwiftUI e controllo mirato delle assegnazioni nei `catch`. [Patch e verifica](docs/FIXES_0_12_2.md). Conserva la [correzione CoreGraphics della 0.12.1](docs/FIXES_0_12_1.md). La nuova CI è stata fermata prima dei comandi dal blocco di fatturazione GitHub: la compilazione Apple resta non eseguita, non viene dichiarata una versione finale verificata.

**Sviluppo successivo alla 0.9.1:** correzioni di testo Pencil, gomma selettiva, foto e import PDF, nuovi strumenti, sezioni/sottosezioni, collegamenti e fonti, statistiche di ripasso, glossario e schede di definizione strutturate. [Avanzamento completo del piano](docs/CLAUDE_PLAN_AUDIT.md), [verifiche e limiti attuali](docs/ROADMAP_VALIDATION.md). La CI Apple più recente non è partita per il blocco di fatturazione GitHub; le ultime schermate non sono ancora compilate con l’SDK Apple. I test locali del Core sono eseguibili anche tramite Docker/Swift ufficiale, senza sostituire le prove UIKit o sull’iPad.

[Anteprima 0.12.0: comandi, pacchetto e conservazione dei quaderni](docs/DELIVERY_0_12_0.md). Aggiunge archivio/cestino delle lezioni, ricerca per nome ed export degli audio originali con trascrizione corretta e timestamp. La Lente si apre anche dal testo selezionato o dalla sottolineatura esplicita, in un popup espandibile. Ricerca web separata, facoltativa, con citazioni cliccabili e inserimento annullabile. [API, login ChatGPT e modello economico](docs/AI_API_AND_LOGIN.md). Restano disponibili le [funzioni della 0.11.0](docs/DELIVERY_0_11_0.md). Le nuove integrazioni Apple richiedono ancora compilazione e prova sul dispositivo.

**Nuove funzioni:** PDF e testo più nitidi allo zoom, backup automatici con versioni, penne/preset e gomma selettiva, selezione trasformabile, testo formattato, scanner, PDF affiancato, ricerca globale e Lente AI. [Funzioni, accesso ai comandi e limiti della 0.9](docs/STUDY_WORKSPACE_0_9.md). iCloud è predisposto con il Team ID fornito; firma e attivazione del contenitore restano da completare. Il backend AI richiede hosting HTTPS e configurazione.

**0.9.1 — trascrizione delle registrazioni lunghe:** ogni blocco viene letto direttamente dalla registrazione, senza conversione; il silenzio iniziale non ferma più il lavoro; un blocco che fallisce viene saltato e riprovato con Riprendi; parole salvate in frasi brevi; schermo acceso durante la trascrizione; "Prova il primo blocco" e registro diagnostico. [Prova sull'iPad](docs/TESTING_0_9_1.md).

**Stato della consegna:** [CI Apple superata per la 0.9.1](https://github.com/sminikiller/NeuralNotes/actions/runs/39472735749): 91 test core macOS, 164 unit/integrazione iPad (2 esclusioni del simulatore) e 16 UI test; build Release senza firma riuscita; 12 test backend. [Esiti e limiti](docs/VALIDATION.md). Apple Speech reale, Pencil fisica e runner Swift Playground restano da provare sull'iPad.

## Aprire sul solo iPad

1. Conserva il progetto precedente e i suoi dati.
2. In File decomprimi **NeuralNotes-iPad-0.20.8.zip** in una cartella separata.
3. Apri **NeuralNotes.swiftpm** in Swift Playground e premi Esegui app.
4. Sidebar → **Verifica sul dispositivo** → **Esegui controlli sul mio iPad**: controlli temporanei incorporati, distinti dalla suite XCTest.
5. I comandi recenti e il recupero sono nella [consegna 0.15.0](docs/DELIVERY_0_15_0.md). Restano le prove di [trascrizione lunga](docs/TESTING_0_9_1.md), [studio](docs/STUDY_WORKSPACE_0_9.md), [workspace e forme](docs/TESTING_0_8.md) e [scorrimento](docs/TESTING_0_7.md).

Il nuovo Playground può avere un container diverso: non elimina né aggiorna automaticamente i quaderni del precedente. Esporta dalla vecchia versione e importa dalla sidebar un `.nnbackup` o una cartella `.nnbook`. Per cercare i pacchetti in una cartella usa Recupero quaderni → Importa quaderni da una cartella. Non selezionare il progetto `.swiftpm` nell’importatore di quaderni. Conserva l’originale finché la copia non è riaperta e controllata. Questo pacchetto non è un IPA firmato.

## Correzioni 0.8.2

Scarabocchio lungo la traccia reale, forme riconosciute confermate fino al sollevamento, riapertura sull’ultima pagina modificata e copertina opzionale con anteprima della stessa pagina. [Comportamento e prova iPad](docs/FIXES_0_8_2.md).

## Consolidamento 0.8.1

Corretto il type-check troppo lento di HeldShapeRecognition segnalato sull’iPad, dividendo le formule in passaggi Double espliciti. Salvataggio dell’inchiostro indipendente dagli errori delle impostazioni, modifiche arrivate durante IO salvate prima del cambio pagina, protezione dei tratti attivi e recupero esplicito del catalogo precedente anche dall’editor, conservando originali/media e sessioni in memoria. Fine sopra la tastiera, ripristino persistente della sessione e trasferimento nativo del file della trascrizione. Ambiente SDK/compilatore visibile nella Verifica e workflow Apple attivo. [Prove e limiti](docs/CONSOLIDATION_0_8_1.md).

## Workspace e strumenti 0.8

Toolbar flottante nei quattro lati, workspace indipendenti salvati per quaderno e backup, preferiti riordinabili, tre colori e spessori recenti per strumento, mini toolbar espandibile in focus e indicatore REC/durata. Menu Azioni organizzato per attività. Libreria con recenti ad accesso diretto, copertine a colori/motivi/simboli o foto. Forme trascinate dal punto iniziale a quello finale, righello PencilKit e riconoscimento conservativo di linea/cerchio/rettangolo con pressione prolungata. [Comportamento, prove e limiti](docs/TESTING_0_8.md).

## Doppio tocco per lo zoom 0.7.1

Il doppio tocco/doppio clic alterna foglio intero centrato e foglio a tutta larghezza, senza margini laterali. Da uno zoom manuale torna al foglio intero. Il pulsante Pagina intera mantiene la propria funzione. Aggiornati il controllo geometrico incorporato e il test UI; aggiunte due regressioni di integrazione. [Prova sul dispositivo](docs/FIXES_0_7_1.md).

## Scorrimento continuo e voltata a libro 0.7

Il verticale ora mostra fogli consecutivi con distacco di 12 punti del documento e decelerazione continua nel PKCanvasView principale. Il cambio della pagina attiva mantiene la posizione del documento, senza ricreare il contenitore esterno della 0.6. Prefetch delle pagine vicine e protezione del primo contatto se una pagina non è pronta. L’orizzontale usa una voltata curl nei due sensi; Riduci movimento usa una dissolvenza. [Comportamento e prove](docs/TESTING_0_7.md). Le sei regressioni sono incluse nella suite Apple.

## Correzione layout e Pencil 0.6.1

Rimosso il secondo contenitore scorrevole introdotto nella 0.6. Il canvas principale occupa tutta l’area dell’editor e resta lo stesso nelle tre modalità. Pagina singola torna predefinita; sfoglio verticale e orizzontale usano solo le dita. Pan/pinch escludono Pencil e lo sfoglio è bloccato durante un tratto. Il precedente flusso verticale con anteprime impilate è sostituito dallo sfoglio nel canvas. [Dettagli, regressioni e prova iPad](docs/FIXES_0_6_1.md).

## Funzioni della 0.6

- Navigazione scelta per quaderno. Nella 0.6.1 il layout verticale della 0.6 viene sostituito: tutte le modalità mantengono il canvas principale, senza selezione automatica delle anteprime.
- Doppio tocco integrato con i gesti PencilKit e comando esplicito Pagina intera. Con disegno tramite dito, doppio tocco/sfoglio a due dita.
- Scarabocchio valutato dopo la consegna del disegno, con passaggi verticali e giri continui per annerire. Cancellazione locale con undo; riconoscimento euristico.
- Testo con Pencil: campo UITextView direttamente sul foglio per scrittura e gesti Scribble disponibili in iPadOS, oltre alla tastiera.
- Visualizza trascrizione apre un lettore completo. Checkpoint recuperati se la proiezione è vuota; risultati senza parole segnalati e ripetibili; rinomina con chunk vuoti conserva il testo.

[Prove, comportamento e limiti della 0.6](docs/TESTING_0_6.md). Le regressioni della 0.6 sono incluse nella suite Apple corrente.

## Correzioni 0.5.1

Registrazione senza pausa automatica passando in background, modalità audio dichiarata anche per il blocco schermo e controllo del recorder al ritorno. Il supporto effettivo del runner va verificato. Doppio tocco per pagina intera; scarabocchio più sensibile con cancellazione locale dell’inchiostro e delle parole digitate; pulsanti Audio indipendenti. [Dettagli e prove](docs/FIXES_0_5_1.md).

## Novità 0.5

- **Import PDF dalla libreria:** Importa PDF o quaderno riconosce i PDF e crea direttamente un quaderno annotabile col nome del file. Il percorso PDF è separato dal backup, con errori specifici e rollback del solo nuovo quaderno se fallisce. Originale conservato.
- **Carta e tipo quaderno:** alla creazione scegli carta libera/rigata/quadrettata/puntinata, sei colori, passo, margine, formato Classico/A4/Letter/Quadrato e orientamento. Icona foglio nell’editor per la pagina corrente e/o il modello delle pagine future. Cambio formato con contenuti ridimensionati e undo. Le pagine PDF mantengono il loro originale.
- **Focus completo:** nasconde toolbar, schede, navigazione e stato; mantiene lo strumento corrente. Pulsante flottante in alto a destra trascinabile, con posizione della scena e ritorno animato agli strumenti. Punto rosso se il microfono registra.
- **Avanzamento con trascinamento:** a pagina intera, trascina molto oltre il fondo per passare alla successiva o crearla se sei all’ultima. L’aggiunta è annullabile. Disattivabile in Carta e gesti rapidi.
- **Scarabocchio configurabile:** uno zig-zag ripetuto cancella parole digitate e inchiostro nella zona attraversata, con undo. Nella 0.5.1 è attivo inizialmente salvo preferenze già salvate; Carta e gesti rapidi permette di disattivarlo. La grafia viene cancellata geometricamente. Immagini e forme restano intatte.
- **Trascrizioni:** continua a usare Apple Speech on-device, ora con blocchi di 45 s, checkpoint persistenti, avanzamento, pausa/ripresa e un retry del blocco fallito. Chiudere il pannello per scrivere non cancella il lavoro; uscita dal quaderno/background lo sospendono. L’utente ha riferito che il riconoscimento precedente ora sembra funzionare: la qualità della nuova versione richiede comunque prova.
- **Nomi e correzioni:** Audio → Rinomina / correggi cambia titolo e testo per minuto senza toccare il CAF. Le correzioni sono conservate separatamente e protette durante una successiva ripresa. Esporta testo produce un .txt con riferimenti [hh:mm:ss] circa ogni minuto, marcato parziale quando necessario.

La suite storica della 0.5 conteneva **151 metodi XCTest** e **26 controlli incorporati**. Gli esiti della CI Apple sono in [VALIDATION.md](docs/VALIDATION.md). [Prove e limiti 0.5](docs/TESTING_0_5.md).

## Novità 0.4

- Toolbar con icone dirette per strumenti, undo/redo, testo, Foto, fotocamera e forme; palette richiudibile, colori/spessori rapidi, modalità concentrazione.
- Foto scattate o importate: anteprima, ritaglio libero/quadrato, rotazione di 90°, ridimensionamento. Il ritaglio è reversibile e conserva l’asset normalizzato.
- Cerchio/ellisse, rettangolo, linea e freccia; colore, spessore e geometria modificabili. Pannello oggetti aperto sulla selezione.
- Selezione multipla o a rettangolo di testi, immagini, forme e tratti. Spostamento di gruppi misti, copia/incolla interno anche tra quaderni, duplicazione ed eliminazione.
- Cronologia dell’editor per inchiostro, oggetti e pagine, incluso ordine/importazione/ripristino. Fino a 60 azioni e 48 MB stimati, nella sessione corrente. L’azione non viene consumata se il salvataggio fallisce.
- Ripristino di schede e quaderno selezionato tramite SceneStorage; ultima pagina per documento. Fino a sei schede, un canvas montato alla volta. Nuove finestre con libreria indipendente e protezione contro due editor che scrivono nello stesso quaderno.
- PDF con inchiostro ricostruito in geometria vettoriale; PDF originale e testo restano contenuti PDF. Export pagina per pagina, rilascio dei temporanei e possibilità di cancellazione tra pagine. Disponibile anche l’export con aspetto PencilKit raster.
- Recupero dei quaderni non registrati in libreria, indice precedente conservato, pagine rimosse recuperabili e report dello spazio. Pulizia esplicita dei file non referenziati a quaderno chiuso, con blocco se gli indici sono illeggibili.
- Nuovi test core, integrazione editor/PDF/concorrenza e UI; diagnostica incorporata estesa e prova temporanea con 50 pagine e CAF sintetico di 60 secondi.

## Funzioni già presenti

Libreria con cartelle/sottocartelle, copertine colore/fotografiche, preferiti, ricerca titoli, ordinamento, griglia/elenco e cestino. Pagine con miniature, titoli/segnalibri e sfondi bianco, rigato, quadrettato o puntinato. PencilKit con penna, evidenziatore, gomma vettoriale e lazo; zoom/pan e scrittura con dito opzionale. Import PDF, caselle di testo, immagini e allegati originali. Backup completo a blocchi con checksum, importazione e unione con nuove identità.

Audio CAF segmentato, pausa/ripresa, timeline/seek, gestione interruzioni e collegamento dai tratti ai momenti registrati. Vision OCR su pagina/area; Apple Speech richiesto esclusivamente on-device, a finestre per file lunghi. Ricerca nel testo, PDF, OCR e trascrizioni con pagina/minuto. Ricerca semantica opzionale con embedding italiani del sistema se disponibili.

Studio offline estrattivo, schemi, flashcard/quiz e ripasso persistente. L’estrazione locale seleziona frasi delle fonti: non è un LLM. AI remota opzionale con client HTTPS, consenso, token backend in Keychain e citazioni validate. Il [backend Node](backend/README.md) ha 23 test locali superati; hosting, modello, segreti e prova live non sono configurati.

## Permessi e finestre

Microfono, fotocamera e riconoscimento vocale sono dichiarati nel manifest Playground e nell’Info.plist Xcode; richiesta all’uso. Foto usa il selettore del sistema. La dichiarazione di più scene è inclusa anche nel Playground tramite AppInfo.plist. Il menu Nuova finestra controlla il supporto del processo ospitante: se Swift Playground non espone più scene, mostra un messaggio; la prova di finestre resta necessaria sul dispositivo.

Il ripristino delle schede dipende dal ripristino della scena iPadOS; non è una sincronizzazione tra installazioni o dispositivi. Le schede conservano editor e canvas inattivi: memoria con sei quaderni da misurare.

La registrazione attiva può continuare con schermo bloccato e passando ad altre app quando il processo ospitante supporta la modalità audio in background. Il pannello Audio verifica la dichiarazione nel bundle. Chiudere il quaderno o un’interruzione audio sospende il microfono; la terminazione del processo non consente di continuare. La trascrizione viene sospesa in background.

## Salvataggio e limiti

```text
Application Support/NeuralNotes/Library.store
Documents/Notebooks/<documentID>.nnbook/
  manifest.json               # identità e ordine attuale
  manifest.previous.json      # indice precedente
  pages/<pageID>.json          # oggetti, coordinate, revisione, anchor, OCR
  drawings/*.drawing          # PKDrawing corrente e precedente
  images/                     # asset normalizzati, crop nei metadati
  attachments/                # originali PDF e allegati
  audio/                      # segmenti CAF
  catalog.json                # allegati, audio, trascrizioni, flashcard
  artifacts/                  # elaborazioni con fonti
  recovery/                   # copie di indici danneggiati
```

Writer actor per documento, scritture atomiche, autosave a 700 ms e flush alla navigazione/uscita/background. Un arresto può perdere la parte ancora in memoria. Recuperare un indice non ripara un media realmente danneggiato. La pulizia protegge anche le pagine rimosse e i loro disegni precedenti; il cestino dei quaderni resta persistente, senza svuotamento fisico globale.

La ricostruzione PDF vettoriale approssima texture e opacità dei pennelli PencilKit: il `.drawing` nativo resta l’originale. Le immagini fotografiche restano raster. La selezione a rettangolo include tratti interi in base ai loro bounding box; il lazo PencilKit agisce sull’inchiostro. La cronologia unificata usa i pulsanti della toolbar; il gesto nativo a tre dita e l’undo dentro TextEditor restano gestiti dai rispettivi controlli. L’incolla di tratti crea nuove identità senza copiare i collegamenti audio.

## Verifiche e parti aperte

[Prove iPad 0.7](docs/TESTING_0_7.md) · [Correzione iPad 0.6.1](docs/FIXES_0_6_1.md) · [Prove iPad 0.6](docs/TESTING_0_6.md) · [Correzioni iPad 0.5.1](docs/FIXES_0_5_1.md) · [Prove iPad 0.5](docs/TESTING_0_5.md) · [Validazione effettiva](docs/VALIDATION.md) · [Accettazione](docs/ACCEPTANCE.md).

Su Windows: `python tools/check_project.py --swift-syntax`, `python tools/package_ipad.py`, `python tools/package_project.py`. Sono controlli di sorgenti e packaging, non compilazione Swift. Su un futuro Mac: `bash tools/verify_macos.sh` per core, unit/UI test su simulatore e build Release senza firma.

Restano la verifica Apple della nuova versione, registrazioni reali lunghe, documenti grandi, memoria/latency/VoiceOver e profili di performance. Il piano originale prevede CloudKit in seguito: non è attivo. Modello generativo locale, classificazione automatica e comprensione visiva generativa non sono implementati. Il backend richiede distribuzione/configurazione; account Apple, firma e TestFlight/App Store restano da predisporre. [Stato per modulo e prossime prove](ROADMAP.md) · [Architettura](ARCHITECTURE.md).
