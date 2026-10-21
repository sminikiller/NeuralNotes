# Verifiche della lavorazione successiva alla 0.9.1 — aggiornato alla 0.12.0

Branch: `codex/editor-reliability-and-roadmap`. Non è una dichiarazione di completamento di tutta la roadmap o di pubblicazione su App Store.

## Prove locali del 21 ottobre 2026

- Swift 6.1.2 Linux, immagine ufficiale `swift:6.1.2`: **163 XCTest, 161 superati e due esclusioni già previste dall’ambiente, zero errori; 98 Swift Testing FSRS passati**. Include recupero snapshot interrotti, identità e media dei quaderni, sezioni cicliche/profonde, assegnazione pagine, collegamenti diretti/inversi, clone/unione, statistiche e ora legale, trascrizione sintetica di tre ore, correzioni autorevoli e stato parziale esplicito. Nuove prove della 0.11: transazione di due pagine e recupero del journal interrotto, rifiuto prima di qualsiasi scrittura per geometria/revisioni/media errati, quiz con scadenza e ripresa/clone, mappa modificabile e fonti, budget della cache, identità Spotlight, fonti fino alla fine di una lezione e budget Unicode, rifiuto di catalogo/file oltre limite conservando byte precedenti, lettura limitata anche per pagine JSON altrimenti valide, immagini copiate indipendenti dal sorgente e rifiuto di media assenti/fuori budget/con percorsi esterni. Nuove prove della 0.12: **otto ore sintetiche/640 checkpoint** con riapertura, ultima parte e correzioni; export a blocchi di parti audio con metadati di sei ore, byte identici e transcript corretto; archivio/cestino/ripristino senza perdita di media o anchor; esclusione del cestino dalla ricerca; geometria della sottolineatura e del cerchio chiuso; citazioni web Unicode, protocolli rifiutati, identità della cache e conservazione in clone/conversazioni.
- Backend Node: **23 test passati**, comprese schede `/v1/lookup`, quiz `/v1/quiz`, opzioni distinte, citazioni, autenticazione, quote, streaming interrotto e risposta incompleta. La ricerca `/v1/research` verifica abilitazione esplicita, termine isolato, tool effettivo, una chiamata massima, URL sicuri e rifiuto di output incompleti/non citati; il budget di uscita e il ragionamento configurato sono verificati su tutti i percorsi. Nessuna chiamata a pagamento.
- Controllo progetto: **386 oggetti, 243 file Swift analizzati, 284 metodi XCTest individuati**. In aggiunta, parsing con il compilatore Swift 6.1.2 in modalità Swift 5 per sorgenti app e test Apple. Il parsing non equivale a type checking, compilazione con SDK o esecuzione dei test Apple.

I due skip Linux riguardano gli alias Darwin `/private/var`, assenti su questo host (`testDarwinPrivateVarAliasAllowsNewFiles` e `testDarwinAliasesProduceTheSameArchiveEntryNames`); non sono esclusioni aggiunte per nascondere regressioni. Tutte le prove multiore qui eseguite usano riconoscimento sintetico: non misurano Apple Speech o la registrazione fisica in standby. La sequenza di otto ore ha completato 640 salvataggi e una riapertura, con risultati fino a 07:59:15 e correzioni conservate.

I nuovi test Apple coprono taglia rifiutato senza perdita, spostamento misto testo/inchiostro con anchor audio e undo/redo, drop PDF senza note della pagina precedente, localizzazione del testo formattato e laser senza mutazioni, nota rapida con testo e controlli incorporati su documenti temporanei. La 0.12 aggiunge il menu AI del testo selezionato, link RTF con undo, export/organizzazione audio e un file WAV sparso di **sei ore**: durata/frame reali, controller interrotto dopo 120 blocchi e ricreato per gli altri 360 con riconoscimento iniettato. **Sono presenti ma non eseguiti**. I controlli incorporati sono **33**, di cui due nuovi della 0.12; una riga «Completato sul dispositivo» compare soltanto se quel controllo viene realmente eseguito e riesce nell’app.

Esecuzione Core su Windows con Docker Desktop attivo:

```powershell
docker volume create neuralnotes-swift-build
docker run --rm --mount "type=bind,source=$($PWD.Path),target=/workspace,readonly" --mount "type=volume,source=neuralnotes-swift-build,target=/build" --workdir /workspace swift:6.1.2 bash tools/verify_linux.sh
```

Il workspace resta montato in sola lettura. Il volume conserva cache di compilazione e copie temporanee dei sorgenti. Linux usa `apple/swift-crypto` fissato alla 3.12.3; Apple usa CryptoKit del sistema e il Playground non scarica dipendenze. Le prove Linux non compilano UIKit, PencilKit, PDFKit, SwiftData o le schermate SwiftUI.

## Prove Apple effettive

- Run `39483133356`, commit `eba004f`: ultima esecuzione interamente verde di questa lavorazione, con 178 XCTest sul simulatore (due esclusioni), 98 FSRS, 18 UI e Release senza firma.
- Run `39488740893`, commit `08a3720`: Core 107 XCTest + 98 FSRS passati; simulatore 194 XCTest (due esclusioni) + 98 FSRS passati. Il test UI testo Pencil è passato; due test Audio falliti perché i comandi non erano visibili nella lista. Posizione dei comandi corretta successivamente.
- Run `39490272717`, commit `89a3ae9`: errore nel nuovo test foto (confrontava punti con pixel del renderer 2×); aspettativa corretta in `ab1c321`. Anche il test UI testo Pencil è fallito nuovamente: resta intermittente, non risolto. Aggiunti screenshot e gerarchia AX da conservare prima dell’asserzione nella prossima esecuzione.
- Run `39515889190`, commit `ab1c321`: **nessun job avviato**. GitHub segnala pagamenti recenti falliti o limite di spesa da aumentare nelle impostazioni Billing & plans. Nessuna modifica a pagamenti/limiti e nessuna nuova esecuzione dispendiosa sono state avviate per aggirarlo.

## Controlli ancora aperti

Compilazione Apple delle modifiche successive ad `ab1c321`; difetto intermittente del campo testo; fotocamera/scanner/Pencil fisici; prestazioni della gomma con grafia densa; registrazioni lunghe e standby nel runner finale; cartella File con provider esterno; CloudKit a due dispositivi; AI reale con hosting e modello configurati. Firma e distribuzione richiedono anche chiave privata e profilo: il solo certificato `.cer` pubblico non firma l’app.

I file originali e le copie parziali vengono conservati nel recupero di una sostituzione interrotta. La compatibilità del catalogo rimane v1 con campi opzionali; la struttura SwiftData della libreria non è stata cambiata.

## Difetti aggiuntivi corretti durante la verifica

- Taglia eliminava anche dopo copia rifiutata per dimensione; duplica poteva incollare una selezione precedente. Le operazioni dipendono ora dall’esito della copia.
- Le immagini copiate avevano soltanto un riferimento al file originale. Ora gli appunti interni possiedono una copia temporanea dei media entro il budget complessivo di 32 MB; la copia resta valida se il sorgente viene pulito/rimosso e durante un incolla asincrono anche se un’altra finestra cambia selezione. Gli appunti interni non sono un backup persistente dopo il riavvio dell’app.
- Il writer poteva creare cataloghi superiori ai 16 MB accettati dal lettore e vettori/immagini superiori ai 100 MB accettati dall’import. Rifiuto prima di sostituire l’ultima copia leggibile; prova sui byte originali. Le pagine rimappate durante l’unione usano lo stesso writer e il limite JSON è verificato anche prima della lettura di pagine/manifest.
- Risposte/trasferimenti asincroni verificano pagina e input prima dell’inserimento; un gesto iniziato nel frattempo non produce più un inserimento silenziosamente saltato nel drop.
- La cache dei fogli vicini ora contabilizza anche il disegno della pagina appena lasciata e rilascia i vettori più pesanti conservando le miniature. I/O/prefetch serializzati; 48 MB è un budget stimato, non una misura del consumo totale dell’app.
- I quiz normalizzano la precisione delle date al formato persistito, evitando il rifiuto di un progresso valido dopo la rilettura del catalogo.
- Indici PDF negativi o al limite di overflow vengono rifiutati dal writer/importatore; il renderer verifica anche il numero reale delle pagine prima della conversione dell’indice. Prova di rifiuto senza modificare la pagina precedente.
- Durante la preparazione di una nuova selezione la Lente poteva conservare fonti precedenti: ora le svuota e blocca l’invio; una modifica della pagina richiede aggiornamento. Richieste in corso conservano selezione e configurazione iniziali.
- Un errore nel salvataggio poteva nascondere un risultato AI valido: lookup, ricerca e chat mostrano prima il risultato e segnalano separatamente il mancato salvataggio. Scrittura della cache facoltativa; citazioni web conservate anche in clone e unione.
- Il compilatore Linux ha rilevato una catena di espressioni troppo complessa nella disposizione delle citazioni: sostituita con passaggi tipizzati; la suite è poi passata. Il ritaglio degli indici Unicode evita di spezzare emoji composte.
- Un cerchio chiuso nello strumento Lente poteva produrre un ritaglio vuoto usando soltanto i due estremi: ora considera tutta la traccia, con prova del cerchio e della sottolineatura inversa. Il test UI Audio scorre esplicitamente fino al comando e conserva evidenze se non è azionabile; nuova prova di archivio/ritorno ai recenti predisposta, non eseguita.

Le parti residue del piano sono elencate senza convertirle in completamenti nell’[audit](CLAUDE_PLAN_AUDIT.md). Nessuna nuova esecuzione CI è stata forzata per aggirare il blocco di fatturazione.
