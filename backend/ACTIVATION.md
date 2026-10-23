# Attivazione account e AI — backend 0.6 / app 0.21

## Stato effettivo

Il backend e l’accesso email sono implementati. I servizi Auth/PostgREST/database/email sono stati provati realmente **in locale**, con due identità e TLS verificato; DeepSeek era sostituito da una fixture. Non esiste ancora un URL pubblico configurato nel pacchetto. I collegamenti Supabase/Render e la chiave privata DeepSeek non sono disponibili nella sessione; nessuna infrastruttura a pagamento è stata creata.

## Configurazione di destinazione

1. Progetto Supabase: applicare `platform/schema.sql` a un database nuovo. È una migrazione iniziale, non idempotente: non rilanciarla su dati esistenti. Configurare Auth email e SMTP di produzione. Il template deve contenere `{{ .Token }}` per mostrare il codice da inserire nell’app. Non applicare i bootstrap di test. [Guida OTP ufficiale](https://supabase.com/docs/guides/auth/auth-email-passwordless).
2. Render: il blueprint `deploy/render.yaml` descrive il gateway Docker sul branch corrente, health check e variabili. Registrare `NN_PROVIDER_KEY` nel gestore segreti del servizio; impostare `NN_SUPABASE_URL` e la publishable/anon key. La service-role key non serve al gateway. [Blueprint Render](https://render.com/docs/infrastructure-as-code), [riferimento](https://render.com/docs/blueprint-spec).
3. Il blueprint usa il piano gratuito per staging. Dopo 15 minuti di inattività Render sospende le istanze gratuite e il risveglio può richiedere circa un minuto: non offre risposte immediate costanti. Per produzione servirà valutare un’istanza sempre accesa e un budget, senza attivare acquisti automaticamente. [Limiti ufficiali](https://render.com/docs/free).
4. DeepSeek richiede una chiave API server. Il gateway usa l’adapter già presente e il modello configurabile; account/app e chiave provider sono separati. Prima del rilascio verificare disponibilità del modello e ricerca sull’account reale. [API ufficiale](https://api-docs.deepseek.com/api/deepseek-api/).

Con variabili presenti nell’ambiente del processo, dalla radice:

```powershell
node backend/preflight.mjs
node backend/preflight.mjs --live-model
```

Il primo comando controlla i nomi delle variabili e l’accessibilità Auth senza stampare valori. Il secondo esegue anche una richiesta DeepSeek limitata a 256 token su testo sintetico; può consumare credito provider. Non invia appunti. Nessuno dei due è una prova completa di SMTP, Storage o app iPad. Nella sessione è stato eseguito solo il primo: variabili mancanti, nessuna chiamata live.

Quando il gateway HTTPS è effettivamente disponibile:

```powershell
python tools/configure_service.py --origin https://HOST-DEL-GATEWAY
python tools/generate_project.py
python tools/package_ipad.py
```

Sostituire l’host con l’URL reale. Lo script verifica `/v1/config`, modalità gestita, origine Auth e tipo di chiave pubblica; aggiorna entrambi i plist solo dopo la verifica. Non riceve né scrive chiavi private. Un URL da solo non dimostra che il modello o SMTP funzionino. Nel pacchetto attuale questo collegamento non è stato eseguito perché manca un servizio pubblico disponibile.

## Ripetere i test locali

Node 22+, Docker Desktop attivo, OpenSSL disponibile (anche quello di Git per Windows):

```powershell
node --test backend/*.test.mjs
node backend/integration/run.mjs
```

La seconda prova crea container isolati, porte solo su loopback, segreti casuali e un certificato temporaneo per localhost. Usa GoTrue, PostgreSQL, PostgREST e Mailpit reali. Nessuna email esterna: indirizzi `.invalid`. Il modello è una fixture esplicita. Nel `finally` elimina container, volumi e file temporanei di configurazione/chiave. Non modifica il trust store di sistema; solo il processo di test riceve la CA locale. La cartella `.verification` non deve essere pubblicata. Storage API v1.81.0 è ora un servizio reale locale con filesystem e migrazioni proprie, configurato seguendo il [compose ufficiale Supabase](https://github.com/supabase/supabase/blob/master/docker/docker-compose.yml). Le prove includono prenotazione, upload immutabile, CAS, URL privato firmato, download identico, isolamento, cancellazione fisica e rifiuto dei token residui dopo eliminazione. Il provider AI resta una fixture; nessun progetto Supabase ospitato è stato verificato.

## Lavoro ancora aperto per il rilascio

Prova live provider e SMTP, prova account/Keychain e popup sull’iPad, monitoraggio e budget, backup database, pulizia oggetti e retention, moderazione e controlli dei materiali condivisi. La community nativa, la coda durevole e l’interfaccia per i conflitti esistono; restano verifica pubblica, completa sincronizzazione bidirezionale tramite account e suddivisione dei grandi oggetti. Abbonamenti/pagamenti restano disabilitati; i piani esposti sono proposte. Il PDF locale da 1 GiB non alza il limite cloud di 100 MiB per oggetto.


## Aggiornamento 0.21.0: account e controlli di pubblicazione

Dopo la migrazione iniziale applicare **in ordine e una volta** tutti i file SQL di `platform/migrations/`. Su un database già esistente applicare solo queste migrazioni: non rilanciare `schema.sql`, non applicare i bootstrap di test. La 001 aggiunge il ciclo di cancellazione e blocca nuovi caricamenti durante la rimozione; la 002 restituisce i conflitti semantici come HTTP 409, evitando i ritentativi di PostgREST sulle serializzazioni `40001`; la 003 espone solo il numero pubblico del contratto.

`/health` misura il processo; `/ready` restituisce 200 soltanto con il contratto database atteso. Il blueprint usa `/ready`. Il preflight controlla anche email Auth abilitata e migrazioni; la prova live del provider resta un passo distinto e richiede la chiave nel servizio di hosting. SMTP pubblico richiede mittente/dominio configurati e una prova di consegna reale.

L’app aggiunge Account NeuralNotes nella libreria, nome visualizzato, esportazione JSON paginata e cancellazione con nuovo codice email. La cancellazione procede a gruppi di 100 oggetti via Storage API e riprende dopo interruzione; solo alla fine elimina metadata e Auth. I token già emessi sono rifiutati dalle policy quando l’utente non esiste più. Materiali di terzi in un gruppo di proprietà impediscono la cancellazione finché la proprietà non è trasferita (`POST /v1/platform/hubs/transfer`). Nessuna service-role key è necessaria al gateway. Quaderni locali e copie nel separato account Apple non vengono cancellati.

La coda di upload e i relativi file sono separati per account **e** origine del gateway. Le vecchie code senza identità rimangono conservate e non sono assegnate automaticamente a chi accede: ripetere il backup dalla libreria. Gli originali locali rimangono disponibili. I checkpoint iCloud sono separati per utente Apple; il cambio account invalida cache e conflitti.

Prove ripetibili senza credenziali reali: `npm --prefix backend test`, `pwsh -File backend/platform/verify.ps1`, `node backend/integration/run.mjs`. La CI esegue ora tutte e tre, senza chiamate a modelli a pagamento.
