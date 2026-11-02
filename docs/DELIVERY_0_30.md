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

Solo fondazione locale: modello opzionale e validazione, riferimenti media canonici in inspector/maintenance/recovery/snapshot e remapping import; quattro test Core. Nessuna UI livelli né gestione del canvas attivo ancora implementata. Non pubblicare questo ramo. Prima di dichiarare completa la fase servono tutti i blocchi precedenti, integrazione storage restante, adapter di scrittura, rendering e prove SDK.


Punto bloccante emerso nella ricognizione: DocumentWorkspace.save elimina direttamente il precedente disegno base assumendo proprietà esclusiva del percorso. Con livelli duplicati o uniti i file sono immutabili ma possono essere condivisi. Prima di attivare i livelli occorre un criterio di raggiungibilità canonico (anche fuori dalla pagina corrente), oppure una politica di raccolta differita limitata nello spazio; non basta verificare il prefisso del nome. Non rimuovere quella protezione senza gestire anche l’accumulo di revisioni durante registrazioni/scritture lunghe. Il codice candidato 0.29 non include questo modello sperimentale.


## Protezione delle revisioni — candidato locale

L'eliminazione delle vecchie revisioni ora consulta un indice derivato dei soli metadati, inizializzato pigramente prima della prima eliminazione e aggiornato da ogni scrittura serializzata. Include pagine cestinate, livelli nascosti/bloccati e puntatori precedenti. Recuperi con journal invalidano l'indice; un header illeggibile impedisce l'eliminazione senza impedire il salvataggio. Le revisioni senza riferimenti continuano a essere eliminate: il controllo non accumula un nuovo archivio a ogni tratto. Nessun payload PDF/audio/drawing viene caricato per costruire l'indice. Nuovi test sintetici controllano 40 salvataggi, livelli condivisi e cestinati, pulizia e un header corrotto.

API di storage candidata: lettura/salvataggio con layerID esplicito sostituisce atomicamente solo i puntatori di quel livello e conserva due revisioni per proprietario. Il percorso senza layerID resta quello base. Blocco/nascondimento rifiuta l'input esplicito prima di scrivere file. Test alterna 12 salvataggi base/livello, conserva quattro file, verifica il pacchetto e il rifiuto del livello bloccato. Nessuna UI o sostituzione del canvas ancora attivata; test SDK della fase non ancora eseguiti.
