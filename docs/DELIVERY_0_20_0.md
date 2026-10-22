# NeuralNotes 0.20.0 / build 36: funzioni AI complete, account e backup nel cloud

22 ottobre 2026. Ramo `claude/ai-attivazione`, creato da `0dbcd63` (0.19.0).

Contiene i sorgenti e un App Playground. Non è un IPA firmato e non è stato compilato con l’SDK Apple: la CI Apple resta bloccata dalla fatturazione GitHub.

## Funzioni AI

### Con la chiave personale

**Scheda del termine, quiz e flashcard** funzionano ora anche con la chiave personale (OpenAI, Claude, Gemini, API compatibile Responses, DeepSeek). Prima richiedevano il backend.

- **Contratti:** gli schemi JSON e le regole sulle citazioni sono gli stessi del backend. Ogni riferimento viene copiato dalle fonti inviate, mai generato dal modello.
- **Ricerca web con fonti:** è disponibile anche con la chiave OpenAI (`web_search` di Responses). Al provider va solo il termine, mai la pagina.
- **DeepSeek API:** è un nuovo motore personale (Chat Completions in modalità JSON). Il modello si scrive nella Connessione AI.
- **Claude API:** ora accetta le risposte dei modelli attuali, che includono blocchi di ragionamento adattivo. Il budget di uscita sale a 16.000 token. Prima queste risposte venivano rifiutate come non valide.

### Lente

- **Inserimento:** la risposta va accanto all’area cerchiata o alla selezione, senza coprire testo, immagini e inchiostro, e senza uscire dalla pagina. Corpo 16 pt.
- **Flashcard dalla risposta:** la domanda non è più il comando ("Spiega"). Con un motore AI vengono proposte fino a tre carte; senza, una bozza locale sull’argomento. Le carte si correggono prima di salvarle.
- **Spiega e annota:** sottolinei o cerchi con lo strumento Lente un nome, una data, un luogo o un termine tecnico, anche su un PDF importato come quaderno.
  - L’app legge il termine con l’OCR e chiede al motore una spiegazione di una o due frasi, dalla sua conoscenza generale.
  - Il testo della pagina, insieme al titolo del quaderno, serve solo a scegliere il significato giusto.
  - La spiegazione arriva come post-it accanto al termine: in grassetto il termine, poi la spiegazione, con la dicitura "conoscenza generale, non dalle tue fonti". Le risposte incerte sono segnate "da verificare".
  - È automatico per selezioni brevi (fino a 12 parole) quando il motore è collegato e il consenso è attivo, e si spegne dall’interruttore nella Lente. Il pulsante "Spiega e annota" lo fa a mano, anche su frasi più lunghe.
  - Un annulla toglie la nota. Ogni nota costa un credito con il servizio NeuralNotes.
  - Funziona con tutti i motori AI, compreso DeepSeek, e con il servizio (`/v1/explain`).

### Ripasso

- **Flashcard generate dall’AI:** dalla pagina corrente o da tutto il quaderno, con un argomento facoltativo. Restano bozze modificabili; ognuna conserva la propria fonte.
- **Interrogami:** rispondi scrivendo o dettando; l’AI valuta la risposta rispetto alla carta e alla sua pagina, con citazioni, e suggerisce una valutazione. La scelta finale resta tua.
- **Valutazione "Difficile":** si aggiunge alle altre tre (FSRS a 4 gradi).

### Sbobina con l’AI

Si trova in Audio → una registrazione → "Sbobina con l’AI".

- **Cosa fa:** la trascrizione diventa appunti puliti. Un capitolo alla volta (cinque minuti o un tuo segnalibro), con i tempi dell’audio al posto delle citazioni.
- **Ripresa:** ogni capitolo viene salvato appena pronto. Se ci sono pause, errori di rete o il quaderno viene chiuso, si riprende da dove si era arrivati. Una correzione della trascrizione segnala che la sbobina va aggiornata.
- **Lettura:** ascolto per capitolo, export in Markdown, inserimento come pagine di testo del quaderno con un solo annulla.

## Backend `/v1/cards` e consumi

- **`/v1/cards`:** nuovo endpoint delle flashcard. Ha lo schema strict per Responses e la modalità JSON per DeepSeek, autenticazione e quote condivise con gli altri endpoint.
- **`/v1/platform/account`:** ora restituisce anche i crediti usati oggi e nel mese.
- **Nell’app:** Connessione AI → Account mostra piano, crediti del giorno e del mese, crediti rimasti e spazio cloud.

## Backup nel cloud NeuralNotes

Si trova in Libreria → Cloud e sincronizzazione.

- **Salvataggio:** salva uno o tutti i quaderni chiusi nell’account NeuralNotes, fino a 100 MB per quaderno. Ogni salvataggio diventa una nuova revisione e il server conserva le precedenti.
- **Coda persistente:** pacchetto `.nnbackup`, SHA-256, prenotazione, upload autenticato senza sovrascrittura, conferma della revisione attesa. Dopo un errore o un riavvio la coda riparte dall’ultimo passo concluso.
- **Conflitti:** se il cloud ha una revisione più recente, nulla viene sostituito. Puoi sostituire la versione del cloud con la tua oppure scaricarla come nuovo quaderno.
- **Download:** crea sempre un nuovo quaderno, dopo il controllo di dimensione e checksum.
- **Sicurezza:** il token dell’account viene inviato solo al gateway e allo storage del progetto configurato. I link firmati di download non ricevono il token.

**Limiti:**
- non è una sincronizzazione bidirezionale automatica tra due iPad e non unisce le modifiche;
- quaderni oltre 100 MB richiedono il backup su File;
- Storage ospitato e upload reali non sono ancora stati provati: lo storage nei test locali resta una fixture.

## Verifiche eseguite

| Prova | Esito |
|---|---|
| Swift Core Linux 6.1.2 (Docker) | 234 XCTest: 232 passati, 2 skip Darwin preesistenti, 0 errori; 98 FSRS passati |
| Nuovi test Core | Chiave personale strutturata (7), sbobina (5), interrogazione e "Difficile" (4), posizionamento della Lente (3), bozza locale (1), consumi dell’account (3), backup cloud (4) |
| Backend Node | 48 test passati (6 nuovi: `/v1/cards`, `/v1/explain`, DeepSeek cards ed explain, consumi dell’account) |
| Integrazione account | `MANAGED_E2E_PASS` con GoTrue, PostgreSQL 16, PostgREST e Mailpit reali in locale, nuovo controllo dei crediti per account. AI simulata |
| Sintassi | Grammatica di 284 file Swift (tree-sitter); `swiftc -parse` Swift 5 di tutti i sorgenti di app e test |
| Non eseguito | Compilazione SDK Apple, test XCTest e UI sul simulatore, prova sull’iPad, chiamate AI reali, Supabase e Render ospitati |

## Attivazione

L’app è pronta in due modi.

### 1. Subito, con la tua chiave

1. Apri Lente AI → Connessione AI.
2. Scegli il motore (OpenAI, Claude, Gemini o DeepSeek), scrivi il modello e incolla la chiave. La chiave resta nel Portachiavi dell’iPad.
3. Attiva il consenso.

Funzionano: chat, scheda, quiz, flashcard, interrogazione e sbobina. La ricerca web richiede OpenAI o il servizio.

### 2. Servizio NeuralNotes con account

Account, piani e cloud sono gestiti da Supabase e dal gateway su Render.

**Cosa fai tu (account e chiavi sono tuoi):**

1. **Supabase:** crea un progetto. Nel SQL Editor esegui una sola volta `backend/platform/schema.sql`. In Auth abilita Email con codice e un SMTP, con il template che contiene `{{ .Token }}`. Annota l’URL del progetto e la publishable key, mai la service role.
2. **DeepSeek:** crea una chiave API con credito e un limite di spesa.
3. **Render:** New → Blueprint, collega il repository GitHub e scegli `backend/deploy/render.yaml`. Il blueprint usa il ramo indicato nel file: per pubblicare `/v1/cards` e i consumi, questo ramo deve essere sul server (vedi sotto). Nelle variabili segrete inserisci tu `NN_PROVIDER_KEY`, `NN_SUPABASE_URL` e `NN_SUPABASE_PUBLIC_KEY`.
4. **Mandami solo l’indirizzo HTTPS del gateway.** Non mandare chiavi in chat.

**Cosa faccio io:**

1. `python tools/configure_service.py --origin https://…`, che verifica `/v1/config` e scrive l’indirizzo nei plist;
2. rigenero il progetto e lo zip;
3. aggiorno questa consegna con le prove reali.

Dettagli e controlli: [ACTIVATION.md](../backend/ACTIVATION.md), [ENVIRONMENT.md](../backend/ENVIRONMENT.md).

**Per pubblicare il backend aggiornato** serve un commit e un push di questo ramo, poi una delle due strade:

- puntare il blueprint di Render a `claude/ai-attivazione`;
- unire il ramo a quello usato da Render.

Il commit, il push e l’unione non sono stati fatti: aspettano la tua conferma.

## Pacchetto

Il pacchetto è `.verification/NeuralNotes-iPad-0.20.0.zip`, nella cartella `AppAppunti-claude`. Aprilo in File, decomprimilo in una cartella nuova e apri `NeuralNotes.swiftpm` con Swift Playgrounds.

Conserva il Playground precedente e i suoi backup. Il formato dei quaderni resta v1, con i soli nuovi campi opzionali (sbobina nella sessione audio) e senza migrazioni SwiftData.
