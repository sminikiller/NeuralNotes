# TestFlight senza Mac: beta interna di NeuralNotes

GitHub compila l'app con Xcode 26.6 su un Mac nel cloud, la firma con il tuo certificato e la carica su App Store Connect. Sull'iPad la installi poi con l'app TestFlight. Non servono né un Mac né Swift Playgrounds.

Questa è la **beta interna**: la usi tu (e chi aggiungi al team) per il collaudo sull'iPad.
- Non passa dalla revisione di Apple.
- Non richiede backend pubblico né pagine privacy.
- Non contiene la sincronizzazione iCloud, che si aggiungerà in una beta successiva.

Restano attivi i backup su File, l'export nativo e il cloud dell'account, quando il servizio sarà pubblicato. La pubblicazione sull'App Store usa invece il percorso completo di [DELIVERY.md](DELIVERY.md).

**Ti servono:** l'Apple Developer Program attivo sul team `64R668842U`, un PC Windows con Git per Windows (Git Bash) e un browser. Tempo: circa 30–45 minuti la prima volta.

> **Sicurezza.** Chiave privata, file `.p12`, password e file `.p8` restano solo sul tuo PC e nei segreti di GitHub. Non incollarli in chat, nelle email o nel repository. Se finiscono altrove, revoca certificato e chiave dal sito Apple e creane di nuovi.

## 1. Registra l'identificativo dell'app (App ID)

1. Apri [Identifiers](https://developer.apple.com/account/resources/identifiers/list) e premi **+**.
2. Scegli **App IDs**, poi **App**.
3. Descrizione `NeuralNotes`. In **Bundle ID** scegli **Explicit** e scrivi `com.neuralnotes.NeuralNotes`.
4. Non attivare altre funzioni (per questa beta niente iCloud), poi **Continue** e **Register**.

Se l'identificativo esiste già, va bene così: passa al punto 2.

## 2. Crea il certificato di distribuzione (da Windows)

Apri **Git Bash** e scrivi, una riga alla volta, sostituendo `LA-TUA-EMAIL` con l'email del tuo account Apple:

```bash
mkdir -p ~/neuralnotes-firma && cd ~/neuralnotes-firma
openssl genrsa -out distribuzione.key 2048
MSYS_NO_PATHCONV=1 openssl req -new -key distribuzione.key -out distribuzione.csr -subj "/emailAddress=LA-TUA-EMAIL/CN=NeuralNotes Distribution/C=IT"
```

1. Apri [Nuovo certificato](https://developer.apple.com/account/resources/certificates/add).
2. Scegli **Apple Distribution**, poi **Continue**.
3. Carica il file `distribuzione.csr`, che trovi in `C:\Users\<tuo utente>\neuralnotes-firma`.
4. Scarica il certificato (`distribution.cer`) nella stessa cartella.

Poi, ancora in Git Bash:

```bash
cd ~/neuralnotes-firma
openssl x509 -in distribution.cer -inform DER -out distribuzione.pem -outform PEM
openssl pkcs12 -export -legacy -inkey distribuzione.key -in distribuzione.pem -name "NeuralNotes Distribution" -out distribuzione.p12
```

Ti chiede due volte una password: scegline una e conservala, perché è il segreto `NN_CERTIFICATE_PASSWORD`. Se compare "unknown option -legacy", ripeti l'ultimo comando senza `-legacy`.

## 3. Crea il profilo di distribuzione

1. Apri [Nuovo profilo](https://developer.apple.com/account/resources/profiles/add).
2. In **Distribution** scegli **App Store Connect**, poi **Continue**.
3. Scegli l'App ID `com.neuralnotes.NeuralNotes` e il certificato del punto 2.
4. Nome `NeuralNotes App Store`, poi **Generate** e **Download**. Sposta il file `.mobileprovision` in `neuralnotes-firma`.

## 4. Crea la scheda dell'app in App Store Connect

1. Apri [App](https://appstoreconnect.apple.com/apps) e premi **+**, poi **Nuova app**.
2. Compila così:
   - piattaforma **iOS**;
   - nome **NeuralNotes** (se è già usato da altri, scegline uno simile: conta il Bundle ID);
   - lingua principale **Italiano**;
   - Bundle ID `com.neuralnotes.NeuralNotes`;
   - SKU `neuralnotes-ipad`;
   - accesso **completo**.
3. Premi **Crea**.

## 5. Crea la chiave API per il caricamento

1. Apri [Integrazioni → API di App Store Connect](https://appstoreconnect.apple.com/access/integrations/api) e scegli **Chiavi del team**.
2. Genera una chiave di nome `GitHub TestFlight` con accesso **App Manager**.
3. Annota il **Key ID** e l'**Issuer ID**, che compare sopra l'elenco.
4. Scarica il file `AuthKey_….p8` nella cartella `neuralnotes-firma`. **Si può scaricare una sola volta.**

## 6. Inserisci i 6 segreti in GitHub

Apri [Secrets di GitHub Actions](https://github.com/sminikiller/NeuralNotes/settings/secrets/actions) e, per ogni riga, premi **New repository secret**.

Per i tre file serve il testo in base64. In **PowerShell**, partendo dalla cartella:

```powershell
cd $HOME\neuralnotes-firma
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$PWD\distribuzione.p12")) | Set-Clipboard
```

Ora il testo è negli appunti: incollalo nel segreto. Ripeti cambiando il nome del file.

| Nome del segreto | Valore |
|---|---|
| `NN_CERTIFICATE_P12_BASE64` | base64 di `distribuzione.p12` |
| `NN_CERTIFICATE_PASSWORD` | la password scelta al punto 2 |
| `NN_PROFILE_BASE64` | base64 del file `.mobileprovision` |
| `NN_ASC_KEY_BASE64` | base64 del file `AuthKey_….p8` |
| `NN_ASC_KEY_ID` | il Key ID (testo semplice) |
| `NN_ASC_ISSUER_ID` | l'Issuer ID (testo semplice) |

Poi conserva la cartella `neuralnotes-firma` in un posto sicuro, per esempio un archivio cifrato o un gestore di password. Serve per i rinnovi.

## 7. Avvia la compilazione per TestFlight

Funziona anche dal browser dell'iPad.

1. Prima serve una **verifica completa verde** dell'ultimo commit. Il controllo confronta i sorgenti dell'app con quelli già verificati, così su TestFlight va solo codice collaudato. Da una pagina di run verde copia il commit completo: 40 caratteri, visibili sotto il titolo della run.
2. Apri [NeuralNotes verification](https://github.com/sminikiller/NeuralNotes/actions/workflows/verify.yml) e premi **Run workflow**.
3. Compila così:
   - ramo: quello con questo workflow;
   - scope **testflight**;
   - **verified_sha**: il commit copiato.
4. Premi **Run workflow**.

Dura circa 20–30 minuti. Se mancano segreti si ferma subito ed elenca solo i loro nomi, prima di qualsiasi firma. Alla fine il registro mostra `UPLOAD_COMMAND_SUCCEEDED`. Il numero di build cresce da solo a ogni esecuzione.

## 8. Installa con TestFlight

1. In App Store Connect apri l'app e poi **TestFlight**. Dopo 10–30 minuti di elaborazione da parte di Apple la build è pronta. La domanda sulla crittografia non compare: l'app dichiara di usare solo HTTPS e hash.
2. In **Test interni** crea un gruppo, per esempio `Io`, e aggiungi te stesso e la build.
3. Sull'iPad installa **TestFlight** dall'App Store, accedi con lo stesso Apple ID e installa NeuralNotes.

## 9. Porta i tuoi quaderni nell'app TestFlight

L'app TestFlight è separata da quella di Swift Playgrounds e non vede i suoi quaderni.

1. Nell'app di Playgrounds esporta ogni quaderno come **Quaderno nativo e backup** in File o iCloud Drive.
2. Nell'app TestFlight importalo e controlla pagine, inchiostro, foto, audio e trascrizioni.
3. Conserva Playgrounds e i backup finché non hai verificato tutto.

Dettagli in [DELIVERY.md](DELIVERY.md), punto 6.

## Costi e rinnovi

- Ogni esecuzione usa circa 25 minuti di runner macOS di GitHub Actions. Nei repository privati quei minuti pesano di più nel conteggio del piano.
- Le build TestFlight scadono dopo 90 giorni: per continuare basta lanciare una nuova esecuzione.
- Certificato e profilo durano un anno. Alla scadenza ripeti i punti 2, 3 e 6.
