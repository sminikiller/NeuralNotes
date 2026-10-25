# Privacy e assistenza: contenuti da finalizzare prima del rilascio

Questa è una scheda tecnica per preparare le pagine pubbliche e le dichiarazioni App Store, non un’informativa legale già valida. Non inventare titolare, recapiti, durata di conservazione o accordi con fornitori.

## Flussi effettivi da dichiarare

| Funzione | Dati | Destinazione e controllo |
| --- | --- | --- |
| Scrittura locale | Quaderni, immagini, audio, trascrizioni e impostazioni | Contenitore dell’app; nessun account necessario |
| Account email | Email, identificativo utente, nome visualizzato facoltativo | Supabase Auth/database e provider SMTP configurati dall’operatore |
| Cloud NeuralNotes | Quaderni caricati, versioni, checksum, date e titolo | Storage privato e database; associati all’account |
| Quote AI | Identificativo e contatori d’uso del servizio | Database per quote giornaliere/mensili |
| Richiesta AI | Domanda e contenuto scelto; testo ricavato dalle immagini nelle azioni previste | Gateway e provider configurato. Non dichiarare il provider come attivo prima della verifica |
| Ricerca web | Termine selezionato per la ricerca | Provider e motore di ricerca configurati; è distinta dall’invio delle fonti del quaderno |
| iCloud | Copie dei quaderni esplicitamente sincronizzati | Account Apple dell’utente, separato dall’account NeuralNotes |
| Assistenza | Quanto l’utente invia volontariamente | Canale che sarà effettivamente pubblicato |

Il gateway non aggiunge log delle domande/risposte nel codice applicativo; ciò non dimostra assenza di log presso hosting, SMTP, database e provider. Verificare le loro policy, regioni, contratti e impostazioni. Gli archivi cloud possono includere foto e audio anche se l’utente non li invia direttamente all’AI.

## Manifest e dichiarazioni Store

Il manifest predisposto dichiara nome, email, User ID, contenuti dell’utente, foto/video, audio e interazioni per le funzionalità dell’app; dati collegati all’utente, tracking disabilitato. Il solo uso locale non invia questi dati al backend. Il manifest non sostituisce il questionario privacy di App Store Connect né la verifica dei fornitori effettivi. Controllare anche log tecnici/indirizzi IP e contatti di assistenza quando vengono attivati.

## Conservazione e cancellazione

- L’utente può esportare i dati dell’account e richiederne la cancellazione dall’app, previa conferma email.
- La cancellazione online è riprendibile e rimuove gli oggetti Storage prima dei dati dell’account; le copie locali/iCloud restano separate.
- Le versioni cloud occupano quota: non dichiarare una retention temporale automatica finché non è implementata e configurata.
- Documentare separatamente retention dei backup database, log hosting, SMTP e provider AI. Non promettere cancellazione istantanea di copie gestite da terzi.
- Configurare un canale per assistenza, richieste sui dati e gestione di cancellazioni rimaste incomplete.

## Pagine pubbliche necessarie

**Privacy:** identità e contatto dell’operatore, scopi, categorie, fornitori/regioni, conservazione, cancellazione e modalità di esercizio delle richieste. Includere condivisione con il provider AI e limiti della trascrizione/ricerca online effettivamente attive.

**Assistenza:** recapito funzionante, guida ai backup e ripristino, versioni supportate, istruzioni per segnalare errori senza allegare appunti personali e percorso di cancellazione account. Il canale non è creato da questo documento.

Le URL HTTPS vanno inserite con `tools/configure_service.py --privacy-url ... --support-url ...` soltanto dopo la pubblicazione. App Store Connect e app devono mostrare la stessa informativa.
