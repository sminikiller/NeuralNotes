# Roadmap NeuralNotes — 0.9.0

Le sette aree richieste sono sviluppate nella [consegna 0.9](docs/STUDY_WORKSPACE_0_9.md): rendering visibile e cache, versioni automatiche dei backup, penne e gomma selettiva, testo formattato/scanner/inserimenti, PDF affiancato, indice persistente/OCR e Lente AI. La sincronizzazione CloudKit è implementata e predisposta per il Team ID `64R668842U`, ma non attivata né provata sul servizio reale. Gli esiti effettivi della build sono in [VALIDATION.md](docs/VALIDATION.md).

Prossime verifiche e attività:

1. Completare le prove fisiche sull’iPad 10, soprattutto input Pencil, scanner, nitidezza, memoria e registrazioni lunghe con standby.
2. Attivare App ID/contenitore/profilo di firma nel team Apple e provare CloudKit su due dispositivi con modifiche concorrenti. Cartelle e cancellazioni cloud richiedono ancora un protocollo dedicato.
3. Pubblicare e configurare il backend HTTPS, poi misurare qualità e latenza delle risposte AI sulle fonti. Nessuna risposta live è stata provata.
4. Eliminare il possibile secondo contatto sulle pagine molto grandi/non preparate durante un salvataggio; completare la pipeline delle anteprime fuori dal percorso di interazione e misurare archivi grandi.
5. Aggiungere checklist interattive, continuazione degli elenchi, trascinamento PDF e maniglie libere per trasformare selezioni; estendere OCR automatico ai quaderni esistenti con elaborazione controllata.

Non viene dichiarata la parità con Goodnotes. I limiti concreti di ogni area sono elencati nella guida 0.9, separati dalla presenza del codice e dalle prove automatiche.

## Storico fino alla 0.8.1

**Stato attuale:** consolidamento del salvataggio/recupero, correzione del compilatore e CI macOS privata attiva. Gli esiti correnti sono in [VALIDATION.md](docs/VALIDATION.md); le indicazioni di mancata verifica nelle voci precedenti descrivono lo stato storico di quelle consegne. La prova fisica su iPad resta separata.

**0.7:** verticale continuo con fogli ravvicinati nello scroll del canvas, offset preservato, prefetch e attivazione sicura; voltata orizzontale curl e alternativa Riduci movimento. [Prove correnti](docs/TESTING_0_7.md). Nessuna verifica SDK/animazione reale eseguita qui.

**0.6.1:** correzione della regressione segnalata sul layout e sull’input Pencil. Ripristinato il canvas unico a tutta area, sfoglio verticale/orizzontale con dita e blocco durante scrittura. Il precedente stack continuo viene rimosso. [Prova corrente](docs/FIXES_0_6_1.md).

**0.6:** modalità di navigazione verticale/orizzontale/singola, correzione competizione doppio tocco, commit differito dello scarabocchio, testo in pagina con UITextInput e lettore completo delle trascrizioni; recupero/checkpoint vuoti e retry. [Prove correnti](docs/TESTING_0_6.md). Implementato, ancora da compilare/provare con SDK e hardware Apple.

**0.5.1:** correzioni per standby/background, doppio tocco pagina intera, cancellazione locale e azioni Audio separate; [prove mirate](docs/FIXES_0_5_1.md). Registrazione reale in background da verificare nel runner.

**0.5:** percorso PDF dalla libreria separato dai backup; modelli carta per quaderno/pagina, focus completo flottante, avanzamento al fondo e scarabocchio configurabile. Trascrizioni con checkpoint e pausa/ripresa, rinomina, correzioni ed export per minuto. [Accettazione corrente](docs/TESTING_0_5.md). Le nuove funzioni sono implementate ma non ancora compilate/provate qui con SDK Apple. Le sezioni successive conservano il quadro della 0.4 e i gate generali.

La 0.4 implementa le tre priorità richieste: editor con cronologia oggetti/pagine, ripristino schede e più scene; inchiostro vettoriale nel PDF; recupero/spazio e nuove prove. Aggiunge fotocamera, ritaglio, forme e selezione mista. **Implementato non equivale a verificato su iPad**: nessuna build Apple della 0.4 è stata eseguita qui.

| Modulo del piano iniziale | Presente nel codice | Verifica o lavoro ancora necessario |
|---|---|---|
| Libreria | Cartelle/sottocartelle, copertine fotografiche, cestino, ricerca titoli, ordinamento | Regressione multiwindow e accessibilità sul dispositivo |
| Editor | PencilKit, strumenti rapidi, foto/camera/crop, forme, selezione e gruppi, undo oggetti/pagine | Gesti lazo/cancellazione, precisione crop, latenza, memoria, tastiera e tre dita |
| Pagine e finestre | Sei schede, ultima pagina, SceneStorage, librerie separate e lease del writer | Ripristino della scena e supporto multiwindow del processo Playground |
| PDF/documenti | Originali separati, import, export vettoriale o aspetto PencilKit, nativo/merge | Confronto visuale dei pennelli e di PDF ruotati/croppati complessi, export molto grandi |
| Audio | Segmentazione, timeline, ancoraggi, pause/interruzioni e recupero durata CAF | Registrazioni reali di 60–120 minuti, drift, spazio scarso, interruzioni ed errore hardware |
| OCR/Speech/ricerca | Vision, Speech on-device a finestre, ricerca pagina/minuto e embedding opzionali | Grafia reale, modelli italiani sul dispositivo e misure su archivi grandi |
| AI e studio | Estrazione locale con fonti, flashcard/ripasso, client e backend remoto modulare | Hosting/segreti/modello, prova live e qualità del tutor; classificazione e visione generativa |
| Recupero/spazio | Indice precedente, orfani, recupero pagine, report e pulizia protetta | Crash durante commit reali, disco pieno, migrazioni future, svuotamento fisico del cestino quaderni |
| Cloud | Disegno local-first e confini del writer | CloudKit/outbox/conflitti, account/entitlement e prove a due dispositivi; come previsto, non attivato prematuramente |
| Distribuzione | Progetto Xcode, target di test e Playground generato | SDK/build effettivi, firma, archivio, TestFlight/App Store e profilazione |

## Gate 0.4

1. Compilare il Playground 0.7; eseguire i 26 controlli incorporati, incluso il backup precedentemente fallito.
2. Completare [TESTING_0_4.md](docs/TESTING_0_4.md) su una copia temporanea: foto/crop, gruppi, cronologia, riavvio, finestre, PDF e recupero.
3. Eseguire la prova sintetica facoltativa e poi le prove reali lunghe, annotando tempi e risultati.
4. Appena disponibile un ambiente Apple completo, eseguire i 140 XCTest e build Debug/Release. Nessuna prova manuale sostituisce questi controlli.
5. Valutare i problemi misurati prima di aggiungere indicizzazione persistente, cache più aggressive o un renderer differente.

Non si dichiara raggiunta la parità funzionale o qualitativa con Goodnotes. L’AI locale estrattiva non viene presentata come modello generativo e la disponibilità di embedding non viene simulata. Il vecchio gate di Fase 1 è conservato nello storico: l’utente ha autorizzato il proseguimento dopo le proprie prove manuali.

## Zoom con doppio tocco 0.7.1

CanvasHost alterna lo zoom minimo e la larghezza esatta della pagina attiva, eliminando gli inset laterali nella seconda vista. Il ritorno a Pagina intera ripristina gli inset e il centraggio. Il flusso verticale usa la stessa regola laterale e mantiene coordinate locali dell’inchiostro. Due nuove regressioni di integrazione e test UI aggiornato, non eseguiti con SDK Apple. [Prova iPad](docs/FIXES_0_7_1.md).

## Workspace e input 0.8

Il catalogo v1 aggiunge campi opzionali editorWorkspaces e coverDesign; gli endpoint normalizzati opzionali delle forme mantengono compatibilità con le diagonali precedenti. Workspace e palette per attività sono validati e salvati con mutatori del catalogo che conservano sessioni/media. Il monitor touch osserva PencilKit senza impedire i recognizer nativi, mostra anteprime e corregge un solo tratto dopo il commit. La toolbar è un overlay sul canvas; la mini toolbar focus usa i primi tre preferiti. Recenti della libreria locali, stile copertina incluso nel backup. [Prove e limiti](docs/TESTING_0_8.md).

## Consolidamento 0.8.1

Flush inchiostro/testo prima delle configurazioni e svuotamento delle modifiche concorrenti; blocco cambio pagina/strumento durante il tratto. Catalogo precedente dentro recovery, ripristino esplicito con conservazione dei byte interrotti e protezione dei media. Clone/import aggiorna le identità del catalogo recuperabile. Classificatore geometrico riscritto in operazioni Double esplicite dopo errore reale di Playground. Workflow macOS e baseline Git. [Prove](docs/CONSOLIDATION_0_8_1.md).
