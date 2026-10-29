# NeuralNotes 0.25 — Crediti e strumenti forma

## Stato
Verifica completa superata sul commit b64b2d6820945042f51707836dbd3a3bbc6f69f5. Beta interna 1.0.0 (128) firmata e caricata su Apple il 29 ottobre 2026. Il comando di upload è riuscito; elaborazione e disponibilità su TestFlight restano di competenza Apple.

## Contenuto
- Informazioni su NeuralNotes dalla libreria e da Account e servizi: logo AppLogo derivato dall’icona, autore, ringraziamenti, versione/build reali, copia di informazioni tecniche senza dati dei quaderni, privacy in breve e licenze.
- Email feedback configurabile con `python tools/configure_service.py --feedback-email INDIRIZZO`; non occorre configurare un backend per aggiungerla. Senza email le azioni mail sono nascoste. Assistenza e privacy mancanti mostrano un messaggio.
- Per i ringraziamenti modifica solo `NeuralNotes/Resources/Credits.json`: `{"names": ["Nome", "Altro nome"]}`. Il file iniziale è vuoto.
- Rombo, poligoni regolari e liberi, stelle e archi; geometria vettoriale condivisa da rendering, selezione, miniature e PDF.
- Stile: contorno, riempimento/opacità, tratteggio/puntini, angoli arrotondati, punte aperte/piene. Applicazione multipla e predefinito nel Workspace.
- Maniglie di dimensione e rotazione; estremi, raggio interno, curvatura e vertici secondo la forma. Il poligono libero permette aggiunta/rimozione dei vertici con pressione prolungata.
- Riconoscimento con attesa o al rilascio, forme abilitate e output modificabile/inchiostro. Con la penna il risultato predefinito è modificabile; con l’evidenziatore viene raddrizzata solo la linea.
- Annulla della correzione ripristina l’inchiostro originale; l’annulla successivo rimuove il tratto. L’ancoraggio audio è trasferito e la riproduzione nasconde anche le forme fino al loro tempo.
- Angoli di 15°, proporzioni 1:1 e punti di collegamento alle forme; indice spaziale dei candidati costruito all’inizio del gesto.

## Compatibilità e prestazioni
I nuovi campi di forme e Workspace sono opzionali. Tipi di forma e stili futuri sconosciuti hanno un ripiego sicuro. Nessuna migrazione distruttiva di file, nessun aggiornamento di bundle/container/team o segreti di firma. Fixture JSON e immagine del formato 0.24.1 in `Tests/Fixtures/0.24.1`: lettura, risalvataggio, backup/import e PDF nei test Apple. Le figure vecchie mantengono contorni, punte aperte e assenza di riempimento.

Il riconoscimento ricampiona in 64 punti; i test controllano anche 2.000 campioni e query spaziali con migliaia di candidati. Non si può dedurre il limite fisico di 16 ms o 60 fps sull’iPad 10 dai soli tempi del runner CI. Rimane il collaudo fisico di grafia reale per i falsi positivi. La modalità con attesa resta il predefinito prudente.

## Licenze e risorse
La sola libreria di terze parti inclusa nel binario iOS è swift-fsrs, vendorizzata con licenza MIT già riportata in ThirdPartyNotices.txt. swift-crypto è condizionata a `#if os(Linux)` nel Package.swift: iOS usa CryptoKit del sistema. Nessuna nuova dipendenza. Credits.json, licenze e AppLogo sono inclusi sia nel target Xcode sia nel pacchetto Playgrounds.

## Versioni e distribuzione
Generatore e pacchetto iPad: 0.25.0, build sorgente 53. La corsia TestFlight esistente assegna autonomamente versione commerciale 1.0.0 e numero progressivo di esecuzione; non viene modificata. La schermata Informazioni mostra sempre i valori effettivi del bundle, non quelli scritti in questo documento. Link e build effettivi saranno aggiunti dopo le verifiche.

## Verifica conclusiva del 29 ottobre
- [Verifica completa 40815806130](https://github.com/sminikiller/NeuralNotes/actions/runs/40815806130): tutti e sei i job verdi (portable, backend-services, upgrade, playground, apple, distribution).
- Core macOS: 306 XCTest e 98 Swift Testing superati. iPad: 456 XCTest eseguiti, 2 saltati, nessun errore, più 98 Swift Testing superati. Tutti i 32 test UI superati.
- Fixture del formato precedente: apertura, salvataggio, riapertura, PDF e backup nativo superati. Passano anche annulla/ripristina del riconoscimento e delle ancore audio, stile e riempimento effettivo nel PDF, replay senza modificare i dati.
- Compilazione iOS Release e archivio non firmato riusciti. Il pacchetto Playgrounds della verifica è compilato per simulatore e dispositivo e supera 60 osservazioni di avvio nel simulatore.
- Screenshot controllati: Informazioni in tema realmente scuro e chiaro, orientamento verticale e orizzontale; stella con riempimento e comandi di selezione.
- Pacchetto esatto della CI: NeuralNotes-iPad-0.25.0.zip; SHA-256 `27b1f07776070a38db51677e0a528c4f04ef9511f492b2d2695e9c94329b0fb5`.
- Backend: prove locali SQL/Auth/Storage superate; provider AI simulato. Questi risultati non attestano servizi di produzione.
- Firma e caricamento TestFlight: [40875248301](https://github.com/sminikiller/NeuralNotes/actions/runs/40875248301), riuscito sul medesimo commit verificato: `EXPORT SUCCEEDED` e `UPLOAD_COMMAND_SUCCEEDED`.

## Fasi successive
0.26–0.31: aggancio completo a griglia/allineamento, connettori persistenti, goniometro e gomme per tipo, testo/zoom di scrittura, livelli e riordino della grafia. Ogni fase viene verificata e consegnata prima della successiva. Non incluse GIF, collaborazione in tempo reale o grafia generata.
