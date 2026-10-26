# TestFlight senza Mac: beta interna di NeuralNotes

GitHub compila l'app con Xcode 26.6 su un Mac nel cloud, la firma con il tuo certificato e la carica su App Store Connect. Sull'iPad la installi poi con l'app TestFlight. Non servono né un Mac né Swift Playgrounds.

Questa è la **beta interna**: la usi tu (e chi aggiungi al team) per il collaudo sull'iPad.
- Non passa dalla revisione di Apple.
- Non richiede backend pubblico né pagine privacy.
- Non contiene la sincronizzazione iCloud, che si aggiungerà in una beta successiva.

Restano attivi i backup su File, l'export nativo e il cloud dell'account, quando il servizio sarà pubblicato. La pubblicazione sull'App Store usa invece il percorso completo di [DELIVERY.md](DELIVERY.md).

**Il compilatore è sui server GitHub.** Sul tuo dispositivo non devi installare Xcode, Swift o un altro compilatore. Per le operazioni sul sito Apple basta il browser, anche dall'iPad.

**Stato al 26 ottobre 2026.** La prima beta, 1.0.0 (build 120), è stata caricata con questa procedura ed è installata sull'iPad.
- App ID, certificato, profilo, scheda dell'app, chiave API, i 6 segreti di GitHub e il gruppo di test sono già pronti.
- Per una nuova build basta il punto 7.
- I punti 1–6 servono solo per il rinnovo o per rifare la configurazione.
- Certificato e profilo scadono il **25 ottobre 2027**.

**Per configurare o rinnovare ti servono:**
- l'Apple Developer Program attivo sul team `64R668842U`;
- un PC Windows con Git per Windows (Git Bash) e GitHub CLI collegato all'account: `gh auth status` deve mostrare `sminikiller`;
- un browser.

> **Sicurezza.** Chiave privata, file `.p12` con la sua password e file `.p8` restano solo sul tuo PC e nei segreti di GitHub. Non incollarli in chat, nelle email o nel repository. Se finiscono altrove, revoca certificato e chiave dal sito Apple e creane di nuovi. Key ID e Issuer ID, da soli, non sono segreti.

Tutti i file di firma stanno nella cartella `C:\Users\<tuo utente>\neuralnotes-firma`, che in Git Bash è `~/neuralnotes-firma`. Il browser salva i download nella cartella **Download**, a volte nell'ultima sottocartella usata: da lì spostali in `neuralnotes-firma`.

## 1. Identificativo dell'app (App ID)

L'App ID `com.lorenzominichilli.neuralnotes` è già registrato nel team. `com.neuralnotes.NeuralNotes` non è disponibile su Apple, per questo il progetto usa il primo.

Solo se mancasse:
1. Apri [Identifiers](https://developer.apple.com/account/resources/identifiers/list) e premi **+**.
2. Scegli **App IDs**, poi **App**.
3. Descrizione `NeuralNotes`. In **Bundle ID** scegli **Explicit** e scrivi `com.lorenzominichilli.neuralnotes`.
4. Non attivare altre funzioni (per questa beta niente iCloud), poi **Continue** e **Register**.

## 2. Certificato di distribuzione (da Windows)

Apri **Git Bash** (tasto Windows, scrivi `Git Bash`, Invio). Incolla i comandi con clic destro → **Paste**, uno alla volta:

```bash
mkdir -p ~/neuralnotes-firma && cd ~/neuralnotes-firma
openssl genrsa -out distribuzione.key 2048
MSYS_NO_PATHCONV=1 openssl req -new -key distribuzione.key -out distribuzione.csr -subj "/CN=NeuralNotes Distribution/C=IT"
```

L'email nella richiesta non serve: Apple usa solo la chiave pubblica.

1. Apri [Nuovo certificato](https://developer.apple.com/account/resources/certificates/add).
2. Scegli **Apple Distribution**, poi **Continue**.
3. Carica il file `distribuzione.csr` dalla cartella `neuralnotes-firma`, poi **Continue**.
4. Premi **Download** e sposta `distribution.cer` nella cartella `neuralnotes-firma`.

Poi, in Git Bash, un solo comando: converte il certificato, genera una password casuale e crea il `.p12`.

```bash
cd ~/neuralnotes-firma && openssl x509 -in distribution.cer -inform DER -out distribuzione.pem -outform PEM && openssl rand -hex 16 > password-p12.txt && openssl pkcs12 -export -legacy -inkey distribuzione.key -in distribuzione.pem -name "NeuralNotes Distribution" -out distribuzione.p12 -passout file:password-p12.txt && echo "TUTTO OK: distribuzione.p12 creato"
```

Deve comparire `TUTTO OK: distribuzione.p12 creato`.
- Il comando non chiede nulla: in Git Bash le richieste di password di OpenSSL possono bloccarsi.
- La password è in `password-p12.txt` e diventa il segreto `NN_CERTIFICATE_PASSWORD`.
- `-legacy` produce il formato che il portachiavi di macOS legge.
- Se compare "No certificate matches private key", il certificato è stato creato da un'altra richiesta: rifallo con `distribuzione.csr`.

Nell'elenco dei certificati Apple può comparire anche **Distribution Managed**. È un certificato gestito da Apple, per esempio per Swift Playgrounds: lascialo stare, il progetto non lo usa.

### Alternativa: richiesta già pronta

Nel repository c'è anche una richiesta preparata da Codex: [NeuralNotes-TestFlight.certSigningRequest](signing/NeuralNotes-TestFlight.certSigningRequest). Contiene solo la parte pubblica. La chiave privata corrispondente è nella cartella ignorata `.verification/apple-testflight-signing` della copia di lavoro di Codex.

**Il certificato attuale non viene da questa richiesta**, ma dalla chiave in `neuralnotes-firma`. Usa la richiesta pronta solo al posto dei tre comandi qui sopra, mai insieme: ogni certificato funziona solo con la propria chiave.

## 3. Profilo di distribuzione

1. Apri [Profiles](https://developer.apple.com/account/resources/profiles/list) e premi il **+ blu**.
2. In **Register a New Provisioning Profile**, nell'elenco **Distribution**, scegli **App Store Connect** (non *tvOS* né *Mac*). Premi **Continue**.
3. In **App ID** scegli **NeuralNotes (64R668842U.com.lorenzominichilli.neuralnotes)**. Premi **Continue**.
4. Scegli il certificato di **Lorenzo Minichilli** con la stessa scadenza del punto 2, **senza** la parola *Managed*. Premi **Continue**.
5. In **Provisioning Profile Name** scrivi `NeuralNotes App Store`. Premi **Generate**.
6. Premi **Download** e sposta `NeuralNotes_App_Store.mobileprovision` in `neuralnotes-firma`.

Ogni volta che rifai il certificato devi rifare anche il profilo: un profilo vale solo per i certificati che contiene.

## 4. Scheda dell'app in App Store Connect

La scheda esiste già: **NeuralNotes**, ID Apple dell'app `6826883204`. In **Informazioni sull'app**, l'**ID pacchetto** è `com.lorenzominichilli.neuralnotes`.
- **Non cambiare quel menu.** Elenca anche altri identificativi dell'account.
- Per TestFlight non serve compilare la pagina della versione: descrizione, screenshot e note di verifica servono solo per l'App Store.
- Gli avvisi in alto, come lo stato di operatore commerciale UE, riguardano la pubblicazione sull'App Store, non la beta.

Solo se la scheda mancasse:
1. Apri [App](https://appstoreconnect.apple.com/apps) e premi **+**, poi **Nuova app**.
2. Compila così:
   - piattaforma **iOS**;
   - nome **NeuralNotes** (se è già usato da altri, scegline uno simile: conta il Bundle ID);
   - lingua principale **Italiano**;
   - Bundle ID `com.lorenzominichilli.neuralnotes`;
   - SKU `neuralnotes-ipad`;
   - accesso **completo**.
3. Premi **Crea**.

## 5. Chiave API per il caricamento

1. Apri [Integrazioni → API di App Store Connect](https://appstoreconnect.apple.com/access/integrations/api).
2. **Solo la prima volta:** premi **Richiedi accesso** e accetta le condizioni dell'API. Per il titolare del conto l'approvazione è immediata.
3. In **Chiavi del team** premi **Genera chiave API**.
4. Nome `GitHub TestFlight`, accesso **App Manager**, poi **Genera**.
5. Nella riga della chiave premi **Scarica**, poi conferma. Sposta `AuthKey_<KEY ID>.p8` in `neuralnotes-firma`.
   - **Si può scaricare una sola volta.**
   - Nella cartella deve restare un solo file `AuthKey_…`.
6. Lascia aperta la pagina. Sopra l'elenco c'è l'**ID emittente** (Issuer ID) con il pulsante **Copia**: serve al punto 6. Il **Key ID** è il codice nel nome del file.

## 6. I 6 segreti su GitHub, con un solo comando

In Git Bash incolla questa riga e premi **Invio**:

```bash
cd ~/neuralnotes-firma && read -p "ID emittente (Issuer ID): " ISSUER && KEY=$(ls AuthKey_*.p8) && KEYID=${KEY#AuthKey_} && KEYID=${KEYID%.p8} && R=sminikiller/NeuralNotes && base64 -w0 distribuzione.p12 | gh secret set NN_CERTIFICATE_P12_BASE64 -R $R && tr -d '\r\n' < password-p12.txt | gh secret set NN_CERTIFICATE_PASSWORD -R $R && base64 -w0 NeuralNotes_App_Store.mobileprovision | gh secret set NN_PROFILE_BASE64 -R $R && base64 -w0 "$KEY" | gh secret set NN_ASC_KEY_BASE64 -R $R && gh secret set NN_ASC_KEY_ID -R $R --body "$KEYID" && gh secret set NN_ASC_ISSUER_ID -R $R --body "$ISSUER" && echo "TUTTO OK: 6 segreti inseriti su GitHub"
```

1. Quando compare `ID emittente (Issuer ID):`, torna sulla pagina della chiave API e premi **Copia** accanto all'ID emittente.
2. Torna in Git Bash, fai clic destro → **Paste** e premi **Invio**.
3. Compaiono 6 righe *Set Actions secret …* e poi `TUTTO OK: 6 segreti inseriti su GitHub`.

I file vanno direttamente dal PC a GitHub, cifrati. Con `gh secret list -R sminikiller/NeuralNotes` controlli i nomi, mai i valori.

| Nome del segreto | Da dove viene |
|---|---|
| `NN_CERTIFICATE_P12_BASE64` | `distribuzione.p12` in base64, su una sola riga |
| `NN_CERTIFICATE_PASSWORD` | `password-p12.txt`, senza a capo |
| `NN_PROFILE_BASE64` | `NeuralNotes_App_Store.mobileprovision` in base64 |
| `NN_ASC_KEY_BASE64` | `AuthKey_….p8` in base64 |
| `NN_ASC_KEY_ID` | il codice nel nome del file `AuthKey_….p8` |
| `NN_ASC_ISSUER_ID` | l'ID emittente copiato dalla pagina |

La compilazione decodifica il base64 in modo rigoroso. Se inserisci i segreti a mano dal sito di GitHub, incolla il testo su una sola riga, senza spazi o a capo finali.

## 7. Avvia la compilazione per TestFlight

Funziona anche dal browser dell'iPad.

1. Prima serve una **verifica completa verde** dell'ultimo commit. Il controllo confronta i sorgenti dell'app con quelli già verificati, così su TestFlight va solo codice collaudato. Da una pagina di run verde copia il commit completo: 40 caratteri, visibili sotto il titolo della run.
2. Apri [NeuralNotes verification](https://github.com/sminikiller/NeuralNotes/actions/workflows/verify.yml) e premi **Run workflow**.
3. Compila così:
   - ramo: quello con questo workflow;
   - scope **testflight**;
   - **verified_sha**: il commit copiato.
4. Premi **Run workflow**.

Dal PC puoi usare lo stesso comando del primo caricamento, sostituendo il commit:

```bash
gh workflow run verify.yml --repo sminikiller/NeuralNotes --ref codex/photo-perspective-sync-center -f scope=testflight -f verified_sha=COMMIT-DI-40-CARATTERI
```

Dura circa 10–30 minuti. Se mancano segreti si ferma subito ed elenca solo i loro nomi, prima di qualsiasi firma. Alla fine il registro mostra `Uploaded NeuralNotes`, `EXPORT SUCCEEDED` e `UPLOAD_COMMAND_SUCCEEDED`. Il numero di build cresce da solo a ogni esecuzione.

**Se si ferma:**
- `Missing GitHub distribution secret`: manca un segreto, ripeti il punto 6.
- `No profile for team … matching … found`: il profilo non contiene il certificato attuale o è di un altro App ID. Ripeti i punti 3 e 6.
- Errore all'import del certificato o della password: il `.p12` e `password-p12.txt` non corrispondono. Ripeti l'ultimo comando del punto 2, poi il punto 6.

## 8. Installa con TestFlight

Già configurato: in App Store Connect → **TestFlight** c'è il gruppo di test interni **Io**, con te come tester e la **distribuzione automatica** attiva. Ogni nuova build arriva da sola al gruppo, dopo 10–30 minuti di elaborazione da parte di Apple. La domanda sulla crittografia non compare: l'app dichiara di usare solo HTTPS e hash.

Su un nuovo iPad:
1. Installa **TestFlight** dall'App Store, l'app di Apple con l'elica azzurra.
2. Apri l'email di invito di TestFlight per NeuralNotes e tocca **Visualizza in TestFlight**. Se TestFlight chiede un codice, è scritto nella stessa email.
3. Premi **Accetta**, poi **Installa**.

Se il gruppo mancasse: in **TEST INTERNI** premi il **+ blu**, chiama il gruppo `Io` e lascia spuntata **Abilita distribuzione automatica**. Poi in **Tester** premi **+** e aggiungi te stesso.

## 9. Porta i tuoi quaderni nell'app TestFlight

L'app TestFlight è separata da quella di Swift Playgrounds e non vede i suoi quaderni.

1. Nell'app di Playgrounds esporta ogni quaderno come **Quaderno nativo e backup** in File o iCloud Drive.
2. Nell'app TestFlight importalo e controlla pagine, inchiostro, foto, audio e trascrizioni.
3. Conserva Playgrounds e i backup finché non hai verificato tutto.

Dettagli in [DELIVERY.md](DELIVERY.md), punto 6.

## Costi e rinnovi

- Ogni esecuzione usa un runner macOS di GitHub Actions. Nei repository pubblici i minuti dei runner standard sono gratuiti. Nei repository privati i minuti macOS pesano di più nel conteggio del piano.
- Le build TestFlight scadono dopo 90 giorni: per continuare basta lanciare una nuova esecuzione (punto 7).
- Certificato e profilo scadono il **25 ottobre 2027**. Prima di quella data ripeti i punti 2, 3 e 6.
- La chiave API non scade, ma Apple non permette di riscaricarla. Se perdi il file `.p8`, revoca la chiave, creane una nuova (punto 5) e ripeti il punto 6.
- Conserva la cartella `neuralnotes-firma` in un posto sicuro, per esempio un archivio cifrato o un gestore di password.
