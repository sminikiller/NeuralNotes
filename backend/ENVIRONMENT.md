# Avvio del backend gestito 0.5

Richiede Node 22 o successivo, un progetto Supabase e un reverse proxy HTTPS con buffering disabilitato per NDJSON. Il server non è distribuito da questa consegna. Non inserire segreti nei sorgenti, nel Playground o in `/v1/config`.

Blueprint, verifica delle variabili, collegamento dell’app e test account reali locali sono descritti in [ACTIVATION.md](ACTIVATION.md). Nessun endpoint pubblico è stato attivato.

## Configurazione server

| Variabile | Uso |
|---|---|
| `NN_PROVIDER` | `deepseek` predefinito, oppure `responses` |
| `NN_PROVIDER_KEY` | Chiave privata del provider, solo sul server |
| `NN_MODEL` | Modello; DeepSeek predefinito `deepseek-flash` |
| `NN_MAX_OUTPUT_TOKENS` | DeepSeek, predefinito 2048, intervallo 256–8192 |
| `NN_ENABLE_WEB_SEARCH` | `1` abilita ricerca; disabilitata altrimenti |
| `NN_SUPABASE_URL` | Origine HTTPS del proprio progetto |
| `NN_SUPABASE_PUBLIC_KEY` | Publishable key o vecchia anon key; service role rifiutata |
| `NN_AUTH_SECRET` | Solo modalità personale senza Supabase, almeno 32 caratteri |
| `NN_BIND` / `PORT` | Predefiniti 127.0.0.1 / 8787; nel container bind 0.0.0.0 |

Non serve fornire la service role all’API: le operazioni inoltrano il token utente a PostgREST/Storage e rispettano RLS. Il segreto HMAC non sostituisce gli account nella modalità gestita. `npm start` usa `start.mjs`; il vecchio `server.mjs` conserva il percorso personale precedente. L’app dalla 0.18 supporta accesso email con codice e rinnovo della sessione, dopo il collegamento a un gateway pubblico verificato. Non esiste un account autenticato automaticamente nel pacchetto.

Applicare `platform/schema.sql` una volta in un progetto Supabase nuovo, con privilegi di amministrazione database. È una migrazione iniziale, non uno script idempotente per database già popolati. Non applicare `test-bootstrap.sql` sul servizio: serve esclusivamente alle fixture locali. Configurare Apple/email nell’Auth del servizio separatamente. Installazioni e migrazioni remote non sono state eseguite.

Avvio locale: impostare le variabili nell’ambiente del processo e lanciare `npm start` dalla cartella backend. In produzione mettere TLS davanti al server, limiti di traffico e di connessioni a livello proxy, monitoraggio senza contenuti privati e budget provider. `Dockerfile` include il gateway senza dipendenze npm esterne e gira come utente node. Nessuna password viene richiesta o memorizzata dal gateway.

## Contratto

`GET /v1/config` è pubblico: provider key e segreti esclusi, elenco dei piani espressamente proposti, `subscriptionsActive: false`. Le altre chiamate richiedono `Authorization: Bearer <access token utente>`; Auth verifica l’utente sul servizio prima di eseguire operazioni.

AI: `/v1/study` con JSON o NDJSON, `/v1/lookup`, `/v1/quiz`, `/v1/research`. Formati e citazioni restano quelli descritti in README. La quota si addebita solo dopo validazione della richiesta, ma prima dell’inferenza; errori provider/cancellazioni non rimborsano automaticamente. Contesto lungo costa più crediti, ricerca otto. Quote atomiche per giorno/mese UTC nel database, senza fidarsi di un piano dichiarato dal client.

Sotto `/v1/platform/`:

- `GET account`, `POST profile`: identità/piano/alias privato.
- `GET/POST hubs`: sezioni e creazione con autore derivato dall’accesso.
- `GET resources?hub=<uuid>` oppure `?mine=1`: massimo 50, offset fino a 10000 e tag facoltativo. `POST resources`: materiale in attesa, mai direttamente pubblicato dal client.
- `POST moderate`, `POST reports`, `POST blocks`: pubblicazione/nascondimento autorizzati, segnalazioni e blocco.
- `POST invites`, `POST join`: token casuale, digest salvato, scadenza e utilizzi limitati.
- `POST uploads`: prenota oggetto privato da 1 byte a 100 MiB. Restituisce URL di upload autenticato, non un URL anonimo; il client usa access token utente e publishable key. Nessun upsert; path nuovo per revisione.
- `GET documents`, `POST commit`: elenco e commit cloud con `expectedRevision`, checksum e dimensione. Conflitto 409, revisione precedente conservata.
- `GET download?resource=<uuid>` oppure `?document=<uuid>`: URL privato valido 60 secondi dopo verifica dei permessi.

I payload esatti sono nei validatori di `platform.mjs` e nei test. RTF/pagine/inchiostro non vengono trasformati dal server. Il commit richiede un oggetto già caricato, dimensione effettiva corrispondente e prenotazione. File immutabili, limite per account, massimo 32 prenotazioni in attesa e scadenza un’ora. Nessuna cancellazione automatica degli oggetti o retention è ancora implementata: non lasciare il servizio pubblico senza completare la gestione operativa dello spazio.

## Verifiche e lavoro aperto

Da radice: `node --test backend/*.test.mjs` (41 passati). SQL: `powershell -NoProfile -ExecutionPolicy Bypass -File backend/platform/verify.ps1`, richiede Docker e PostgreSQL 16 Alpine; crea un container temporaneo senza porte pubblicate e lo ferma in finally. Auth/Storage sono fixture di schema; PostgreSQL/RLS/RPC sono reali. Il test non chiama Supabase né provider AI live.

Nuovo `node backend/integration/run.mjs`: Auth/email/PostgREST/database reali locali, provider AI simulato. Storage HTTP non verificato. [Dettagli](ACTIVATION.md).

Prima del rilascio: test end-to-end Auth/Storage ospitati, gestione account/cancellazione, backup database, pulizia prenotazioni/file abbandonati, retention snapshot, moderazione e scansione file, limiti di abuso, pagamento verificato e native UI/outbox. Le route presenti non implicano che tutte queste funzioni siano pronte per produzione. [Piano](../docs/AI_COMMUNITY_PLAN_0_17.md).
