# Fase0.30 — candidata completa da compilare e collaudare

La beta pubblicata resta1.0.0(179), con PDF0.28.2 e testo0.29. Il candidato0.30 è isolato e non distribuito. La verifica completa42098289365 ha compilato il pacchetto iPad e superato Core e aggiornamento dei quaderni; nella suite nativa sono falliti sei casi (166 asserzioni, principalmente pixel della stessa fusione). **48 di49 UI sono passati**. Il job è poi scaduto durante Release: non è una verifica verde.

Correzioni raggruppate: UIImage.draw usa esplicitamente Multiply/Screen/Difference/ColorDodge, perché il metodo senza parametri ripristina Normal. Il PDF dei gruppi parzialmente trasparenti usa contorni per le tre prove dei coefficienti e testo selezionabile una sola volta nel passaggio finale, anche nelle unioni annidate. Il cambio proprietario/visibilità completa la preparazione del fallback sul vero host, senza attendere il dettaglio né un ulteriore tocco. Aggiunte prove sul layout dei glifi, sui testi dopo unione e sulla preparazione dopo nascondi/annulla. La verifica successiva riusa le48UI concluse e riprova i livelli e le regressioni pertinenti con un ampio lotto nativo, Core, Release e pacchetto reale.

## Stato del candidato

Il successivo lotto8ce ha superato Release, pacchettoPGRelease+60avvii, Core430+98, il replay e la preparazione dei livelli senza primo tocco. Restano quattro casi nativi: forma dei glifi, due oracoli di prova (seme casuale ricreato e frase PDF che va a capo), parità bitmap/PDF di un pennello con texture. La correzione usa l’istanza UIFont realmente risolta, confronta il disegno letto prima/dopo e normalizza solo gli spazi dell’estrazione PDF. La parità pixel conserva la tolleranza4 su inchiostro monolinea solido; la texture privata PencilKit non è un tracciato PDF pubblico. Gli archivi dei pennelli originali restano verificati con tutti i loro campi. Nessuna asserzione di unicità o di assenza immagini è stata rimossa.

Il PDF vettoriale ricostruisce la geometria dei pennelli con texture; per il loro aspetto raster esatto usare PNG/JPEG, per mantenerli integralmente modificabili usare il nativo. Questo limite del renderer pubblico era già presente prima dei livelli. Il nuovo test verifica inoltre che la cache dell’evidenziatore non dipinga il suo fondo bianco sul testo nero. Nel modulo del quaderno il campo nome riceve il focus iniziale, e il test aspetta la tastiera reale prima di digitare.

- Livelli veri per pagina, fino a16, con Base senza migrazione dei file precedenti. Mostra/nascondi, blocca, rinomina, duplica, riordina, opacità, svuota ed elimina sono annullabili. Il nome attivo è visibile sotto la toolbar; gli strumenti e i menu oggetti sono limitati al proprietario attivo.
- Pannello con miniature preparate una alla volta. Export PDF vettoriale/PNG/JPEG: tutti, visibili o scelti; export di un solo livello. Nativo e backup conservano anche livelli nascosti/bloccati. OCR e ricerca comprendono tutto il contenuto; la selezione parole interattiva esclude testi nascosti.
- Unione modificabile: conserva PKStroke originali, pressione, maschere, randomSeed e tempi. Una piccola composizione interna conserva ordine oggetti/marker/penna/tape e opacità dei gruppi precedenti. Nessuna rasterizzazione dei dati. Massimo128nodi,4livelli annidati e200.000riferimenti di tratto per proprietario: oltre questi limiti l’operazione fallisce senza pubblicare il nuovoheader. Se la Base riordinata viene unita sotto, resta una Base vuota anziché cancellare l’identità della pagina.
- Un solo canvas nativo con cache viewport12+36MiB; il dettaglio parte dopo il fallback e viene interrotto durante la scrittura. I buffer temporanei, l’inchiostro attivo, le anteprime e il backingUIView sono separati dal budget48MiB, quindi non chiamarlo picco totale. Il PDF resta sulla cache in background già verificata29. Baseline dell’inchiostro riusata per gesto, solo delta per campione; anche i gruppi uniti riusano la composizione immutabile durante l’aggiunta di un tratto.
- Salvataggi/annulla perproprietario, staging di fileimmutabili per azioni tra pagine e cambioformato, cancellazione pertipi su tutti i livelli visibili/sbloccati, snapshot prima/dopo con un solojournal. Gli oggetti bloccati restano esclusi; nuovoformato ridimensiona esplicitamente tutti i proprietari, anche nascosti/bloccati, senza deformare le proporzioni.
- Copia/incolla e trasferimento mantengono gruppi/opacità dei contenuti uniti, assegnano l’owner destinazione e validano prima di pubblicare. Gli eventuali rimandi audio di forme provenienti da un altro quaderno non vengono collegati a sessioni inesistenti. Le selezioni PNG mantengono alpha, senza probe opachi sullo sfondo.
- Audio: ancore perowner/occorrenza, hit sulle curve di tutti i livelli visibili, replayreadonly con cache32MiB e frame riusato tra tick; nessun insieme residente di16PKDrawing. Nuove prove sugli owner uguali/copie, Native e giornale.
- Formato pacchetto2 promosso atomicamente alla prima pagina con livelli, compresa cronologia/recupero. Nuovi quaderni senza livelli restano1. La promozione non viene annullata: una versione29 non deve aprire e risalvare un quaderno con dati30. iCloud/backend/firma/identità non sono stati modificati.

## Gate prima della consegna

1. Compilazione SDK e suite raggruppataCore/Native/UI, Release e pacchetto realePlaygrounds. Nessun esito previsto va riportato come superato.
2. Controllare il test del testo digitato di un livello parzialmenteopaco: deve rimanere selezionabile UNA volta nelPDF. I probe vettoriali potrebbero duplicarlo; correggere se rilevato.
3. Ispezionare screenshot UI Livelli e regressioni PDF/marker/Undo/zoom; confronti pixel Native prima/dopo unione, clipboard e export.
4. Verificare CRC e sorgenti dello ZIP esatto CI e solo dopo caricare la beta con la corsia autorizzata. Registrare numero effettivo e upload, senza stimarlo.
5. La prova fisica prolungata suPencil, audio lungo e standby rimane distinta dal simulatore.

## Come provarla dopo una distribuzione verificata

1. Apri un quaderno di prova, disegna una forma e apri l’icona Livelli.
2. Crea un livello e scrivi lì. Nascondilo: il contenuto sotto deve tornare pulito. Annulla: ritornano contenuto e proprietario attivo.
3. Blocca un livello, prova a selezionare e cancellare gli altri, poi sbloccalo. Trascina le righe del pannello per cambiarne l’ordine.
4. Nel menu del livello modifica nome/opacità, duplica o unisci sotto. Annulla ogni operazione; i tratti originali devono essere esatti.
5. Esporta prima solo visibili, poi tutti, poi un livello scelto. L’export non deve cambiare la pagina originale.

---
Documentazione di progetto e checkpoint storici conservati di seguito. Le loro diciture «ancora da implementare» non sostituiscono lo stato sopra.

# Fase 0.30 — progetto di integrazione, prima di cambiare il modello

Questo documento è preparazione; nessun livello è ancora attivato in produzione. Va promosso nel DELIVERY 0.30 solo dopo la consegna verificata di 0.29. Il codice corrente PDF resta sul ramo di consegna; il candidato 0.29 è nel worktree separato.

## Contratto dei dati

`layers == nil` significa esattamente la pagina attuale, con disegno nei puntatori drawingFile/previousDrawingFile esistenti. Alla prima creazione esplicita, l’elenco include la base con id == page.id, senza suoi puntatori media; gli altri id differiscono dalla pagina e hanno disegno e revisione precedente opzionali. Massimo 16 inclusa base, ordine dal basso verso l’alto, id/file senza duplicati, nomi non vuoti limitati, opacità finita 0…1. La base si può riordinare. La sua eliminazione richiede svuotamento documentato o riassegnazione atomica della convenzione: non cancellare implicitamente i suoi file.

Gli oggetti, inclusi PDFMarkup.wordHighlight e il nuovo rettangolo marker, hanno layerID opzionale; nil significa base. I vecchi file non vengono riscritti all’apertura. Gli ID vengono rinnovati in clonazione con una sola mappa condivisa da oggetti e layer. Un riferimento non valido non deve far sparire silenziosamente un oggetto: validazione e recupero devono mostrare il problema prima di attivare strumenti distruttivi.

## Blocco obbligatorio: riferimenti ai file

Le liste dei media sono oggi ripetute in WorkspaceMaintenance, NativePackageInspector, WorkspacePageEdit/PageEditSnapshot e PageEditRecovery; inoltre DocumentMerge, PageBatch e DocumentWorkspace scrivono o duplicano puntatori. Prima della UI creare un unico riferimento media di PageSnapshot, con tipi (drawing/current/previous, PDF, immagine) e usarlo ovunque. I livelli nascosti, bloccati, eliminati ma recuperabili e gli snapshot di annulla devono rimanere raggiungibili. Verificare i limiti individuali dello snapshot media anche con PDF importati oltre 100 MB: creazione/recupero non possono avere limiti diversi e fallire dopo una modifica già applicata.

Matrice minima: maintenance non elimina disegni dei livelli; clone/duplica rinnova riferimenti ma conserva i file immutabili; native export/import e snapshot cloud includono tutti i file, anche invisibili; recovery riporta pagina e puntatori insieme. Nessun nuovo servizio backend o capacità iCloud.

## Canvas e cronologia

Un solo canvas autorevole, anche con la finestra Zoom di 0.29: il canvas temporaneo chiude il tratto prima di un cambio di livello. Il livello attivo viene catturato all’inizio del tratto. Solo il suo disegno può essere sostituito o salvato. Non leggere sedici PKDrawing contemporaneamente.

Prima di cambiare livello, salva il valore live nel file immutabile corretto e aggiorna il riferimento di pagina con transazione esistente. Fallimento o chiusura interrompe il cambio conservando la selezione iniziale. Una modifica di metadati/livello usa snapshot su disco e una sola voce di annulla; non accumulare sedici archivi residenti. Il normale annulla di un tratto sul livello attivo resta il percorso in memoria. EditorContentState deve identificare il livello cui appartengono i byte; normalizzazione/equality ignorano solo puntatori di revisione, non contenuto o proprietà del livello. Testare annulla attraversando un cambio livello e annulla→nuovo tratto senza resurrezione.

## Un solo criterio per gli strumenti

Oggetti eleggibili = appartenenti al livello attivo visibile e sbloccato, meno i blocchi individuali. Applicare lo stesso criterio a lazo, gomma selettiva/scarabocchio, Seleziona tutto, comandi di stile, handle, menu contestuale, trascinamento, duplicazione, collegamenti e creazione/inserimento di testo/foto/forme/marker/righello. Il conteggio di Elimina per tipo deve chiarire l’ambito e usare gli stessi ID della cancellazione. Non filtrare solo i disegni lasciando manipolabili oggetti dei livelli bloccati.

## Disegno e memoria

Carta/PDF si disegnano una volta. Ogni livello: oggetti sotto l’inchiostro, evidenziazioni e rettangoli multiply, inchiostro, oggetti davanti; opacità sul gruppo. I livelli sopra il canvas sono overlay senza tocchi. La composizione dell’evidenziatore live include solo gli strati sotto/attivo, poi si sovrappongono gli strati superiori. Riutilizzare cache PDF 0.28.2, senza reinserire drawPDFPage sul main actor.

Le immagini dei livelli inattivi sono tasselli/viewport con un budget complessivo, non un’immagine completa per ognuno. Gli export possono caricare un livello per volta e usare il disegno vettoriale; i filtri Tutti/Visibili/Scelti non scrivono metadati o cronologia. Immagine, PDF, miniatura, OCR e cattura Lente devono condividere ordine e opacità.

## Audio, ricerca e compatibilità

StrokeAnchor deve poter identificare il livello. Copiare un livello può duplicare firme native identiche: usare una chiave composta (layerID, signature), con nil/base compatibile con tutti gli audio precedenti. Unione aggiorna la proprietà del livello e rimappa le firme senza perdere i tempi. Ancore di forme/marker e connettori seguono la medesima regola. Ricerca/OCR leggono tutti i livelli, anche quando l’export è filtrato, e invalidano risultati su modifica del layer corretto.

## Prove che bloccano la consegna

1. Vecchia pagina 0.29 apre/salva/riapre identica; nessuna migrazione o perdita di media.
2. PDF con annotazioni su un nuovo livello: nascondi → PDF pulito anche nell’export solo visibili; tutti → annotazioni presenti.
3. Strumenti tentati su livello nascosto/bloccato non cambiano metadati, disegno o cronologia.
4. Ordine base/inattivo-sotto/attivo/inattivo-sopra con pixel, multiply e opacità, anche mentre la punta è appoggiata.
5. Duplica/unisci con maschere, pressione, seed e tempi audio, più riferimenti a forme/connettori.
6. Interruzione mentre salva/cambia livello/unisce: recupero completo o stato precedente, mai puntatori misti.
7. Maintenance, backup nativo, import, annulla su disco e recupero proteggono ogni livello e PDF grande.
8. UI attiva livello, occhio, blocco, ordine, opacità, annulla e finestra di scrittura; screenshot e ZIP esatto verificati prima di TestFlight.


## Checkpoint di sviluppo

Fondazione locale: modello opzionale e validazione, riferimenti media canonici in inspector/maintenance/recovery/snapshot e remapping import; quindici test Core presenti, ancora non eseguiti con SDK. Nessuna UI livelli né gestione del canvas attivo ancora implementata. Non pubblicare questo ramo. Prima di dichiarare completa la fase servono tutti i blocchi precedenti, integrazione storage restante, adapter di scrittura, rendering e prove SDK.


Punto bloccante emerso nella ricognizione: DocumentWorkspace.save elimina direttamente il precedente disegno base assumendo proprietà esclusiva del percorso. Con livelli duplicati o uniti i file sono immutabili ma possono essere condivisi. Prima di attivare i livelli occorre un criterio di raggiungibilità canonico (anche fuori dalla pagina corrente), oppure una politica di raccolta differita limitata nello spazio; non basta verificare il prefisso del nome. Non rimuovere quella protezione senza gestire anche l’accumulo di revisioni durante registrazioni/scritture lunghe. Il codice candidato 0.29 non include questo modello sperimentale.


## Protezione delle revisioni — candidato locale

L'eliminazione delle vecchie revisioni ora consulta un indice derivato dei soli metadati, inizializzato pigramente prima della prima eliminazione e aggiornato da ogni scrittura serializzata. Include pagine cestinate, livelli nascosti/bloccati e puntatori precedenti. Recuperi con journal invalidano l'indice; un header illeggibile impedisce l'eliminazione senza impedire il salvataggio. Le revisioni senza riferimenti continuano a essere eliminate: il controllo non accumula un nuovo archivio a ogni tratto. Nessun payload PDF/audio/drawing viene caricato per costruire l'indice. Nuovi test sintetici controllano 40 salvataggi, livelli condivisi e cestinati, pulizia e un header corrotto.

API di storage candidata: lettura/salvataggio con layerID esplicito sostituisce atomicamente solo i puntatori di quel livello e conserva due revisioni per proprietario. Il percorso senza layerID resta quello base. Blocco/nascondimento rifiuta l'input esplicito prima di scrivere file. Test alterna 12 salvataggi base/livello, conserva quattro file, verifica il pacchetto e il rifiuto del livello bloccato. Nessuna UI o sostituzione del canvas ancora attivata; test SDK della fase non ancora eseguiti.


## Comandi sui metadati — candidato locale, senza UI attiva

Aggiunta, rinomina, visibilità, blocco, opacità e riordino sono trasformazioni pure con controlli comuni e limite16. Duplicazione rinnova insieme ID degli oggetti, collegamenti interni, attributi di sovrapposizione/blocco e ancore audio; le firme native restano identiche ma appartengono al nuovo livello. Gli endpoint esterni rimangono collegati agli oggetti esistenti. Il vettore viene copiato in un nuovo file immutabile senza caricarlo in memoria. L'eliminazione rimuove solo i contenuti del proprietario scelto, conserva gli altri e stacca correttamente i collegamenti rimasti senza target. La Base per ora è protetta dall'eliminazione: prima della UI completare l'azione esplicita Svuota e l'unione che coinvolge la base.

Il writer dei metadati verifica revisione e presenza di ogni file prima di un unico commit atomico dell'header. Il test controlla duplicazione bytes, conflitto di revisione, percorso mancante, invariabilità della base e pulizia delle copie eliminate. I quindici test Core complessivi di questa fondazione sono presenti e passano solo il parser, non risultano ancora eseguiti. Restano render a gruppi con opacità, livelli attivi/strumenti, annulla su disco e integrazione completa della UI. Il candidato0.29 non contiene questa fondazione.


## Unione: vincoli da risolvere prima della UI

Il merge deve conservare maschere, pressione, seed e ancore. Due livelli duplicati possono contenere tratti con identica firma: la chiave layer+firma basta prima del merge, ma non dopo. Serve disambiguare le occorrenze e aggiornare insieme replay/ancore, senza cambiare i tratti per ottenere semplicemente una firma diversa. Anche l'opacità deve essere applicata all'intero gruppo: moltiplicare separatamente l'alpha dei tratti cambia il colore delle sovrapposizioni. Non attivare un merge che rasterizzi silenziosamente l'inchiostro o perda questa composizione. Il livello Base implicito si clona ora rimappando anche gli owner espliciti della base, senza materializzare layers o migrare file.


Riferimento verificato: [Quartz, Transparency Layers](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_trans_layers/dq_trans_layers.html) e [CGContext.beginTransparencyLayer](https://developer.apple.com/documentation/coregraphics/cgcontext/begintransparencylayer(auxiliaryinfo:)). Il gruppo parte da un backdrop trasparente; quindi un semplice gruppo con multiply interno può cambiare l'evidenziatore rispetto al PDF esterno. La prova pixel deve comprendere nero del PDF sotto marker su livello a opacità parziale, sovrapposizioni interne e inchiostro bianco su carta scura. Non spostare silenziosamente tutti i gruppi su multiply né rimuovere le verifiche di leggibilità già verdi. Per i frame interattivi conservare la cache PDF in background: non ridisegnare il vettore originale sul main per ricostruire il backdrop.


Recupero vettori per proprietario predisposto con LayerDrawingReader: letture limitate a100MiB, fallback solo alla revisione precedente del livello richiesto, nessuna resurrezione quando il current è intenzionalmente vuoto. Due prove native aggiunte, ancora NON eseguite con SDK, usano veriPKDrawing per corruzione, base intatta e successivo salvataggio recovered. Un testCore aggiuntivo passa da snapshot su disco e journal con cache reachability già calda: il successivo save non può eliminare il file che il nuovo livello nascosto ha acquisito. QuindiciCore+dueNative sono ora presenti nella fondazione, NON risultati di test SDK.


Predisposta la cattura dei riferimenti base nella cronologia su disco (`preservingBaseReferences`, defaultfalse conserva il comportamento precedente). Le operazioni sui livelli potranno conservare tutti i vettori immutabili senza sediciPKDrawing inRAM e ripristinarli anche dopo pulizia del pacchetto. Il journal pubblica i puntatori dello snapshot solo dopo aver ripristinato tutti i file. Un testCore alterna modifiche base/livello, forza pulizia e ripristina byte e puntatori originali. La gestione della cronologia nell'editor non è ancora collegata allaUI livelli.

Audio: `strokeOccurrence` opzionale distingue copie identiche dopo il merge senza cambiare nativo/seed/pressione. `LayerStrokeTimeline` filtra proprietario, preserva wildcard dei documenti precedenti ed espande/ribasa le occorrenze con i tempi originali. Gli orphan restano fuori dal disegno e non si agganciano a tratti importati con uguale firma. Quattro proveCore presenti, nonSDK; il replay e il tap audio nell'editor devono ancora usare questo scope. Il writer/audio di0.29 rimane separato e immutato da questo candidato.


Aggiornamento locale 5 novembre: predisposto il passaggio di proprietario nel singolo canvas. `selectLayer` conclude e salva il livello precedente prima di leggere il successivo; lettura fallita o livello nascosto/bloccato lascia intatto il canvas. Il writer aggiorna soltanto il file del proprietario attivo; il rebase conserva nomi/opacità/livelli aggiunti durante un salvataggio. La cronologia in memoria identifica il proprietario e cambia livello prima di applicare annulla/ripristina incrociati. La UI non espone ancora questi comandi: compositore e scope di tutti gli strumenti restano prerequisiti. Aggiunti tre test nativi (annulla/ripristina tra proprietari con pressione, destinazione corrotta, livello nascosto/bloccato) e due Core (svuota Base conservando PDF/altri livelli/collegamenti e rebase durante scrittura). `clearing` svuota anche la Base senza migrare i file né eliminare PDF. Fondazione totale: 22 test Core e 5 nativi PRESENTI, non eseguiti con SDK. Parser locale:479 Swift/713 metodi XCTest presenti, grafo734; nessuna CI aggiunta per questo lotto parziale. Non pubblicare né integrare nella 0.29.


Operazioni editor dei livelli predisposte sul journal esistente: nuovo, duplica, rinomina, mostra/nascondi, blocca, opacità, ordine, svuota ed elimina preparano due snapshot su disco con tutti i vettori raggiungibili, quindi pubblicano una sola modifica annullabile. Il cursore cronologico conserva anche il proprietario prima/dopo: annullare una cancellazione ripristina i vettori e il canvas corretto. La duplicazione prepara un file immutabile indipendente prima del commit, senza pubblicare prematuramente la pagina. Due ulteriori prove native coprono annulla di nuovo livello→inchiostro→nascondi e duplica→modifica→elimina con ripristino dei byte, conservando la base e il sorgente. Totale fondazione:22 Core+7Native PRESENTI, nonSDK; parser480Swift/715 metodi e grafo736. Questi comandi rimangono interni, senza pulsante UI, finché compositore, strumenti, merge, export e audio non sono completi e verificati. Nessun TestFlight/SDK30 avviato.


Il confine comune `mutatePage` ora limita gli oggetti al proprietario attivo con LayerObjectEdits, senza togliere agli algoritmi geometrici i riferimenti agli altri livelli. Oggetti esistenti fuori ambito o bloccati vengono conservati, quelli nuovi ricevono il proprietario corretto, comprese le ancore di forme/connettori; nascosto/bloccato non acquisisce contenuti. Tre proveCore aggiunte per proposte estese alla pagina, blocchi, inserimenti, ancore e pass-through identico dei documenti legacy. Questo è solo il confine comune: gli accessi diretti di tutti gli strumenti devono ancora essere controllati prima dellaUI. Totale25Core+7Native presenti; parser482/718, grafo738. Tutti NONSDK, nessun upload30.


Piano di composizione Core predisposto: LayerRenderPlan conserva ordine intero dei proprietari e stadi interni (annotazioni, oggetti sotto, marker, inchiostro, oggetti davanti e nastri), riferimenti immutabili e opacità del gruppo. Filtri Tutti/Visibili/Scelti sono in sola lettura e non nascondono gli oggetti bloccati. Tre proveCore coprono legacy, selezione nascosta/visibile e riordino con marker/nastri. Non è ancora il compositore pixel o il renderer vettoriale: quelli devono consumare questo piano e rispettare il backdrop multiply. Totale28Core+7Native PRESENTI, parser484Swift/721metodi, grafo740; NONSDK.

Gate aggiuntivo prima della UI: la versione0.29 ignora i campi layer opzionali. Evitare di permettere a un downgrade di salvare/pulire un documento con livelli: valutare promozione atomica del solo manifest a formato2 al primo livello esplicito, lasciando i documenti legacy a1, con reader/import/clone/recovery1+2 e protezione dal ripristino di un manifest1 sopra pagine a livelli. Nessuna promozione o modifica di formato è ancora implementata; va completata con prove crash/rollback prima di esporre i livelli.


Scope preliminare esteso a selezioni/tocco/lazo tramite storage selezione filtrato, snap, campi testo, ingresso penna/guide, rettangolo marker e indice spaziale della gomma (calcolato al gesto, non a ogni punto). Il passaggio di livello conclude il campo testo e conserva il proprietario della sua voce di annulla. La gomma parziale preserva ora ancore di altri livelli e rimappa soltanto le occorrenze sopravvissute: mantiene tempi e ID, espande wildcard senza duplicare ID e non riaggancia orphan a firme nuove. Documenti senza layers mantengono il percorso audio precedente. Aggiunti un testNative di testo/selezione/passaggio e dueCore per ancore dopo cancellazione. Totale30Core+8Native PRESENTI; parser484Swift/724metodi, grafo740. Nessuna verifica SDK30 o attivazioneUI. Mancano ancora l’audit degli altri writer diretti (scansioni/import/incolla/forme/scarabocchio/tipo), il compositore, merge, export, indicizzazione multistrato e replay/tap multistrato: non dichiarare gli strumenti già completi.


Protezione del formato implementata nel candidato locale: i documenti legacy restano manifest1; il primo header con livelli promuove atomicamente main e recovery a2 prima di pubblicare gli oggetti. Nessun file di inchiostro viene migrato. Reader/inspector/clone/journal accettano1+2, le scritture di un ordine catturato sotto1 non possono retrocedere un pacchetto2. Recupero esplicito controlla anche header delle pagine conservate nel cestino e non ripristina formato1 sopra livelli, neppure con main corrotto; i formati futuri sconosciuti vengono preservati e rifiutati. Sei nuove proveCore per prima promozione, ordine stale, crash fra main/recovery, recupero con livelli nel cestino, clone/Undo e backup futuro99 non sovrascritto. Totale36Core+8Native PRESENTI, nonSDK. Il catalogo audio rimane formato1; nessun backend/iCloud modificato. Questo supera il precedente gate di progetto solo come implementazione candidata, ancora da verificare con SDK nella fase completa.


## Composizione affine candidata (non ancora collaudata con SDK)

Le operazioni Normal/Multiply del contenuto sono affini sul backdrop opaco: F(c)=a·c+b. Due prove del contenuto su nero e bianco danno b e w=a+b. Il compositore usa soltanto blend standard del PDF: Multiply con (w−b)/(1−b), poi Screen con b. Difference e ColorDodge costruiscono il coefficiente, senza ridisegnare il PDF esterno e senza applicare l’opacità a ogni singolo oggetto. L’opacità del gruppo entra nelle due prove prima dei coefficienti. Un gruppo al100% usa direttamente il percorso precedente, senza passaggi aggiuntivi. Per lo schermo vengono conservate due mappe opache con costo reale; il percorso PDF emette i comandi vettoriali nelle trasparenze. Riferimento primario: [ISO32000-1 tabella136](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf) e [correzione Adobe sui blend](https://www.adobe.com/content/dam/cc1/en/devnet/pdf/pdfs/adobe_supplement_iso32000_1.pdf). Questa derivazione è progetto/implementazione, non prova empirica del renderer Apple.

PageRenderer ora espone carta/PDF separati e contenuto di un proprietario, mantenendo il percorso legacy equivalente. LayeredPageRenderer esporta sequenzialmente un solo PKDrawing per proprietario, con filtri Tutti/Visibili/Scelti e override del disegno live corretto. PDF e immagine condividono stadi/opacità; nessun UIGraphicsPushContext viene mantenuto attraverso await. ExportPDF accetta anche un insieme di pagine per esportare soltanto un livello della pagina corrente. Exportimmagine dell’editor usa il percorso async e conserva la selezione PNG trasparente precedente.

Sette nuove proveNative PRESENTI: pixel su diversi sfondi/opacità e sovrapposizioni, nero del PDF e inchiostro bianco, PDF con font selezionabile e nessuna XObject immagine per l’inchiostro, limiti/origine mappe; inoltre exportVisibili/Tutti/Scelti, opacità PDFvsimmagine/vettori, override live senza cambiare i file. **Non eseguite con SDK.** Da verificare prima della consegna anche estrazione senza duplicazioni dei testi dei livelli con opacità parziale, oltre al budget del viewport e alla cache in preparazione. Nessuna UI Livelli ancora attivata né nuova build pubblicata.


Checkpoint locale — composizione, cache e confini editor, 5 novembre 2026. NON SDK, NON distribuito.

- LayerScene/LayerSceneView collegano al singolo canvas una composizione trasparente ai tocchi. Fallback completo12MiB e dettaglio viewport36MiB perhost; i buffer temporanei, l’inchiostro attivo e il backingUIView sono separati da questi48MiB. Gli archivi inattivi sono letti uno alla volta e rilasciati. Nessun nuovo decode PDF sulMain. I documenti layers=nil seguono il percorso29.
- Inchiostro vivo: baseline rasterizzata una volta pergesto e soli nuovi tratti percampione. Massimo1,5MP perimmagine diinchiostro, massimo4immagini baseline/delta e marker/penna. Proprietari inattivi riusati su scrittura/testo attivi. Le mappe dipendono anche da oggetti temporaneamente nascosti e bersagli di connettori tra livelli.
- Preparazione automatica di pagina/livello, stato reale Pronto/Preparazione e protezione del primo input durante preparazione; fallimenti non generano retry infiniti. Memorywarning elimina dettaglio/ink temporanei; nessuna scrittura dello stato visivo neiPKDrawing. Anteprima riconoscimento e marker compongono gli altri livelli senza sostituire il contenitore nativo.
- Anteprime vicine, copertina ultima pagina, navigatore, girofoglio, OCR manuale/automatico, selezione OCR e Lente usano il compositore asincrono. OCR/ricerca possono comprendere tutti i proprietari; selezione parole visibili esclude testo/etichette nascosti. AreaRecognition non decodifica più inbody.
- Audio: nuove ancore sui livelli con owner e occorrenza; hit audio segue le curve dei proprietari visibili, letti sequenzialmente. Replay readonly a timeline indipendenti, mappe32MiB totali e frame riusato fra tick senza nuovi tratti; non conserva16PKDrawing. Non cambia i file o la cronologia.
- Tutti i recordEdit dei normali editor diretti passano dal confine dei proprietari, inclusi nuovi oggetti/ancore; carta/formato ha un percorso esplicito globale. Incolla assegna l’owner destinazione; scarabocchio protegge gli altri testi. Copia/spostamento tra pagine e cambioformato preparano file immutabili di ogni owner e usano due snapshot completi con un unico journal. Annulla ripristina anche owner e inchiostroBase, compresi nascosti/bloccati durante cambioformato. I ricostruttori di stroke mantengono randomSeed.
- Aggiunte proveNative su pixel/caches/Native invariato, riuso baseline, hit/replayaudio, clipboard e editor diretti, trasferimento incrociato conUndo, formato multiproprietario. Nuova provaCore sullo staging non pubblicato e ripristino atomico. Un nuovo test verifica esplicitamente che il testo digitato di un livello parzialmenteopaco sia selezionabile UNA volta nelPDF: esito SDK ancora da acquisire, possibile punto da correggere nei probe vettoriali.
- Gate ancora aperti: merge senza perdita di pressione/maschere/ordine/opacità; pannello Livelli ed export filtrato accessibili inUI; finire audit eliminazione pertipi e contenuti negli import; prova SDK/QA memoria/pixel/ZIP esatto eTestFlight. Nessuna UI Livelli attiva, nessuna0.30 inROOT, nessun caricamento nuovo. Non dichiarare conclusa0.30.

Verifica42119500167: Core430+98,269Native con3asserzioni fallite in2casi, tutte5UI passate, Release ePGRelease+60avvii passati. Restano differenza di hinting dei glifi (3.238 contro limite3) e colore del PDF semitrasparente (canali29/21 contro4); non allentare i limiti. Il nuovo candidato disegna gli stessi contorni nei passaggi dei coefficienti e nel risultato finale, emettendo il testo selezionabile invisibile una sola volta; il test richiede anche gli accenti italiani. Imposta inoltre un profilo di output sRGB esplicito al posto del contesto PDF senza profilo. L’output intent non dichiara conformità PDF/X. Nuove prove allegate: PDF sorgente e bitmap/PDF per isolare eventuali differenze cromatiche residue. Non distribuito finché verificato.
