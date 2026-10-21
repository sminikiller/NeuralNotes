# NeuralNotes 0.12.0, build 22 — audio e Lente rapida

Anteprima dei sorgenti e App Playground. La compilazione e la prova Apple delle modifiche recenti restano aperte: la CI non avvia i job per il blocco di fatturazione GitHub e non c’è un iPad controllabile da questa sessione. [Report delle prove](ROADMAP_VALIDATION.md), [piano completo e voci residue](CLAUDE_PLAN_AUDIT.md).

## Audio e trascrizioni

Audio → **Recenti / Archivio / Cestino**, con ricerca per nome e ordinamento stabile per data. Il menu della lezione permette di archiviare, ripristinare o cancellare soltanto la trascrizione. Il cestino conserva i file e occupa ancora spazio; non è una cancellazione fisica nascosta. Le operazioni sull’archivio richiedono che registrazione e trascrizione siano terminate.

**Esporta audio e trascrizione** prepara file indipendenti e apre la condivisione di sistema: scegliere Salva su File. Include le parti audio originali, senza ricodificarle, `.txt` corretto con timestamp, `.md` per capitoli, playlist `.m3u8` e metadati `.json`. Se la registrazione è stata interrotta o ripresa, le parti restano separate e ordinate per numero/timestamp. Non è un singolo M4A unito. Se non c’è testo riconosciuto, esporta comunque audio e metadati.

La copia usa blocchi da 1 MB, verifica dimensioni e spazio disponibile e conserva gli originali quando fallisce o viene annullata. I file temporanei restano fino alla chiusura della condivisione. Per trasferire anche pagine, inchiostro, anchor e impostazioni usare il backup completo `.nnbackup` del quaderno: l’export audio è destinato all’uso esterno.

La prova locale multiore usa **otto ore sintetiche, 640 finestre**, con riapertura dopo 120 checkpoint e verifica dell’ultima parte e delle correzioni. Non è una prova di otto ore di Apple Speech, di microfono reale o di standby. La registrazione/trascrizione fisica e le prestazioni sul runner iPad restano da misurare.

Predisposto anche un XCTest Apple con file WAV sparso di sei ore: lettura della durata e dei frame finali, interruzione del controller dopo 120 finestre, ricreazione e ripresa delle 360 mancanti, correzioni e timestamp finali. Il riconoscimento è iniettato e il test non è ancora eseguito: non dimostra la qualità di Apple Speech.

## Lente rapida

Selezionare testo digitato → **Apri nella Lente AI**. Con lo strumento Lente si può toccare, cerchiare un’area oppure sottolineare il termine. Si apre il popup, espandibile nel pannello; da lì si scelgono spiegazione, definizione o altre azioni. La penna normale mantiene il comportamento di scrittura.

La scheda del termine offre **Cerca sul web con fonti** quando è configurato un backend. Invia soltanto il termine, richiede consenso e abilitazione web del servizio, mostra citazioni cliccabili e inserisce risposta/collegamenti nel foglio con undo. Hosting e credenziali non sono attivati dalla generazione del pacchetto. [API, login ChatGPT e opzione economica verificati](AI_API_AND_LOGIN.md).

## Pacchetti e conservazione

`.verification/NeuralNotes-iPad-0.12.0.zip` contiene `NeuralNotes.swiftpm`; `.verification/NeuralNotes-Sorgenti-0.12.0.zip` contiene il progetto completo. Sono generati dai sorgenti canonici con controllo dei byte, non sono IPA firmati.

Conservare vecchio Playground e backup: una nuova copia può usare un contenitore dati separato. Importare i quaderni dalla copia precedente prima di abbandonarla. Lo schema SwiftData resta invariato e il formato v1 aggiunge soltanto campi opzionali. Le vecchie versioni possono ignorare nuovi metadati: evitare di alternarle sullo stesso file senza una copia originale.

La Verifica sul dispositivo contiene 33 controlli, inclusi due nuovi su export/organizzazione audio e geometria/collegamenti della Lente senza rete. Sono predisposti, non già eseguiti sul tuo iPad. Il difetto intermittente del campo testo rimane aperto finché non sarà verificato con gli strumenti Apple.
