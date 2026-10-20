# NeuralNotes 0.8.2 — app nativa iPad


Editor SwiftUI/UIKit e PencilKit, libreria SwiftData, PDFKit/Core Graphics, AVFoundation, Vision e Apple Speech. iPadOS 17 minimo, nessuna dipendenza di terze parti nell’app. Pacchetto App Playground per iPad 10 / iPadOS 18.7.8 e progetto Xcode con test.

**Stato della consegna:** [CI Apple superata](https://github.com/sminikiller/NeuralNotes/actions/runs/39433258233): 77 test core macOS, 135 unit/integrazione iPad e tutti i 14 UI test superati, più due esclusioni specifiche del simulatore; build Release senza firma riuscita. [Esiti e limiti](docs/VALIDATION.md). La prova della Pencil fisica e del runner Swift Playground resta necessaria.

## Aprire sul solo iPad

1. Conserva il progetto precedente e i suoi dati.
2. In File decomprimi **NeuralNotes-iPad-0.8.2.zip** in una cartella separata.
3. Apri **NeuralNotes.swiftpm** in Swift Playground e premi Esegui app.
4. Sidebar → **Verifica sul dispositivo** → **Esegui controlli sul mio iPad**: 26 controlli temporanei.
5. Prova [workspace, toolbar, forme e copertine](docs/TESTING_0_8.md), poi segui [le prove di scorrimento e voltata 0.7](docs/TESTING_0_7.md), poi le regressioni precedenti e la prova di carico facoltativa.

Il nuovo Playground può avere un container diverso: non elimina né aggiorna automaticamente i quaderni del precedente. Esporta dalla vecchia versione e importa dalla sidebar un `.nnbackup` o una cartella `.nnbook`. Non selezionare il progetto `.swiftpm` nell’importatore di quaderni. Conserva l’originale finché la copia non è riaperta e controllata. Questo pacchetto non è un IPA firmato.

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

La suite corrente contiene **151 metodi XCTest** e **26 controlli incorporati**. Gli esiti della CI Apple sono in [VALIDATION.md](docs/VALIDATION.md). [Prove e limiti 0.5](docs/TESTING_0_5.md).

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

Studio offline estrattivo, schemi, flashcard/quiz e ripasso persistente. L’estrazione locale seleziona frasi delle fonti: non è un LLM. AI remota opzionale con client HTTPS, consenso, token backend in Keychain e citazioni validate. Il [backend Node](backend/README.md) è implementato e ha sette test locali già superati; hosting, modello, segreti e prova live non sono configurati.

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
