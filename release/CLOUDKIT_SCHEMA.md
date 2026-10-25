# CloudKit — schema richiesto dalla build firmata

Derivato dal codice `NeuralNotes/Infrastructure/Persistence/CloudNotebookSync.swift`. Non attiva un container sul portale Apple.

Team atteso: `64R668842U`. App ID: `com.lorenzominichilli.neuralnotes`. Container: `iCloud.com.lorenzominichilli.neuralnotes`. Il codice usa il **database privato dell’utente**, non un archivio pubblico condiviso.

| Record type | Campo | Tipo |
| --- | --- | --- |
| `NNLibrary` | `books` | List of String |
| `NNNotebook` | `chunks` | List of String |
| `NNNotebook` | `previousChunks` | List of String |
| `NNNotebook` | `digest` | String |
| `NNNotebook` | `title` | String |
| `NNNotebook` | `updated` | Date/Time |
| `NNChunk` | `asset` | Asset |

L’indice usa il record ID `library.v1`; ogni quaderno usa il proprio UUID, i frammenti `chunk.<UUID>`. Il codice legge i record per ID, senza una ricerca per campo personalizzato. Non abilitare lettura pubblica dei record per far funzionare il collaudo.

Percorso operativo: associare App ID e container nel team Apple; verificare lo schema nell’ambiente Development usando una build di sviluppo firmata; distribuire lo schema in Production dal CloudKit Console; usare un profilo App Store Connect con CloudKit Production per TestFlight. Verificare poi invio, ricezione, conflitto e cambio account su due dispositivi reali.

Gli archivi vengono trasferiti in frammenti da massimo 8 MiB, mantenendo temporaneamente anche i frammenti della revisione precedente. Le quote iCloud dell’utente restano applicabili. Non confondere questa implementazione con il cloud account Supabase, che usa un limite di 100 MiB per quaderno.

Il simulatore rifiuta esplicitamente questa connessione nell’app. Una compilazione senza firma o la copia dell’entitlement nel progetto non dimostrano che il container sia attivo.
