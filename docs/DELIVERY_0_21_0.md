# NeuralNotes 0.21.0 / build 45

## Cambiamenti

- Cambio pagina: annullamento delle anteprime obsolete, rimozione sincronizzata di backing store, livelli di replay/ricerca/selezione e stato degli oggetti; test di regressione con ritorno alla pagina originale. La segnalazione fisica dell’utente non è riprodotta direttamente sul suo iPad.
- Cloud dell’account: prove aggiunte su azioni rimaste aperte e cambi di account durante una prenotazione di upload. Operazioni multiple vincolate all’identità iniziale; code e archivi distinti per utente e servizio; controllo dell’identità dopo gli await, conservazione delle vecchie code non attribuibili, pubblicazione atomica di un nuovo archivio prima di togliere quello sostituito.
- iCloud: checkpoint per account Apple, invalidazione della cache e dei conflitti a cambio utente, verifiche di identità prima di installare una copia scaricata o salvare i chunk. Richiede app firmata e contenitore CloudKit configurato.
- Account accessibile dalla libreria; nome, esportazione JSON a pagine senza caricare tutto in memoria, cancellazione con codice email. La cancellazione rimuove fisicamente i file prima di Auth e riprende se interrotta. Quaderni locali conservati; materiale di altri autori protetto.
- Corretto un timeout reale nella gestione dei conflitti: `40001` causava ritentativi automatici di PostgREST. I conflitti intenzionali ora usano `PT409`.
- Readiness del contratto SQL e tutte le suite Node/SQL/servizi locali nella CI. Nuova prova di aggiornamento del binario con indice SwiftData, manifest e trascrizione della 0.20.8.

## Verifiche

- Node: 53 test passati, inclusa la readiness.
- PostgreSQL reale: quote, RLS, inviti, CAS, cancellazione riprendibile, blocco scritture, isolamento storage, token residui e trasferimento gruppi passati.
- Servizi locali reali: GoTrue/SMTP Mailpit/PostgREST/PostgreSQL/Storage API su TLS locale. Login, refresh, logout, quote, streaming AI con provider simulato, prenotazione/upload/download byte per byte e cancellazione account passati. Nessuna email esterna o inferenza a pagamento.
- Swift Linux 6.1.2: 7 test account/export passati, inclusi JSON multipagina e rimozione del file incompleto.
- Checkpoint Apple 39967055884 / 7b2196d: Core macOS e FSRS passati, tutti i 384 test nativi (due esclusioni per piattaforma) passati, 22/23 UI passati e Release più App Playground compilati. Risolti cinque dei sei vecchi fallimenti; l’ultimo identifica un wrapper di accessibilità del menu audio con un pulsante nativo figlio. Aggiunta una selezione esplicita del figlio interattivo e area di tocco di 44 pt. Verifica della versione finale in corso: risultati e hash ZIP da registrare dopo il completamento.

## Limiti esterni e lavoro ancora aperto

Non sono collegati account Supabase/Render né presenti credenziali del provider nel workspace o nei segreti del repository. Non è pubblicato un endpoint AI/Auth/Storage; la UI non finge un accesso disponibile. Il backend è predisposto e verificato localmente, non attivato in produzione. Le istruzioni ripetibili sono in `backend/ACTIVATION.md`.

Il cloud via account conserva copie e revisioni con conflitti espliciti; non è ancora una replica automatica bidirezionale completa della libreria. Limite per oggetto 100 MiB. iCloud usa chunk e una politica a tre vie, ma non sono verificati contenitore firmato, account Apple reale o modifiche su due dispositivi. Sincronizzazione dei cestini/folder e garbage collection completa delle vecchie copie restano lavori distinti.

Le prove sintetiche di sei ore verificano lettura a finestre, checkpoint, ripresa e timestamp con riconoscitore simulato. Non sostituiscono registrazione di sei ore, Apple Speech reale, standby e fotocamera su iPad. La prova di sostituzione del binario è sul simulatore con una fixture, non prova tutti i quaderni reali dell’utente o il contenitore temporaneo di Swift Playgrounds. Non è stata eseguita cancellazione o migrazione dei dati dell’utente.
