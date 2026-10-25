# Delivery NeuralNotes — percorso operativo

## Stato

Preparazione avviata il 25 ottobre 2026. Versione di collaudo 0.24.1/build 52; l’archivio Store usa 1.0.0 e un numero di build CI distinto. Il vecchio ZIP 0.24.0 resta intatto. Non esiste ancora una pubblicazione TestFlight/App Store o un backend pubblico verificato.

## 1. Verificare SDK e archivio

Il workflow esistente `verify.yml` ha lo scope `delivery`: runner macOS 26, Xcode 26.6, Core, test nativi/UI, aggiornamento del contenitore, backend locale reale, pacchetto Playground Release e avvio, quindi archivio Release per dispositivo. Il normale scope precedente mantiene il compilatore 16.4 per confronto.

```powershell
gh workflow run verify.yml --ref codex/photo-perspective-sync-center -f scope=delivery -f delivery_upload=false
```

Il job distribution salva versione, Bundle ID, SDK, sistema minimo e presenza della firma in `archive-proof.json`. **Un archivio senza firma non è un IPA distribuibile e non è un upload.** Certificati/chiavi/profili non sono salvati negli artefatti. Gli ZIP restano sorgenti per Playgrounds.

## 2. Attivare il backend

1. Creare/configurare Supabase nella regione scelta, Auth email con SMTP reale e template OTP, database e bucket privato. Per un progetto nuovo applicare `backend/platform/schema.sql` poi le migrazioni in ordine; su un database esistente solo le migrazioni ancora da applicare. Mai usare i bootstrap dei test in produzione.
2. Creare il gateway dal blueprint `backend/deploy/render.yaml`. Il piano gratuito è staging, non una promessa di latenza costante. Nessun piano a pagamento viene acquistato automaticamente.
3. Impostare nel gestore segreti dell’hosting `NN_PROVIDER_KEY`, `NN_SUPABASE_URL`, `NN_SUPABASE_PUBLIC_KEY`. La chiave provider non va nel client/repository. Non usare la service-role key come chiave pubblica.
4. Eseguire `node backend/preflight.mjs`, poi `node backend/preflight.mjs --live-model` con una chiave valida. La seconda prova consuma una quantità limitata di credito; i test con fixture non la sostituiscono.
5. Verificare email reale, accesso/refresh/logout, due account isolati, upload/download/versioni/conflitti e cancellazione. Misurare streaming e primo token, inclusi ripresa rete e timeout. Configurare budget, monitoraggio `/ready`, backup database e politica di conservazione.

Il 25 ottobre 2026 è stato ricontrollato il contratto ufficiale: `deepseek-flash`, `/chat/completions` e `/v1/tools/search` con `query`, `count` e `need_content` corrispondono all’adapter. Questo confronto non è una chiamata live né dimostra credito o accesso sull’account. [Modelli](https://api-docs.deepseek.com/quick_start/pricing/), [ricerca](https://api-docs.deepseek.com/guides/search/). I costi del provider sono separati dall’account Apple e dal login dell’app.

La sincronizzazione account è limitata a 100 MiB per quaderno; l’import locale di PDF fino a 1 GiB non supera questo limite. Cartelle e cestino non sono sincronizzati. Community, abbonamenti e pagamenti restano fuori dalla prima delivery: non pubblicizzarli come disponibili.

## 3. Collegare app e pagine pubbliche

Completare e pubblicare le pagine descritte in `PRIVACY_AND_SUPPORT.md`, poi:

```powershell
python tools/configure_service.py --origin https://HOST-REALE --privacy-url https://PAGINA-REALE/privacy --support-url https://PAGINA-REALE/support
python tools/generate_project.py
```

Gli host sopra sono segnaposto, non servizi creati. Lo script verifica gateway e pagine prima di scrivere i plist. Committare i soli URL pubblici; ricompilare/testare quella revisione prima della distribuzione. Informativa, fornitore effettivo e questionario Store devono coincidere.

## 4. Firma e App Store Connect

Nel team Apple `64R668842U` registrare/verificare l’App ID esplicito `com.neuralnotes.NeuralNotes`, il container `iCloud.com.neuralnotes.NeuralNotes` e la scheda app. Abilitare CloudKit e distribuire lo schema nel suo ambiente Production dopo il collaudo. Non presumere che siano già registrati perché compaiono nel progetto.

La tabella esatta dei record/campi e il percorso Development → Production sono in `CLOUDKIT_SCHEMA.md`.

Il percorso CI usa un certificato **Apple Distribution con chiave privata**, un profilo App Store Connect coerente e una chiave API App Store Connect autorizzata all’upload. Il file `.cer` di sviluppo da solo non li sostituisce. Impostare questi GitHub Actions secrets senza salvarli nel repository:

- `NN_CERTIFICATE_P12_BASE64`: PKCS#12 di distribuzione con chiave privata.
- `NN_CERTIFICATE_PASSWORD`: password del PKCS#12.
- `NN_PROFILE_BASE64`: provisioning profile App Store Connect per team/App ID/container corretti.
- `NN_ASC_KEY_BASE64`: chiave privata `.p8` App Store Connect, in base64.
- `NN_ASC_KEY_ID`, `NN_ASC_ISSUER_ID`: identificativi della relativa chiave API.

`tools/validate_distribution_profile.py` rifiuta profili scaduti, di sviluppo/ad hoc/enterprise, di altro team/App ID o senza CloudKit Production. Il certificato e il collegamento della chiave privata vengono poi verificati dagli strumenti Apple durante la firma. Il keychain temporaneo e i file privati sono rimossi anche in caso di errore.

## 5. Accettazione e upload TestFlight

Compilare una copia di `production.example.json` **solo con risultati reali** e salvarla come repository variable `NN_PRODUCTION_CONFIG`. Contiene URL pubblici, contatto operatore e attestazioni, nessuna chiave. `acceptance_source_sha` deve essere l’esatto commit da distribuire. Le prove fisiche non sono sostituite dai test UI del simulatore.

```powershell
python tools/release_readiness.py --production --online --report .verification/production-readiness.json
gh workflow run verify.yml --ref codex/photo-perspective-sync-center -f scope=delivery -f delivery_upload=true
```

Il primo comando legge `NN_PRODUCTION_CONFIG` dall’ambiente del processo; GitHub la passa automaticamente al job. In assenza di dati o accettazioni il job si ferma prima di accedere ai segreti di firma. Non spuntare prove non eseguite per aggirarlo.

Il workflow con upload abilitato esegue l’archivio firmato e `xcodebuild -exportArchive` con destinazione App Store Connect. Verificare successivamente il processamento Apple e la presenza della build in TestFlight: un comando di upload riuscito non è un’approvazione. La distribuzione ai tester e l’invio ad App Review si gestiscono in App Store Connect.

## 6. Beta e Store

### Passaggio da Playgrounds a TestFlight

Il runner Playgrounds e l’app distribuita possono avere Bundle ID e contenitori diversi. Nel collaudo CLI il pacchetto Playground usa `neuralnotes.swiftpm.NeuralNotes`, mentre l’archivio Store usa `com.neuralnotes.NeuralNotes`. **Non aspettarsi che TestFlight legga automaticamente i quaderni del runner.** La prova di aggiornamento CI sostituisce due app Xcode con lo stesso Bundle ID e non dimostra una migrazione tra questi contenitori.

Prima della prima installazione TestFlight esportare i quaderni attuali in formato nativo su File/iCloud Drive. Conservare Playgrounds e i suoi documenti; importare un backup nella nuova app e controllare pagine, inchiostro, foto, audio e trascrizioni, poi importare gli altri. Non usare solo il PDF come backup modificabile. Non eliminare il progetto o i dati precedenti per risolvere un problema di build. Le cartelle della libreria restano da verificare/riorganizzare separatamente.

### Accettazione e scheda Store

Provare sul dispositivo fisico la build TestFlight: primo avvio, registrazione di ore/standby, camera/Pencil, documenti grandi, aggiornamento senza perdita dati, import dei vecchi export, account/cloud e iCloud su due dispositivi. Preparare screenshot e metadati da `APP_STORE_IT.md`; completare privacy, età, disponibilità, note e accesso revisori. Inviare ad App Review solo dopo questi passaggi.

Completare anche la dichiarazione Apple sulla crittografia in base all’uso effettivo di TLS e CryptoKit; il progetto non inventa un’esenzione o una documentazione di esportazione per conto dell’operatore.

Riferimenti ufficiali: [SDK richiesto](https://developer.apple.com/news/?id=ueeok6yw), [upload](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), [workflow Store](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-workflow/), [profilo di distribuzione](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/), [privacy manifest](https://developer.apple.com/documentation/technotes/tn3184-adding-data-collection-details-to-your-privacy-manifest).
