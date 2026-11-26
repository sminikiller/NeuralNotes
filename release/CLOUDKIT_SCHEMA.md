# CloudKit — schema richiesto dalla build firmata

Team `64R668842U`, App ID `com.lorenzominichilli.neuralnotes`, contenitore `iCloud.com.lorenzominichilli.neuralnotes`. I quaderni vanno nel **database privato dell’Account Apple** configurato sul dispositivo. L’account NeuralNotes per AI e servizi online ha una gestione separata. [Database privato di CloudKit](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase).

## Stato e attivazione

Il 24 novembre 2026 il team ha registrato il contenitore e lo ha associato a NeuralNotes con supporto CloudKit. La console Apple ha confermato il deploy in Production dei tipi NNLibrary, NNNotebook e NNChunk. Il profilo App Store rigenerato con lo stesso certificato autorizza il contenitore e l’ambiente Production. La verifica di distribuzione richiede la build firmata e la prova su due dispositivi con lo stesso Account Apple. [Verifica del profilo e dell’App ID](https://github.com/sminikiller/NeuralNotes/actions/runs/45465239468).

### Procedura di configurazione e rinnovo

1. In **Apple Developer → Identifiers**, crea il contenitore iCloud indicato sopra e associalo all’App ID con **Include CloudKit support**. [Abilitazione delle capability](https://developer.apple.com/help/account/identifiers/enable-app-capabilities).
2. In **CloudKit Console → CloudKit Database**, scegli lo stesso contenitore e crea in **Development** i tre tipi di record elencati sotto. Per automatizzare l’importazione in Development è disponibile anche [NeuralNotes.ckdb](NeuralNotes.ckdb) per `cktool`. Se esistono altri tipi, confronta ed esporta lo schema prima di applicare modifiche. [Schema con cktool](https://developer.apple.com/icloud/ck-tool/).
3. Verifica tipi e campi e usa **Deploy Schema Changes** per portarli in **Production**. [Distribuzione dello schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).
4. Genera un profilo **App Store Connect** per lo stesso App ID e certificato Apple Distribution già valido. Aggiorna `NN_PROFILE_BASE64` con il nuovo profilo. Il resto della firma usa le credenziali già configurate.
5. Esegui la verifica di sola lettura `testflight-status.yml` con `check_icloud=true` sul ramo che contiene il codice iCloud. Deve riconoscere la capability e confermare il profilo Production. La verifica dello schema si fa in CloudKit Console.
6. Usa la corsia interna TestFlight con `scope=testflight`, `testflight_icloud=true` e lo SHA dei sorgenti verificati. La firma controlla contenitore e ambiente. Verifica poi la disponibilità della build in TestFlight.

## Accesso con Apple per l’account NeuralNotes

Per usare **Accedi con Apple** anche per l’account NeuralNotes, abilita **Sign in with Apple** sullo stesso App ID prima di generare il profilo. Nel progetto Supabase del servizio attiva il provider Apple e autorizza il Bundle ID nativo. Configura l’indirizzo HTTPS del servizio tramite `tools/configure_service.py`. Il pulsante appare nelle build distribuite con l’indirizzo configurato e il profilo che consente `com.apple.developer.applesignin`. Il backend Auth verifica il token Apple e il nonce, poi l’app salva la sessione verificata nel Portachiavi. Prova accesso, uscita, rinnovo e cancellazione su un dispositivo con l’account di collaudo. L’accesso al database CloudKit privato usa direttamente l’account iCloud dell’iPad. [Configurazione Apple in Supabase](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple).

## Tipi e campi

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

Gli archivi vengono trasferiti in frammenti da massimo 8 MiB, mantenendo temporaneamente anche i frammenti della revisione precedente. Le quote iCloud dell’utente restano applicabili. Non confondere questa implementazione con il cloud account Supabase, che usa un limite di 100 MiB per quaderno.

Il simulatore rifiuta esplicitamente questa connessione nell’app. Una compilazione senza firma o la copia dell’entitlement nel progetto non dimostrano che il container sia attivo.

## Verifiche dei sorgenti

La candidata ha superato 454 XCTest Core, 98 test Swift Testing, 293 test applicativi, due test UI iPad e la compilazione Release. I test verificano il ripristino di una copia indipendente, il rifiuto di un download quando l’account cambia durante la preparazione e l’accesso ai backup in File se CloudKit non è disponibile. Il pacchetto Playgrounds compila in Debug e i suoi 380 file corrispondono ai sorgenti verificati. [Verifica SDK Apple](https://github.com/sminikiller/NeuralNotes/actions/runs/44296868419).

## Prova su iPad

1. Sul primo iPad, apri **Libreria → Account e servizi → Account Apple e iCloud**. Verifica la connessione e sincronizza un quaderno chiuso con testo, disegno, una foto e un audio breve.
2. Sul secondo iPad con lo stesso Account Apple, usa **Sincronizza tutti i quaderni chiusi**. Apri il quaderno ricevuto e verifica pagine, media e trascrizione.
3. Disattiva la rete, modifica lo stesso quaderno sui due dispositivi e chiudilo. Ricollega un dispositivo alla volta. Il secondo deve mostrare il conflitto e consentire di importare una copia indipendente. Prova anche a scollegare l’Account Apple sul dispositivo di collaudo e verifica che il controllo automatico rimanga inattivo su un account diverso.
4. Esegui un backup da **Salva la copia di un quaderno** scegliendo iCloud Drive. Da **Ripristina una copia da File**, apri il file `.nnbackup` e verifica che ricompaia come quaderno indipendente. Questo percorso è disponibile anche nelle build senza CloudKit che includono il nuovo pannello.

Nella build 212 puoi già esportare da **⋯ → Esporta → Quaderno nativo e backup → Salva su File** e scegliere iCloud Drive. Per aprire la copia usa **Libreria → Importa PDF o quaderno**. Per le copie periodiche, in **Spazio e recupero → Copia in una cartella di File** scegli una cartella in iCloud Drive e mantieni attive le copie automatiche.
