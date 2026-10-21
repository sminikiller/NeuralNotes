# NeuralNotes backend personale

Server Node 22+ senza dipendenze npm. Implementa `POST /v1/study`, `POST /v1/lookup` e `POST /v1/quiz` secondo il contratto dell’app e un adapter reale per la Responses REST API con output JSON strutturato. Il modello è una configurazione obbligatoria: non viene scelto un modello a pagamento automaticamente. Non vengono eseguite chiamate provider durante i test.

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

## Streaming della Lente AI

`POST /v1/quiz` riceve `{sources, count}` con 1–12 domande e le stesse fonti ammesse da study. Restituisce un `QuizBank` con titolo, identificativi, provider/data e domande: prompt, quattro opzioni distinte, indice corretto 0–3, spiegazione e riferimenti ricostruiti dalle fonti. Citazioni, struttura e limiti sono verificati; questo non dimostra l’esattezza didattica delle risposte. Usa autenticazione, quote, cancellazione e timeout comuni, senza streaming. L’app conserva separatamente il progresso locale e la scadenza dell’esame; nessun progresso viene inviato al server.

La scheda `POST /v1/lookup` riceve `{term, sources}`: termine su una sola riga di massimo 120 caratteri e le stesse fonti ammesse da study. Restituisce `LookupCard` con definizione, spiegazione, fino a cinque esempi e cinque termini correlati, riferimenti, provider e data. Il server verifica che il termine corrisponda, ricostruisce i riferimenti esclusivamente dalla richiesta e controlla le citazioni in tutti i campi. L’endpoint condivide autenticazione, quote, timeout e limite di concorrenza di study; non usa streaming. L’app deriva il percorso `/v1/lookup` dall’URL `/v1/study` configurato e richiede lo stesso consenso. Il dizionario di sistema non richiede il backend.

Con `Accept: application/x-ndjson`, `POST /v1/study` invia un oggetto JSON per riga: `{"type":"delta","text":"…"}`, poi `{"type":"result","artifact":{…}}` soltanto dopo la validazione finale. Un errore dopo l’inizio della risposta è un evento `{"type":"error","code":"…"}` e non un artifact. Il client considera i frammenti provvisori e non li salva se manca il risultato finale. Senza questo header resta disponibile la risposta JSON completa precedente.

L’adapter usa lo streaming reale della Responses API, decodifica SSE anche su confini di byte/Unicode e rifiuta risposte troncate o citazioni non presenti nella richiesta. Il reverse proxy deve inoltrare lo streaming senza buffering; `X-Accel-Buffering: no` è inviato dal server. Interrompere la lettura sul client annulla il segnale upstream.

Contratto verificato sulla [documentazione ufficiale dello streaming Responses](https://developers.openai.com/api/docs/guides/streaming-responses). I test locali usano fixture e HTTP loopback: non provano latenza o qualità di un modello live.

## Verifica automatica

`node --test backend/server.test.mjs`

I diciannove test usano un transport stub dichiarato e richieste HTTP su loopback: verificano autenticazione/scadenza, limiti, validazione fonti, citazioni, definizioni strutturate, quiz e opzioni distinte, rifiuti, risposte incomplete, frammenti Unicode, contratto HTTP con streaming e cancellazione alla disconnessione. L’adapter live, l’hosting HTTPS e il collegamento dall’iPad richiedono credenziali e una prova separata. Il backend non viene avviato in background o distribuito automaticamente.

Contratto REST verificato nella [documentazione ufficiale OpenAI sugli output strutturati](https://developers.openai.com/api/docs/guides/structured-outputs). Il campo `text.format` usa JSON Schema strict e la richiesta usa la Responses API.
