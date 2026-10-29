# NeuralNotes 0.25 — Crediti e strumenti forma

## Stato
Implementazione candidata; verifica Xcode e consegna TestFlight ancora da completare. Non è una dichiarazione di rilascio. La build installata dall’utente resta la 1.0.0 (120) finché non viene completata una nuova pubblicazione.

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

## Prove iniziali
- Controlli di struttura, appartenenza dei sorgenti e grammatica Swift: superati localmente, non equivalgono a compilazione SDK.
- 9 test Python di distribuzione e configurazione email: superati.
- Test Core, nativi e UI nuovi: da compilare/eseguire con Xcode.
- Verifica completa e pubblicazione TestFlight: in attesa.

## Fasi successive
0.26–0.31 non iniziate: aggancio completo a griglia/allineamento, connettori persistenti, goniometro e gomme per tipo, testo/zoom di scrittura, livelli e riordino della grafia. Non incluse GIF, collaborazione in tempo reale o grafia generata.

## Collaudo del 29 ottobre — aggiornamento intermedio
- La compilazione Release per iOS e del pacchetto Playgrounds è passata nelle esecuzioni [40792647023](https://github.com/sminikiller/NeuralNotes/actions/runs/40792647023) e [40814055321](https://github.com/sminikiller/NeuralNotes/actions/runs/40814055321).
- Il controllo mirato 40792647023 ha superato i quattro flussi UI selezionati: Informazioni/versione/copia, stella/stile/annulla/ripristina, archivio audio e cambio modalità pagina. I risultati includono screenshot esportati e controllati. Il comando di riempimento è ora un pulsante esplicito.
- Il crash della conversione in forma modificabile è stato riprodotto e corretto: la pagina viene preparata in una copia locale e assegnata in un solo passaggio. Il relativo test nativo di ripristino dell’inchiostro e dell’ancora audio è passato, insieme al controllo del riempimento nel PDF e della riproduzione delle forme con l’audio.
- Nell’esecuzione 40814055321 il gruppo Core è passato prima del simulatore, comprese le nuove prove sui numeri di lati/punte, sulle ellissi allungate e sui punti di collegamento effettivi. Il ricampionamento delle tangenti evita che il rumore di una circonferenza sia interpretato come un poligono.
- Rimaneva un errore nel test nativo della fixture: leggeva il manifest con un JSONDecoder privo della strategia ISO-8601. Il test ora usa l’API canonica DocumentWorkspace.manifest(). L’export del vecchio backup e il suo import erano già passati nei test Core; il test nativo va confermato con questa correzione.
- L’ispezione visiva ha rilevato che il vecchio argomento di lancio non imponeva davvero il tema scuro. Il nuovo test seleziona l’aspetto solo nella build di test, controlla il tema effettivo e cattura l’intero schermo. Le nuove immagini vanno ricontrollate dopo la verifica completa.
- Verifica completa del commit finale e nuova pubblicazione TestFlight ancora da completare. Nessuna nuova beta dichiarata disponibile.
