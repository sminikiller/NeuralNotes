# Verifiche della lavorazione successiva alla 0.9.1 — aggiornato alla 0.11.0

Branch: `codex/editor-reliability-and-roadmap`. Non è una dichiarazione di completamento di tutta la roadmap o di pubblicazione su App Store.

## Prove locali del 21 ottobre 2026

- Swift 6.1.2 Linux, immagine ufficiale `swift:6.1.2`: **151 XCTest, 149 superati e due esclusioni già previste dall’ambiente, zero errori; 98 Swift Testing FSRS passati**. Include recupero snapshot interrotti, identità e media dei quaderni, sezioni cicliche/profonde, assegnazione pagine, collegamenti diretti/inversi, clone/unione, statistiche e ora legale, trascrizione sintetica di tre ore, correzioni autorevoli e stato parziale esplicito. Nuove prove: transazione di due pagine e recupero del journal interrotto, rifiuto prima di qualsiasi scrittura per geometria/revisioni/media errati, quiz con scadenza e ripresa/clone, mappa modificabile e fonti, budget della cache, identità Spotlight, fonti fino alla fine di una lezione e budget Unicode, rifiuto di catalogo/file oltre limite conservando byte precedenti, lettura limitata anche per pagine JSON altrimenti valide, immagini copiate indipendenti dal sorgente e rifiuto di media assenti/fuori budget/con percorsi esterni.
- Backend Node: **19 test passati**, comprese schede `/v1/lookup`, quiz `/v1/quiz`, opzioni distinte, citazioni, autenticazione, quote, streaming interrotto e risposta incompleta. Nessuna chiamata a pagamento.
- Controllo progetto: **376 oggetti, 234 file Swift analizzati, 268 metodi XCTest individuati**. In aggiunta, parsing con il compilatore Swift 6.1.2 in modalità Swift 5 per sorgenti app e test Apple. Il parsing non equivale a type checking, compilazione con SDK o esecuzione dei test Apple.

I due skip Linux riguardano gli alias Darwin `/private/var`, assenti su questo host (`testDarwinPrivateVarAliasAllowsNewFiles` e `testDarwinAliasesProduceTheSameArchiveEntryNames`); non sono esclusioni aggiunte per nascondere regressioni. I test con durata di tre ore usano dati sintetici e non una registrazione fisica di tre ore.

I nuovi test Apple coprono taglia rifiutato senza perdita, spostamento misto testo/inchiostro con anchor audio e undo/redo, drop PDF senza note della pagina precedente, localizzazione del testo formattato e laser senza mutazioni, nota rapida con testo e controlli incorporati su documenti temporanei. **Sono presenti ma non eseguiti**. Quattro controlli incorporati aggiunti, 31 totali; una riga «Completato sul dispositivo» compare soltanto se quel controllo viene realmente eseguito e riesce nell’app.

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

Le parti residue del piano sono elencate senza convertirle in completamenti nell’[audit](CLAUDE_PLAN_AUDIT.md). Nessuna nuova esecuzione CI è stata forzata per aggirare il blocco di fatturazione.
