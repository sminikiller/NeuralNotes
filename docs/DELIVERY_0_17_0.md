# Consegna 0.17.0/build 31 — 22 ottobre 2026

## Correzioni dell’editor

1. **Elimina pagina:** la chiusura della conferma poteva svuotare gli identificativi prima dell’azione. Conferma e selezione ora hanno stato separato; il pulsante Elimina pagina è esterno al pulsante che apre l’anteprima. Il recupero è chiamato Pagine eliminate, con icona cronologia; il comando esplicita Ripristina N pagine nel quaderno. Anche Ripristina quaderno mostra il testo.
2. **Righello:** guida più spessa, con almeno 58 punti sullo schermo durante la disposizione, lunghezza iniziale 640 punti pagina. Due dita per spostare/ruotare e pizzico per cambiare lunghezza, più slider 240–1800. Il vincolo dell’inchiostro usa i bordi della guida effettiva. Conservati nomi selector dedicati e override richiesto da UIView.
3. **Prima foto:** il ritaglio viene presentato da un oggetto contenente immagine e dati, anziché da un flag separato che poteva aprire uno sheet senza immagine. La pagina di destinazione è verificata anche dopo la preparazione asincrona. È la correzione della causa individuata nel codice; il primo scatto hardware non è stato provato qui.
4. **Testo Pencil:** non viene forzata la tastiera all’attivazione del campo; comando Tastiera esplicito. Rimossa la seconda barra di formattazione UIKit aggiunta dall’app: i controlli sono in un overlay compatto coerente con l’editor. Il cambio della sola altezza disponibile, come con la tastiera, conserva zoom e scorrimento; rotazione/cambio larghezza continuano ad adattare il foglio. Scribble resta al sistema, senza tentativi di nascondere interfacce private di iPadOS.

## Apertura dei quaderni

Incluse le ottimizzazioni 0.16: una lettura iniziale dei JSON invece di tre, caricamento isolato della pagina scelta, manutenzione differita e cancellabile dopo inattività, niente nuovo backup dal flush pulito/chiusura. Recupero durate audio fuori dal thread UI e massimo tre anteprime vicine da 800 pixel. [Cause, benchmark e limiti](PERFORMANCE_0_16_0.md).

Il primo elenco legge ancora i JSON di tutte le pagine; manca un indice completamente su richiesta. Le prove sintetiche non misurano PKDrawing/PDF/UI su iPad e non garantiscono un’apertura entro un secondo. I tempi delle fasi sono visibili in Spazio e recupero; Foglio pronto indica modello caricato, non primo frame visualizzato.

## AI e piattaforma

Adapter DeepSeek con streaming e ricerca, autenticazione Supabase, quote atomiche giornaliere/mensili, hub/materiali/inviti, moderazione/report/blocchi, file privati prenotati e snapshot cloud con controllo della revisione. Nessun provider chiamato a pagamento, nessun hosting creato; account/community/sync non sono ancora collegati all’app nativa. [Piano con proposte economiche e stato puntuale](AI_COMMUNITY_PLAN_0_17.md), [configurazione server](../backend/ENVIRONMENT.md).

## Verifiche eseguite

- Swift 6.1.2 Linux: **185 XCTest, 183 passati, due skip Darwin preesistenti, zero fallimenti; 98 test FSRS passati**. Nuova prova Core della geometria/spessore del righello; incluse prove IO 6/12/300 pagine e cancellazione del backup.
- Node: **39 test passati**, fixture dichiarate per provider AI, Auth e trasporti PostgREST. Coprono streaming Unicode, risultati incompleti, citazioni, ricerca, autenticazione, upload, conflitti e quote.
- Avvio del gateway verificato su loopback con credenziali fittizie: configurazione pubblica priva della chiave provider e rifiuto delle chiamate AI senza autenticazione, senza chiamate esterne.
- PostgreSQL 16 reale in Docker: verificati isolamento RLS, quota giornaliera/mensile, dimensioni/prenotazioni, moderazione, report/blocchi, limiti inviti, revisioni concorrenti e rifiuto di revisioni nulle. Auth/Storage sono schemi di supporto: non è un test del servizio Supabase ospitato.
- Grafo Xcode **410 oggetti, 259 file Swift, 321 metodi XCTest presenti**, controllo grammaticale e parsing del compilatore Swift in modalità 5. Non significa esecuzione di tutti i 321 metodi o type checking UIKit.
- Predisposti due nuovi test Apple per conservazione dello zoom/testo e uno UI per elimina/ripristina; **non eseguiti**. Anche le due prove Apple sulle ottimizzazioni 0.16 restano non eseguite.
- I due ZIP sono confrontati byte per byte con i sorgenti e verificati per integrità/assenza di file obsoleti dal packager.

Non ho accesso a compilatore SDK Apple o controllo fisico dell’iPad; la CI Apple resta bloccata dalla fatturazione documentata nell’ultimo tentativo 39589913621. Parsing locale non rileva tutti gli errori SDK mostrati nelle foto precedenti. Questa consegna non è dichiarata una build Apple verificata, né completamento di ogni punto della roadmap.

## Pacchetto e prova mirata

`NeuralNotes-iPad-0.17.0.zip` contiene il progetto Swift Playground completo; `NeuralNotes-Sorgenti-0.17.0.zip` comprende Xcode, test, server e piano. Conservare il vecchio Playground e i quaderni: copie differenti possono usare contenitori differenti. Non eliminare i dati dell’app per aggiornare. [Istruzioni iPad](IPAD.md).

Sequenza di verifica sul dispositivo quando disponibile: aprire e ripristinare una pagina dal cestino; allungare/spostare il righello con due dita e tracciare sul bordo; fare il primo scatto dopo avvio; scrivere con Scribble, aprire/chiudere la tastiera e controllare lo zoom; confrontare l’apertura a freddo con le fasi mostrate in Spazio e recupero. Queste prove sono predisposte, non dichiarate svolte da remoto.
