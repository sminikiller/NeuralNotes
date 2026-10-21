# Verifiche della lavorazione successiva alla 0.9.1

Branch: `codex/editor-reliability-and-roadmap`. Non è una dichiarazione di completamento di tutta la roadmap o di pubblicazione su App Store.

## Prove locali del 21 ottobre 2026

- Swift 6.1.2 Linux, immagine ufficiale `swift:6.1.2`: **125 XCTest, due esclusioni già previste dall’ambiente, zero errori; 98 Swift Testing FSRS passati**. Include recupero snapshot interrotti, identità e media dei quaderni, sezioni cicliche/profonde, assegnazione pagine, collegamenti diretti/inversi, clone/unione, statistiche e ora legale, trascrizione sintetica di tre ore, correzioni autorevoli e stato parziale esplicito.
- Backend Node: **16 test passati**, comprese schede `/v1/lookup`, citazioni, autenticazione, quote, streaming interrotto e risposta incompleta. Nessuna chiamata a pagamento.
- Controllo progetto: **344 oggetti, 209 file Swift analizzati, 235 metodi XCTest individuati**. La grammatica non equivale a type checking, compilazione o esecuzione dei test Apple.

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
