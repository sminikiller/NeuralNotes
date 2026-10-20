# NeuralNotes backend personale — 0.3

Server Node 22+ senza dipendenze npm. Implementa `POST /v1/study` secondo il contratto dell’app e un adapter reale per la Responses REST API con output JSON strutturato. Il modello è una configurazione obbligatoria: non viene scelto un modello a pagamento automaticamente. Non vengono eseguite chiamate provider durante i test.

## Esecuzione su un server proprio

Impostare nell’ambiente server `NN_PROVIDER_KEY`, `NN_MODEL` (un modello accessibile al proprio account con supporto Structured Outputs) e `NN_AUTH_SECRET` (segreto casuale di almeno 32 caratteri). Non inserire queste variabili nel progetto iPad o in file versionati. Eseguire `node backend/server.mjs` sul computer/server di hosting. L’ascolto predefinito è `127.0.0.1:8787`.

Esporre il server attraverso un reverse proxy **HTTPS**, con limite body 256 KB e timeout maggiore di 65 secondi. Configurare quindi nell’app l’URL pubblico completo terminante con `/v1/study`. Il server non configura dominio, certificato o account di hosting da solo.

Con lo stesso `NN_AUTH_SECRET`, eseguire `node backend/issue-token.mjs nome-utente` e copiare il token emesso nel pannello AI dell’app. Questo token dura 24 ore; contiene solo soggetto e scadenza firmati HMAC. Non è la chiave del provider. Ruotando il segreto si revocano tutti i token. Un servizio multiutente con login e revoca individuale richiede un identity provider separato.

Opzionali: `PORT`, `NN_MAX_OUTPUT_TOKENS` (256–8192, default 4096), `NN_UPSTREAM_URL` (endpoint HTTPS che implementa lo stesso contratto Responses), `NN_PROVIDER_NAME`. Altri adapter possono essere iniettati in `createApp` implementando `generate(request, signal)`; non sono dichiarate integrazioni con provider non verificati.

## Comportamento

- Validazione task, UUID e riferimenti, 1–40 chunk, massimo 80.000 caratteri di fonti e 4.000 di domanda.
- Il modello restituisce indici delle fonti; il server ricostruisce i riferimenti copiandoli dalla richiesta e rifiuta indici fuori ambito. Questo non dimostra che tutte le affermazioni siano supportate: servono valutazioni di qualità.
- Nessun archivio, database, cookie o log dei contenuti sul server applicativo. `store: false` nella chiamata Responses. Le politiche di conservazione del provider e del reverse proxy restano separate e vanno verificate dall’operatore.
- Timeout upstream, cancellazione quando il client si scollega, rifiuto dei redirect, limite risposta 2 MB, massimo quattro richieste attive globali.
- Limiti per utente: dieci richieste/minuto e cento/giorno. Sono in memoria, per singolo processo, e si azzerano al riavvio; per più istanze o quote di produzione serve uno storage condiviso. Configurare anche limiti di spesa sull’account provider.
- Errori di autenticazione, quote, rifiuto o output incompleto non diventano risposte simulate. Nessun costo o richiesta esterna avviati per consegnare questo codice.

## Verifica

`node --test backend/server.test.mjs`

I test usano un transport stub dichiarato e richieste HTTP su loopback: verificano autenticazione/scadenza, limiti, validazione fonti, citazioni, rifiuti, risposte incomplete e contratto HTTP. L’adapter live, l’hosting HTTPS e il collegamento dall’iPad richiedono credenziali e una prova separata. Il backend non viene avviato in background o distribuito automaticamente.

Contratto REST verificato nella [documentazione ufficiale OpenAI sugli output strutturati](https://developers.openai.com/api/docs/guides/structured-outputs). Il campo `text.format` usa JSON Schema strict e la richiesta usa la Responses API.
