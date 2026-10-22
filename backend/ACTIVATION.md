# Attivazione account e AI — 0.5 / app 0.19

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

La seconda prova crea container isolati, porte solo su loopback, segreti casuali e un certificato temporaneo per localhost. Usa GoTrue, PostgreSQL, PostgREST e Mailpit reali. Nessuna email esterna: indirizzi `.invalid`. Il modello è una fixture esplicita. Nel `finally` elimina container, volumi e file temporanei di configurazione/chiave. Non modifica il trust store di sistema; solo il processo di test riceve la CA locale. La cartella `.verification` non deve essere pubblicata. Le tabelle Storage sono fixture: API Storage/upload/download ospitati non verificati.

## Lavoro ancora aperto per il rilascio

Prova live provider e SMTP, prova account/Keychain e popup sull’iPad, gestione/cancellazione account, monitoraggio e budget, backup database, pulizia oggetti e retention, moderazione e controlli dei materiali condivisi. Community nativa, outbox cloud, conflitti UI e suddivisione dei grandi oggetti non sono completati. Abbonamenti/pagamenti restano disabilitati; i piani esposti sono proposte. Il PDF locale da 1 GiB non alza il limite cloud di 100 MiB per oggetto.
