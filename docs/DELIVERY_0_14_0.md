# NeuralNotes 0.14.0 / build 25 — editor, PDF e spazio

Aggiornamento del 21 ottobre 2026. Funzioni implementate nei sorgenti; non è una distribuzione firmata né una build verificata con SDK Apple. Il ramo Claude `claude/lotto-1-bozza` / `9a79d58` è stato esaminato come bozza: la conversione è stata completata con una transazione riprendibile, senza considerare la bozza già collaudata.

## Comandi dell’editor

| Richiesta | Comportamento e accesso |
| --- | --- |
| Eliminare pagine | Pagine → cestino sull’anteprima, oppure menu della pagina. Conferma, annulla/ripristina, conservazione dei file recuperabili. Eliminare un’altra pagina mantiene quella corrente. Se elimini l’ultima viene creato un foglio vuoto. |
| Mini toolbar personalizzata | Solo foglio → espandi mini toolbar → ingranaggio. Da uno a tre strumenti per workspace, indipendenti dai preferiti della toolbar grande. Scegli Lazo per l’inchiostro, Oggetti per selezionare anche testi/immagini. La configurazione è anche in Workspace. |
| Popup della toolbar a destra | Freccia sul bordo destro del popup: il contenuto apre verso l’interno. Stessa impostazione per palette, selezione e opzioni; ridotta la larghezza del pannello selezione. |
| Righello | Usa il righello nativo di PencilKit con penna o evidenziatore: traccia vicino al bordo. Il riconoscimento su pressione prolungata non interferisce mentre è attivo. Posizione e rotazione con due dita. Il comportamento fisico di aggancio resta da provare con Pencil. |
| Forme | Linea con più campioni vettoriali; aggancio ogni 45° entro ±6°, mantenendo la lunghezza. Rettangoli ruotati riconosciuti e raddrizzati conservando l’orientamento. Anteprima e inserimento usano lo stesso aggancio anche per le frecce. |
| Testo | Barra sopra la tastiera: Titolo 1, Titolo 2, Corpo, colore del testo ed evidenziazione; rimangono grassetto, corsivo, elenchi e checklist. Attributi salvati in RTF e usati dal renderer del foglio/PDF, con annulla/ripristina. |
| Ascolto | −15 s e +15 s sia nel pannello audio sia durante la lettura della trascrizione. Le richieste di ascolto superate da un nuovo salto non riattivano il vecchio player. |

## Import e PDF affiancato

La lentezza non si può attribuire solo a Playground: lettura, parsing/estrazione PDF, hash e decodifica/PNG delle immagini avvenivano sul MainActor. Ora queste preparazioni usano task separati. I PDF pubblicano l’elenco delle pagine con un solo aggiornamento del manifest, dopo averle validate tutte. Non vengono copiati inchiostro, testi o immagini della pagina precedente. Restano i limiti di 100 MB per file, 1000 pagine per PDF e immagini ridotte a 2400 pixel sul lato lungo.

Questo elimina lavoro sincrono dalla UI, ma non costituisce una misura della velocità sull’iPad: provider iCloud/File, dimensione, immagini e prima resa PDFKit possono ancora richiedere tempo. La pipeline delle anteprime non è interamente fuori dal thread UI.

PDF affiancato → cartella **Apri PDF da File** apre un riferimento esterno senza aggiungere pagine o allegati al quaderno. Accesso al file mantenuto finché il pannello è aperto; originale non modificato. Seleziona il testo per copiarlo o inserirlo con nome file e pagina. Il collegamento riapribile all’interno del quaderno rimane disponibile per gli estratti dei PDF importati; il riferimento esterno ha una citazione testuale, non un bookmark persistente.

Attiva **Cerchia / sottolinea per cercare** per usare un gesto Pencil esplicito: la selezione prende l’area della traccia o il testo sopra la sottolineatura. Il popup offre dizionario, ricerca nel browser e ricerca AI citata se il backend è configurato e autorizzato. Il browser riceve solo il termine. I PDF scansiti senza testo non hanno ancora OCR automatico nel pannello esterno: l’app segnala il caso invece di cercare un vecchio termine. L’evidenziazione persistente riguarda i PDF importati; il riferimento esterno rimane in sola lettura.

## Compressione audio

- La registrazione resta PCM/CAF. Solo dopo **Termina e salva**, con microfono, trascrizione e ascolto inattivi nel controller, parte la conversione delle parti PCM in AAC mono 64 kbps/M4A. Gli audio già compressi non vengono ricodificati.
- AVAudioFile legge e scrive buffer da 32768 frame, senza caricare una lezione intera in memoria; i canali vengono miscelati in mono. Scrittura su nome unico, finalizzazione e sincronizzazione prima della verifica.
- Controllo dei frame/durata decodificata, formato AAC/mono e dimensione. Scarto durata massimo 0,5 s e, più restrittivo, deriva tra PCM, AAC e durata nel catalogo inferiore a 50 ms. Start, host time, anchor, bookmark e tempi dei blocchi non vengono riscalati.
- Un journal registra sorgenti, fingerprint, destinazioni verificate e stato. Prima cambia il catalogo, poi la copia precedente del catalogo, infine rimuove i PCM non trattenuti dal recupero. Alla riapertura riprende anche dopo un cambio dei riferimenti già riuscito o una pulizia interrotta.
- Un errore conserva i PCM e le parti recuperabili. **Metti in pausa** lascia il journal; **Annulla conversione e conserva PCM** rimuove soltanto le proprie uscite non referenziate e soltanto prima del cambio dei riferimenti. Dopo il cambio si completa la pulizia.
- Spazio e recupero → **Comprimi registrazioni** gestisce anche le vecchie lezioni, con stima dello spazio recuperabile. Circa 29 MB/ora è il payload teorico a 64 kbps, non una misura dei file finali. Backup e copie di recupero possono occupare spazio aggiuntivo.
- Lettura/trascrizione usano AVAudioFile anche per AAC. I confini originari dei checkpoint vengono preservati quando l’AAC espone pochi frame di padding. L’export copia le parti attive CAF/M4A e include codec, bitrate, byte originali e timestamp nel manifest versione 2. Import e backup accettano i campi opzionali; il catalogo rimane versione 1.
- Durante una conversione incompleta, export/backup del quaderno attendono il completamento: non producono una copia di un catalogo a metà transazione. La pulizia protegge tutti i file del journal. Lo spazio insufficiente è segnalato, senza cancellare preventivamente gli originali.

## Limite dei backup

Budget per quaderno: `min(1 GiB, max(64 MiB, 3 × dimensione del quaderno))`. Si conservano sempre le due copie più recenti anche se superano il limite. Altrimenti, fino a cinque versioni entro budget; vengono eliminate prima le più vecchie, solo dopo che la nuova copia è completa. Spazio e recupero mostra uso e limite ed esplicita l’eccezione delle due copie protette. Anche la cartella di backup esterna applica la politica di budget e conserva le due copie più recenti; richiede ancora una prova con provider File reale.

## Verifiche e limiti

Eseguiti con Swift 6.1.2 Linux: **174 XCTest, 172 passati e due esclusioni Darwin preesistenti, zero fallimenti; 98 test FSRS passati**. Le nuove prove coprono journal e riapertura prima/dopo il cambio del catalogo e con PCM già parzialmente rimossi, annullamento conservativo, deriva rifiutata, protezione dei file durante pulizia, backup/export di riferimenti AAC, rotazione/restauro di backup oltre budget, append di 100 pagine, geometria e preferenze focus. Nei test portabili i payload AAC sono fixture: non sono prove del codec.

Preparati **sei nuovi metodi Apple**, non eseguiti: CAF sintetico → AAC reale, attacchi audio allineati entro 50 ms e lettura iniziale/finale/ultimo buffer parziale; controller con trascrizione simulata su AAC e ripresa dei blocchi; eliminazione pagina/undo; RTF/PDF/undo; configurazione del righello nativo; selezione su PDF esterno senza import. Due controlli nuovi nella diagnostica portano il totale a **35** e provano codec/ultimo blocco e budget su file temporanei. Un controllo mostra successo solo quando eseguito nell’app.

Controllati grafo del progetto, membership, manifest/privacy e parsing grammaticale/compilatore Swift in modalità 5. Questo non è type checking con SDK Apple. La CI Apple resta bloccata prima degli step dalla fatturazione GitHub, come documentato nella run [39589913621](https://github.com/sminikiller/NeuralNotes/actions/runs/39589913621). Nessuna modifica a pagamenti o tentativo di aggirare il blocco.

Non verificati: build Apple di questa versione, Pencil/camera/scanner fisici, tempi degli import, standby e ASR reale di ore, qualità AI o chiamate remote. Backend invariato: i 23 test a fixture della 0.12 restano l’ultima esecuzione; nessun test live è dichiarato passato. Firma e hosting/credenziali AI restano non attivati. [Piano AI e criteri di completamento](AI_FUNCTIONAL_PLAN.md), [residui dell’intera roadmap](CLAUDE_PLAN_AUDIT.md).

## Pacchetti

`NeuralNotes-iPad-0.14.0.zip`: package completo `NeuralNotes.swiftpm`, da aprire interamente in Swift Playground. `NeuralNotes-Sorgenti-0.14.0.zip`: progetto, test, backend e documentazione. Gli script verificano corrispondenza esatta dei file e integrità ZIP; non compilano l’app. Versione 0.14.0/build 25, senza cambiare lo schema SwiftData della libreria.

Conserva la vecchia copia del Playground: copie diverse possono usare sandbox separate. Trasferisci i quaderni tramite backup nativo e verifica la copia prima di eliminare l’originale. Non è necessario cancellare dati per aggiornare il codice.

Riferimenti tecnici Apple: [lettura/scrittura AVAudioFile](https://developer.apple.com/documentation/avfaudio/avaudiofile), [inizializzazione del writer](https://developer.apple.com/documentation/avfaudio/avaudiofile/init(forwriting:settings:commonformat:interleaved:)), [righello PencilKit](https://developer.apple.com/documentation/pencilkit/pkcanvasview/isruleractive), [pagina PDF al punto del gesto](https://developer.apple.com/documentation/pdfkit/pdfview/page(for:nearest:)).
