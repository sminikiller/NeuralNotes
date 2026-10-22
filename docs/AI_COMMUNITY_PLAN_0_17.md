# NeuralNotes: AI, account, sincronizzazione e community

Proposta e stato dei sorgenti del 22 ottobre 2026, versione 0.17.0. Nessun servizio è stato pubblicato o addebitato. Il backend sviluppato è una base verificata localmente, non una piattaforma già utilizzabile dall’iPad.

## Esperienza nell’app

L’app deve conoscere un solo indirizzo HTTPS NeuralNotes. Modello, chiavi, limiti e abbonamenti si gestiscono sul server. Dopo l’accesso con Apple o codice email, l’utente usa gli strumenti senza configurare provider o token. La chiave del provider non entra nel pacchetto iPad. `/v1/config` restituisce solo configurazione pubblica; l’integrazione nativa di login, rinnovo della sessione e configurazione gestita resta da realizzare.

Il gesto deve essere intenzionale: selezione testo, lazo/Lente, cerchio o sottolineatura con la modalità Ricerca attiva. Una sottolineatura normale non deve avviare chiamate a pagamento. Il client estrae il testo digitale o esegue OCR locale sulla zona, mostra subito una piccola scheda ancorata alla selezione e avvia la risposta progressiva. Azioni: Spiega, Definisci, Esempio, Cerca sul web, Inserisci nel foglio, Copia, Approfondisci. La scheda conserva pagina e selezione di origine: cambiare pagina annulla la richiesta, non inserisce la risposta altrove.

Le azioni sui propri appunti e quelle sul web rimangono riconoscibili. Una definizione usa l’estratto e il contesto vicino; una sintesi lunga recupera solo i passaggi pertinenti dall’indice, senza inviare il quaderno intero. La ricerca web invia il termine, mostra fonti cliccabili e richiede ricerca reale: il modello non inventa collegamenti. L’inserimento sul foglio ha annulla. I frammenti incompleti non diventano risposte salvate. Cache privata per utente, termine, contesto e versione del modello; mai cache condivisa di appunti personali.

Gli strumenti locali di selezione, OCR, popup e inserimento esistono già. Il server supporta studio progressivo, definizioni, quiz e ricerca; la risposta di ricerca web richiede due passaggi e attualmente è completa, non progressiva. L’accesso server gestito non è ancora collegato alle schermate native. Non è promessa una risposta istantanea o corretta al 100%: timeout, rete, OCR e generazione restano misurabili separatamente. Nei materiali sanitari le fonti e la distinzione tra contenuto didattico e decisioni cliniche devono restare visibili.

## Provider e costi

Userei DeepSeek dietro un adapter sostituibile, con ragionamento disattivato per le risposte brevi, limiti di output e output JSON verificato. L’adapter implementato usa `deepseek-flash`, streaming SSE e controllo delle citazioni. Il contratto ufficiale consente JSON e streaming; il prompt deve richiedere esplicitamente JSON. [API DeepSeek](https://api-docs.deepseek.com/api/create-chat-completion/), [modalità JSON](https://api-docs.deepseek.com/guides/json_mode/).

Al controllo del 22 ottobre 2026, Flash costa per milione di token $0,15–0,30 in input non in cache e $0,60–1,20 in output, secondo la fascia oraria. Una risposta con 1.500 token in ingresso e 350 in uscita costa circa **$0,000435–0,000870**, ossia **$0,435–0,87 per mille risposte**, solo inferenza. Search/Fetch sono indicati a $0,75 per mille chiamate riuscite; token delle pagine recuperate, infrastruttura, tasse e cambio si aggiungono. Le condizioni promozionali e le fasce non vanno assunte permanenti. [Prezzi ufficiali DeepSeek](https://api-docs.deepseek.com/quick_start/pricing/), [contratto ricerca](https://api-docs.deepseek.com/guides/search/).

Supabase riunirebbe Auth, PostgreSQL e file privati. Il piano gratuito serve per lo sviluppo; il Pro parte da **$25/mese** al controllo odierno, cui aggiungere gateway HTTPS e consumi eccedenti. È costo del progetto, non costo per account. [Prezzi Supabase](https://supabase.com/pricing), [Auth](https://supabase.com/docs/guides/auth), [controlli Storage](https://supabase.com/docs/guides/storage/security/access-control).

Il budget va protetto con quote nel database, limite di concorrenza e risposta, tetto di spesa provider e metriche senza testo privato. Una richiesta valida può consumare crediti anche se il provider fallisce: il server attuale riserva la quota prima della chiamata e non applica rimborsi automatici. Si evita così un aggiramento tramite cancellazioni ripetute. Una richiesta web costa otto crediti, quelle sui testi almeno uno e fino a venti in base al contesto; un credito non equivale sempre a una risposta.

## Piani proposti, non abbonamenti attivi

| Piano | Prezzo mensile proposto | Crediti AI/mese | Massimo/giorno | Cloud |
|---|---:|---:|---:|---:|
| Base | Gratis | 100 | 10 | 256 MiB |
| Studio | €4,99 | 500 | 50 | 2 GiB |
| Pro | €9,99 | 2.000 | 150 | 10 GiB |
| Gruppo pilota | €24,99 | 3.000 | 300 | 20 GiB |

Scrittura ed esportazione locali restano disponibili senza abbonamento. I prezzi sono ipotesi da verificare con consumi reali, commissioni e supporto. Il piano Gruppo non comprende ancora posti/licenze condivise: prima serve un modello organizzazioni. `plans.mjs` pubblica la proposta; non abilita pagamenti o privilegi. Lo schema applica il piano gratuito e permette solo all’amministrazione di cambiare le assegnazioni. Mancano StoreKit, verifica delle transazioni, webhook e gestione di rimborsi/scadenze.

## Account e sincronizzazione

Il database verifica ogni utente con Supabase Auth, senza fidarsi di UUID passati dall’app. RLS limita profilo, documenti, materiali e inviti. I file sono privati; gli upload richiedono prenotazione, autenticazione e dimensione attesa. Percorsi univoci impediscono di sovrascrivere una revisione. I download autorizzati hanno link brevi.

La scrittura resta locale. La futura coda sul dispositivo registra modifiche, checksum, revisione di base e avanzamento dei trasferimenti; riparte dopo perdita di rete o chiusura. Il server implementa confronto della revisione e snapshot immutabili: un conflitto restituisce 409, preservando entrambe le versioni. Il client dovrà presentare una copia in conflitto, senza sostituire automaticamente l’inchiostro. Serve una strategia per pagine/media separati e caricamenti riprendibili: il limite attuale è **100 MiB per oggetto**, quindi grandi quaderni non possono essere spediti come unico backup. Non è implementata una fusione collaborativa simultanea dei tratti.

Prima del rilascio occorrono coda nativa, tombstone di cancellazione, ripristino versioni, limiti di conservazione, garbage collection sicura, esportazione/eliminazione account e test su due dispositivi. Questi punti non sono completati dal solo endpoint cloud.

## Community

Una sezione come Infermieristica diventa un hub pubblico o privato, con ruoli lettore, autore e moderatore. Organizzazione tramite tag: anno, materia, corso, tipologia, lingua. Materiale con titolo, autore, descrizione, copertina, versione, licenza e fonti. Una persona può leggere il PDF o copiare un quaderno nella propria libreria: le annotazioni personali non modificano il materiale pubblicato.

La condivisione deve preparare una copia selezionata: pagine desiderate, anteprima, rimozione di audio, cestino e informazioni private non richieste. Mai caricare silenziosamente tutto il quaderno. Gli inviti hanno scadenza e limite di utilizzi; il server memorizza solo il digest del token. La prima versione deve avere ricerca per hub/tag, bozze, revisione prima della pubblicazione, segnalazioni e blocco autori. Eviterei inizialmente chat, feed algoritmico e messaggi privati: aumentano molto il lavoro di moderazione.

Il backend implementa hub, membership, materiali in attesa, pubblicazione autorizzata, inviti, report e blocchi. Restano da costruire interfaccia nativa, anteprima di pubblicazione ripulita, pannello moderatore, controllo dei contenuti/file, ricerca completa, notifiche, rimozioni e gestione dei diritti. L’hub Infermieristica non è stato creato in un servizio remoto.

## Ordine di rilascio e stato reale

| Fase | Implementato e verificato localmente | Lavoro prima dell’uso reale |
|---|---|---|
| AI gestita | Adapter DeepSeek, streaming, JSON/citazioni, ricerca reale, quote | Hosting HTTPS, segreti server, login/config nativi, misure latenza/costi live |
| Account | Verifica token e identità, profilo isolato, ruoli/quote SQL | Schermate Apple/email, rinnovo sessioni, eliminazione account |
| Community | Hub, materiali, inviti, moderazione, report/blocchi | UI, condivisione ripulita, ricerca e gestione operativa |
| Cloud | Prenotazioni/file privati, snapshot, checksum e revisione attesa | Coda nativa, ripresa upload, conflitti a schermo, grandi pacchetti e retention |
| Piani | Proposta prezzi e limiti verificati nel database | Pagamenti e privilegi verificati, organizzazioni, sostenibilità economica |

Procederei in questo ordine: consolidare l’editor sull’iPad; pubblicare una prova privata AI con pochi account e budget rigido; aggiungere cloud e conflitti su due dispositivi; aprire una community pilota moderata; attivare abbonamenti solo dopo misurazioni reali. Nessun account esterno o risorsa a pagamento è stato creato in questa consegna.

Verifica eseguita: 39 test Node con fixture e richieste HTTP locali; controlli reali PostgreSQL 16 con schemi Auth/Storage di supporto. Non sono prove del servizio Supabase ospitato, della qualità delle risposte o di latenza dal dispositivo. [Configurazione server](../backend/ENVIRONMENT.md), [report della consegna](DELIVERY_0_17_0.md).
