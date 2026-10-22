# NeuralNotes 0.19.0 / build 35 — PDF grandi e verifica account

22 ottobre 2026. Questa consegna contiene i sorgenti e un App Playground; non è un IPA firmato né una versione compilata con l’SDK Apple.

## PDF fino a 1 GiB e 5.000 pagine

Il vecchio percorso leggeva il PDF completo in memoria, lo ricopiava nell’allegato ed estraeva subito il testo di tutte le pagine. I limiti erano 100 MB e 1.000 pagine. Ora:

- Copia e SHA-256 incrementali in blocchi da 1 MiB, fuori dal thread UI, con avanzamento e annullamento. Lettura coordinata dei file e controllo dello spazio prima della copia: dimensione del PDF più 64 MiB di margine.
- Apertura dal file con Core Graphics, controllo di pagine, geometria e protezione; nessun grande `Data` dell’intero PDF. Spostamento del temporaneo nel quaderno, senza una seconda copia completa.
- Un solo allegato originale condiviso dalle pagine, con identità nuove. Catalogo e manifest pubblicati dopo la preparazione; rollback conservativo se fallisce. Il file sorgente resta intatto.
- Oltre 200 pagine il testo digitale viene letto su richiesta dalla Lente o dall’indicizzatore riprendibile della libreria. La cache del lettore viene rilasciata ogni 32 letture. Ricerca globale → **Testo PDF e grafia dei quaderni** → indicizzazione dei quaderni esistenti. Le scansioni senza testo richiedono ancora OCR.
- Corretto anche il caricamento delle pagine appena create, duplicate o importate: potevano essere già salvate nel manifest ma assenti dall’elenco UI, facendo fallire il cambio pagina. Per le pagine già note resta la lettura isolata della sola destinazione.

1 GiB significa 1.073.741.824 byte. Il limite riguarda l’importazione PDF locale. Foto e altri allegati mantengono i propri limiti; il caricamento cloud resta limitato a 100 MiB per oggetto e richiede ancora un client con suddivisione in parti per quaderni grandi. Backup/versioni consumano ulteriore spazio. Un PDF da 700 MB richiede tempo per copia, download da iCloud e preparazione: nessuna promessa di importazione o apertura in un secondo. Il codice iniziale conserva ancora gli header delle pagine; non è stata implementata una libreria interamente virtualizzata.

## Account e AI

L’accesso email nativo e il gateway della 0.18 sono inclusi. Questa lavorazione aggiunge una prova riproducibile con **servizi locali reali**: Supabase Auth/GoTrue, PostgreSQL 16, PostgREST e Mailpit. Verificati richiesta/ricezione del codice email, due utenti, profili separati, RLS, quote atomiche, rinnovo della sessione e revoca dopo logout. Il gateway viene raggiunto con TLS verificato. Le email rimangono nel catturatore locale.

Nel test completo il trasporto finale verso DeepSeek è una fixture dichiarata: la prova verifica autenticazione → quote → streaming/citazioni HTTP, non qualità, costo o latenza del modello. Nessuna richiesta a un provider AI live è stata eseguita.

Predisposti blueprint Render, controllo delle variabili server e collegamento dei due build dell’app a un URL pubblico verificato. **Servizio pubblico non attivato:** Supabase e Render non risultano collegati e manca la chiave DeepSeek nell’ambiente autorizzato. Nessun URL fittizio o segreto è stato incorporato nell’app. [Configurazione e comandi pronti](../backend/ACTIVATION.md).

## Verifiche eseguite

| Prova | Esito e limiti |
|---|---|
| Swift Core Linux 6.1.2 | 204 XCTest: 202 passati, due skip Darwin preesistenti, zero fallimenti; 98 FSRS passati |
| Nuovi test PDF portabili | Cinque passati: copia/hash di 700 MiB e 1.500 header, spazio/limiti, annullamento, ID duplicati, roundtrip backup di 1.500 pagine con allegato piccolo |
| Fixture PDF valida | 734.003.416 byte, 1.500 pagine: struttura verificata con pypdf strict, prima/ultima pagina renderizzate con Poppler e controllate visivamente |
| Backend Node | 41 test passati; provider e trasporti nelle unit test simulati |
| Integrazione account | Auth, email locale, PostgreSQL/RLS, refresh/logout reali; AI simulata esplicitamente |
| Progetto | 422 oggetti, 267 file Swift, 344 metodi XCTest individuati; grammatica e parsing Swift 5 riusciti |
| Nuove prove native | PDF reale di 1.500 pagine, lettura testo/render e caricamento pagine appena pubblicate: predisposte, **non eseguite** |

La prova di trasporto da 700 MiB usa un payload sintetico sparso con header PDF, non un documento interpretato da PDFKit. La fixture valida separata usa un grande stream non visualizzato: non rappresenta il costo di decodifica di 1.500 scansioni fotografiche. Il test nativo è quello che dovrà verificare l’importazione e il rendering con i framework Apple.

Parsing e controlli strutturali non sono type checking SDK né prove UIKit/Pencil. La CI Apple rimane bloccata dalla fatturazione GitHub documentata nelle [verifiche](ROADMAP_VALIDATION.md); nessun nuovo tentativo ripetuto. Non sono provati su dispositivo consumo massimo RAM, importazione del PDF specifico dell’utente o tempi di avvio.

## Pacchetto

Aprire `NeuralNotes-iPad-0.19.0.zip` in File, decomprimere in una cartella nuova e aprire `NeuralNotes.swiftpm` con Swift Playground. Conservare il progetto precedente e i suoi dati; un nuovo Playground può usare un container diverso. Il pacchetto include tutte le correzioni precedenti. La fixture da 700 MB e i segreti temporanei dei test non sono distribuiti.
