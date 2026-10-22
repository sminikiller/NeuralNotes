# Piano di Claude — verifica e avanzamento

Fonte: documento dell’utente «NeuralNotes — stato del progetto (0.7.1) e roadmap delle funzionalità», allegato del 20 ottobre 2026. Il codice di partenza di questa lavorazione è la 0.9.1, commit `f9867b6`. La richiesta attuale autorizza sviluppo e test autonomi di tutti i lotti, senza altre domande.

Il documento viene usato come specifica di prodotto. Le dichiarazioni sulle API, sui servizi e sulle versioni future richiedono conferma nelle fonti ufficiali; non diventano automaticamente API disponibili sull’iPad 10 con iPadOS 18.

Aggiornato alla **0.17.0/build 31**, 22 ottobre 2026. «Aggiunto» significa implementato nei sorgenti; non implica che la schermata sia stata compilata o provata sull’iPad. [Consegna e comandi](DELIVERY_0_12_0.md), [patch di compilazione](FIXES_0_12_2.md), [evidenze delle verifiche](ROADMAP_VALIDATION.md).

La foto successiva documenta due errori SDK reali nella 0.14.0 (delegato ereditato di PDFView). [Patch 0.14.1](FIXES_0_14_1.md): nessuna conformità o metodo delegato ridichiarati; filtro sul riconoscitore Pencil dedicato. Non ancora compilata con Apple.

## Editor e piattaforma 0.17

Corrette le quattro cause identificate nel cestino, nella guida del righello, nella prima presentazione del ritaglio foto e nel layout del testo. Aggiunto backend DeepSeek con streaming, autenticazione Supabase verificata, quote SQL atomiche, hub/materiali/inviti/report/blocchi e salvataggi cloud versionati con controllo dei conflitti. Non significa account, community o sincronizzazione già disponibili nell’app: mancano integrazione nativa e attivazione del servizio. Non è completata l’intera roadmap. [Piano e stato per componente](AI_COMMUNITY_PLAN_0_17.md), [test e consegna](DELIVERY_0_17_0.md).

## Apertura e fluidità 0.16

Eliminate due scansioni ridondanti dei JSON all’apertura e la scansione completa al cambio pagina. Manutenzione dopo inattività e cancellabile, nessuna nuova scansione/backup dal flush pulito o chiusura; lettura durate di recupero audio senza player sul MainActor; massimo tre anteprime vicine da 800 pixel, barra numeri lazy e tempi delle fasi visibili. **L’elenco iniziale conserva ancora tutti gli oggetti dei JSON: l’indice interamente su richiesta resta da sviluppare.** Benchmark Core 6/12/300 pagine, backup cancellato e suite 184 (due skip) + 98 passati; due nuovi test Apple non eseguiti. Nessuna garanzia di un secondo sul dispositivo. [Analisi e limiti](PERFORMANCE_0_16_0.md).

La seconda foto prova un errore rimasto nella 0.15.1: override mancante di gestureRecognizerShouldBegin in RulerGuideView. [Patch 0.15.2](FIXES_0_15_2.md), sintassi ricontrollata ma compilazione Apple non eseguita.

La build iPad 0.15.0 è fallita per il selettore `move:` del righello, già ereditato da UIResponder. La [patch 0.15.1](FIXES_0_15_1.md) usa nomi di azione dedicati. Controlli sintattici superati; compilazione SDK Apple della patch ancora non eseguita.

## Correzioni e richieste 0.15

Implementati cestino pagine e selezione multipla con undo/ripristino, cestino conservato nel trasferimento nativo, strumenti Solo foglio da uno a cinque con etichetta esplicita, guida del righello che vincola i campioni al bordo scelto, cache dei ritagli e commit del movimento al rilascio, inserimento e modifica del testo direttamente sul foglio con barra compatta e Scribble. La guida sostituisce il solo righello visivo nativo descritto nel lotto precedente.

Corretti ordine dei backup e confronti fra alias dei percorsi; lettura coordinata degli import e recupero dei pacchetti senza indice nel contenitore corrente, più import da cartella come copie. Nessun file fallito dell’utente è disponibile: il suo recupero non è dichiarato riuscito. **182 Core (due skip) + 98 FSRS passati**; quattro nuovi metodi Apple non eseguiti e test UI aggiornato. Restano aperti compilazione SDK, comportamento hardware Pencil/Scribble e misure di fluidità. [Dettagli e comandi](DELIVERY_0_15_0.md).

## Lotto aggiuntivo 0.14 — editor, PDF e budget

Implementati eliminazione di qualsiasi pagina dalle anteprime con undo, strumenti focus salvati separatamente per attività, popup sul lato interno, H1/H2/Corpo e colori/evidenziazione RTF, linea campionata con aggancio ±6° e rettangoli ruotati, salti audio ±15 s. In questo lotto il righello usava PencilKit nativo; la 0.15 lo sostituisce con la guida vincolante descritta sopra, con prova fisica ancora aperta.

Compressione AAC mono 64 kbps solo fuori da registrazione/trascrizione/ascolto, buffer limitati, verifica temporale e journal riprendibile; aggiornati catalogo precedente, export, backup/import, lettura ASR e pannello spazio. Il ramo Claude 9a79d58 è stato usato come bozza non compilata, non come codice già verificato. Budget dei backup con due copie protette e indicazione dello spazio. Import PDF/foto preparati fuori dal thread UI; append PDF con un solo manifest. Nuovo PDF esterno affiancato senza import, estratti e ricerca da selezione/cerchio/sottolineatura esplicita; i PDF scansiti esterni richiedono ancora OCR tramite import.

**174 XCTest Core (due skip) e 98 FSRS passati**; sei nuovi metodi Apple e due controlli diagnostici predisposti, non eseguiti. CI Apple ancora bloccata dalla fatturazione. [Dettagli e comandi](DELIVERY_0_14_0.md), [piano AI e ciò che resta aperto](AI_FUNCTIONAL_PLAN.md). Questo lotto non completa le funzioni AI avanzate o tutta la roadmap.

## Difetti segnalati prima dei lotti

| Voce | Intervento | Verifica |
| --- | --- | --- |
| Rettangolo del testo Pencil | UITextView trasparente e non opaca, senza bordo netto; contenuto del foglio visibile durante la modifica. | Nuova prova unit su carta e PDF. |
| Gomma evidenziatore a scatti | Maschere vettoriali ritagliate direttamente, filtro per tipo e bounding box; aggiornamento durante il gesto a gruppi di campioni, undo unico e ripristino su annullamento del gesto. | Prove penna intatta, aggiornamento durante il gesto, cancellazione parziale/per tratto e undo. Prestazioni hardware ancora da misurare. |
| Opzioni tenendo premuto lo strumento | Popover ancorato al pulsante per penna, evidenziatore, gomma, selezione, forme, testo, righello e Lente. | Test UI della pressione prolungata su penna e gomma. |
| Foto/fotocamera/scanner | Presentazione unica per sorgente; crop soltanto al completamento della chiusura; selettore PHPicker, permesso camera comune e errori visibili. | Test cancellazione picker e nuova prova UI; camera/scanner fisici non disponibili al runner. |
| Inchiostro precedente sul PDF | Importazione esclusiva nel modello, viewport bloccato durante IO, caricamento con delegate sospeso e sincronizzazione immediata della nuova pagina. | Tre pagine PDF dopo inchiostro/testo non salvati; controllo separazione dei dati e ritorno alla pagina originale. |

Prima esecuzione Apple `39476567717`: tutti i 168 metodi unit/integrazione (due esclusioni specifiche del simulatore) e il test popover passati. Un test UI del picker ha selezionato il pulsante Annulla sottostante: gerarchia esportata e test corretto per cercare nella barra di navigazione del selettore. L’esito finale va registrato dopo la nuova esecuzione, senza considerare PASS una run fallita.

## Fase 0 — fondamenta

1. Git e versioni: presenti; una sola lavorazione scrive nel progetto, branch `codex/editor-reliability-and-roadmap`.
2. Build senza Mac: Playground generato e CI macOS/simulatore esistenti. Distribuzione firmata ancora dipendente da chiave privata/profilo e configurazione Apple; il `.cer` fornito è pubblico e non contiene la chiave privata.
3. Sonda SDK: presente nei controlli incorporati. Le API iOS 26/27 non sono una soluzione utilizzabile su iPadOS 18.
4. Rendering: dettaglio del viewport e cache PDF/immagini presenti; pipeline delle anteprime e primo contatto universale ancora da completare.
5. Indice: snapshot persistente per revisione e ricerca globale presenti; filtri per contenuto/cartella ed evidenziazione dei risultati aggiunti.
6. Backup: versioni locali presenti; aggiunta destinazione esterna tramite bookmark di una cartella File, copia coordinata e rotazione indipendente; prova con provider File reale ancora aperta.

## Fase 1 — scrittura

1. Penne/preset: presenti, accessibili ora anche dal popover.
2. Colori: palette per attività/strumento presenti; aggiunto input HEX. Il selettore colore usa quello di sistema.
3. Gomma: presente e corretta nel lotto iniziale.
4. Forme tenute: linea/ellisse/rettangolo presenti; aggiunti triangolo orientato e freccia con testa, con campioni nativi PencilKit.
5. Gesti dita: aggiunti due dita per undo e tre per redo; menu contestuale oggetto con copia/duplica/livelli/blocco/Lente/elimina aggiunto.
6. Pencil: aggiunti doppio tocco/squeeze/hover con verifica di disponibilità iOS 17.5 per l’hardware che li supporta; non sono disponibili sulla Pencil dell’iPad 10.
7. Selezione: trasformazioni presenti; aggiunti lazo libero, copia area immagine, conversione OCR, spessore e azione AI diretta. Aggiunto spostamento dedicato tra pagine con adattamento al foglio, anchor audio rimappati, transazione con journal e undo unico; copia/incolla tra pagine/quaderni già presente. Taglia ora elimina solo se la copia riesce, e duplica non riutilizza più gli appunti precedenti dopo una copia rifiutata.
8. Testo: RTF presente; aggiunti continuazione degli elenchi e checklist azionabili senza entrare in modifica.
9. Finestra zoom: aggiunto navigatore visivo separato, senza un secondo canvas scrivibile; finestra di scrittura ingrandita dedicata ancora da completare.
10. Continuità: viewport unico presente; input freddo grande durante IO ancora protetto con attivazione differita.
11. Presentazione: righello presente; aggiunto laser temporaneo sullo schermo corrente, senza modificare l’inchiostro. Uscita dedicata su schermo esterno ancora da sviluppare.
12. Nastro per ripasso: aggiunto, con svelamento sul foglio, undo, backup ed export.
13. Post-it/timbri/livelli/blocco: aggiunti; oggetti sopra o sotto l’inchiostro, blocco della selezione e duplicazione con identità indipendenti.
14. Carta: aggiunti Cornell, agenda settimanale, pentagramma, isometrico, millimetrato e mappa; aggiunto modello PDF personale per le pagine successive, senza riprendere gli appunti del modello.
15. Scanner/drop/link: presenti; correzione media nel lotto iniziale. Aggiunto drop PDF tramite copia del file mentre il provider lo rende disponibile, separato dall’import dei backup; drop immagini/testo/link verificano ancora la pagina e lo stato dell’input dopo le attese. Se la pagina è occupata, l’errore è esplicito. Prove con app sorgenti reali ancora aperte.

## Fase 2 — Lente e account AI

Pannello, area/selezione, streaming backend, fonti, conversazione, inserimento e flashcard sono presenti. Aggiunti selettore unico offline/backend/OpenAI/Claude/Gemini/Responses compatibile, credenziali distinte nel portachiavi, consenso per motore/destinazione/modello, glossario modificabile con fonti, dizionario di sistema dalla selezione e cache persistente limitata a 32 risposte per selezione/azione. I provider personali restituiscono il risultato finale, mentre il backend mantiene lo streaming reale. Scheda strutturata `/v1/lookup`: definizione/spiegazione/esempi/termini correlati, citazioni verificate, inserimento e glossario. La 0.12 aggiunge il menu sul testo nativo selezionato, la sottolineatura nello strumento Lente e il popup espandibile; lettura delle fonti e invio protetti da selezioni obsolete. Aggiunta ricerca web **esplicita e separata** `/v1/research`, con invio del solo termine, consenso, abilitazione server inizialmente spenta, ricerca effettiva richiesta e citazioni URL cliccabili, cache di un’ora e inserimento RTF annullabile. Ventitré test backend locali passati con fixture; nessuna chiamata live. [Verifica di API, login e opzione economica](AI_API_AND_LOGIN.md). Hosting e credenziali non sono configurati; login ChatGPT senza client registrato non viene simulato.

Sono state consultate le fonti ufficiali OpenAI [sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), [disponibilità](https://developers.openai.com/siwc/quickstart), [output strutturati](https://developers.openai.com/api/docs/guides/structured-outputs) e [ricerca web](https://developers.openai.com/api/docs/guides/tools-web-search). Identità e uso del piano sono autorizzazioni distinte; la disponibilità documentata non equivale all’abilitazione di questa app privata. Non viene inventato un client ID o riutilizzato un client di un’altra app.

## Fase 3 — ricerca e organizzazione

1. Ricerca globale: presente; aggiunti filtri testo/PDF/grafia/audio/glossario e cartella, con anteprima centrata sulla corrispondenza e testo evidenziato. Aggiunte posizioni sul canvas tramite impaginazione del testo formattato e fallback Vision sulle regioni del foglio; l’evidenziazione derivata non modifica gli appunti. Ricerca interna ritardata di 200 ms e risultati obsoleti scartati. Il fallback OCR può evidenziare l’intera riga, non la singola parola.
2. OCR: cache di revisione e indicizzazione nelle pause presenti; aggiunta scansione controllata dei quaderni preesistenti, una pagina per volta, annullabile e riprendibile per revisione; esclusione degli editor aperti.
3. Libreria: recenti/copertine/cartelle presenti; aggiunti tag portabili nel quaderno, pin e Inbox con nota rapida. Aggiunti colori alle cartelle come preferenza locale della libreria, senza migrare SwiftData. La portabilità/sincronizzazione del colore insieme alle cartelle resta da completare.
4. Struttura: titoli/segnalibri/ordine presenti; aggiunte sezioni/sottosezioni con filtro e assegnazione dalle anteprime, collegamenti inseribili nel foglio ed elenco dei collegamenti in entrata. Identità rimappate in clone/import e metadati separati dall’inchiostro. I link verso altri quaderni richiedono ancora apertura manuale del quaderno di origine.
5. Sistema: nota rapida/Inbox presente; aggiunti App Intent con titolo/testo facoltativo e App Shortcut, Spotlight opt-in limitato a titoli/tag, riapertura per identificativo del documento e cancellazione dell’indice quando disabilitato. Integrazioni non ancora compilate/provate con Apple. Widget ancora da sviluppare come target separato.
6. Export: nativo/PDF/testo trascrizioni presenti; aggiunti PNG/JPG/Markdown, copia area selezionata e stampa.

## Fase 4 — PDF

Selezione/copia, evidenziazione per riga, sottolineatura, indice, link nativi, vista affiancata e pagine bianche intermedie presenti. Aggiunti ricerca asincrona evidenziata, estratti con etichetta della pagina e raccolta Markdown delle evidenziazioni. Il margine/ritaglio non distruttivo resta da completare; gli estratti hanno un collegamento interno riapribile con lo strumento Oggetti e sono elencati nelle fonti in entrata.

## Fase 5 — audio

Trascrizione lunga a finestre con checkpoint e isolamento di blocchi silenziosi/falliti presente nella 0.9.1. SpeechAnalyzer dipende da sistema/SDK più recente. Aggiunti replay visivo non distruttivo dei tratti, segnalibri persistenti, velocità 0,5–2× e import audio a file (senza leggere tutta la registrazione in memoria). Capitoli ogni cinque minuti o ai segnalibri personali, rinomina e Markdown integrale con timestamp. La 0.12 aggiunge ricerca per nome, ordine cronologico stabile, archivio/cestino/ripristino e cancellazione della sola trascrizione; il cestino conserva file/anchor e occupa ancora spazio. Export separato delle parti audio originali con TXT/MD corretti, playlist e manifest, copia a blocchi e controllo spazio; L’export non ricodifica ulteriormente; nella 0.14 le parti PCM vengono convertite separatamente solo dopo la registrazione con verifica e journal. La fusione M4A resta assente. Passata la prova Core sintetica di otto ore/640 checkpoint con riapertura e correzioni; predisposto il test Apple di un WAV di sei ore con controller e riconoscimento iniettato, non ancora eseguito. Nessuna misura di ASR reale/standby. La sbobina semantica generativa resta da completare; diarizzazione richiede un motore reale, non nomi di parlanti simulati.

## Fase 6 — studio

1. Conversione grafia: OCR presente, aggiunta sostituzione della selezione, con undo; allineamento avanzato ancora da completare.
2. Tutor: chat con fonti presente; il pannello Studio comprende già l’ambito della cartella e sottocartelle. Aggiunti quiz interattivi con spiegazioni nello studio e simulazione a tempo, risposte nascoste fino alla consegna e ripresa persistente. L’interrogazione conversazionale adattiva resta distinta e da completare.
3. Ripasso: aggiunto FSRS-6 originale, sorgenti con commit fissato e test upstream, migrazione dei vecchi stati al primo ripasso. Aggiunti registro atomico dei ripassi, statistiche reali, serie giornaliera e previsione delle scadenze su calendario; i ripassi anteriori a questa versione non vengono inventati. Quiz locale con alternative ricavate dalle flashcard, più backend strutturato `/v1/quiz`, con quattro opzioni, citazioni verificate e massimo 12 domande. Risultati/progressi restano locali, storico limitato a dieci; generazione live e qualità didattica non provate.
4. Guide/mappe: sintesi estrattiva presente; generazione remota di riassunti/schemi già disponibile nel pannello Studio quando il motore è configurato. Aggiunta conversione di uno schema in una nuova pagina con caselle e linee modificabili, fino a otto punti e riferimenti alle fonti; il testo completo resta nell’elaborazione. Senza domanda, il contesto viene campionato lungo tutto l’indice entro 40 estratti/80.000 unità UTF-16, con avviso di parzialità; non è una lettura integrale o una sbobina semantica completa.
5. Matematica/immagini: OCR presente; LaTeX e verifica dei passaggi richiedono un motore configurato e valutazione sulle fonti.
6. Ordine automatico: titoli/tag/Inbox da completare.
7. Writing Tools: dipendono da hardware Apple Intelligence; il normale UITextView resta il fallback utilizzabile sull’iPad 10.

FSRS: [sorgente ufficiale](https://github.com/open-spaced-repetition/swift-fsrs), commit `4fbaf20184d62f82a9f44f343337c61a2c5483e9`, licenza MIT conservata in `THIRD_PARTY_NOTICES.md` e nelle risorse dell’app. Nessun download di package richiesto al Playground: sorgenti inclusi nel Core.

## Fase 7 e aspetti trasversali

CloudKit/conflitti predisposti nella 0.9; firma, contenitore e prova a due dispositivi ancora esterni. Cartelle/tombstone/outbox, condivisione di sola lettura, adattamento iPhone/Mac, audit completo di accessibilità e privacy di pubblicazione richiedono i rispettivi completamenti. Aggiunta guida iniziale adattiva, riapribile dalla sidebar; testi Dynamic Type ed elementi VoiceOver nelle nuove schede non equivalgono a un audit completo. Toolbar flottante, dock, focus, profili materia, icone/copertine e recenti sono già presenti. EventKit/orario lezioni e collegamenti automatici devono avere azioni esplicite e non creare eventi senza un comando dell’utente.

## Parti ancora parziali o non implementate

| Area | Lavoro residuo e motivo |
| --- | --- |
| Fluidità | Prefetch serializzato e budget stimato di 48 MB aggiunti; preparazione degli import PDF/foto ora fuori dal MainActor, ma rendering delle anteprime ancora sul MainActor. Pipeline completa fuori dal thread principale e scrittura immediata universale su pagine grandi fredde ancora aperte. Non si introduce un secondo scroll view/canvas scrivibile. |
| Editor/PDF | Finestra zoom per scrittura, crop/margini PDF non distruttivi e presentatore per display esterno ancora mancanti; richiedono prove coordinate/zoom/export/input sull’SDK Apple. |
| Account/Lente | Ricerca web con URL e menu AI sul testo ora implementati, ma non provati con provider/iPad reali. Restano login OAuth senza client registrato, attivazione/hosting live, lookup strutturato in streaming, entità automatiche e consenso persistente separato per quaderno. Il consenso attuale è per pannello/motore/destinazione/modello. |
| Audio/AI | Sbobina generativa dell’intera lezione, diarizzazione reale, allineamento avanzato della grafia, LaTeX e verifica matematica, titoli/tag suggeriti e calendario/orario lezioni non implementati. Campionare fonti non completa questi punti. Cestino audio ripristinabile presente; eliminazione fisica definitiva e fusione delle parti audio non implementate. |
| Sistema/cloud | Widget, navigazione diretta tra quaderni, cartelle portabili nel cloud, tombstone/outbox, condivisione di sola lettura e adattamento iPhone/Mac ancora aperti. |
| Gesti/scorciatoie | Comandi dell’editor, gesti dita e menu AI sul testo selezionato presenti; completare scorciatoie schede/ricerca globale/audio e palette squeeze sotto la punta. Il contagocce non è un comando dedicato verificato. |
| Pubblicazione/qualità | Test UI testo intermittente, misure reali su PDF 300 pagine/50 quaderni/sei schede, 30 casi italiani di qualità AI, accessibilità completa, privacy di pubblicazione e distribuzione firmata ancora da verificare. |

Nessuna di queste voci viene considerata completata perché l’SDK non è disponibile o perché esiste un protocollo. Le funzionalità locali non dipendono dall’attivazione dell’AI remota.

L’ordine dei lotti viene mantenuto, ma i numeri di versione originali descrivevano una roadmap dalla 0.7.1: non sono prove di completamento o pubblicazione. La consegna finale deve indicare ciò che è eseguito, ciò che è solo predisposto e le dipendenze effettivamente non attivabili in questa sessione.

## Esecuzioni Apple di questa lavorazione

- `39478731365` (137d78a): PASS, FSRS/nuove carte/elenchi e gesti.
- `39480369723` (25c353b): errore UI di riconoscimento della condivisione; log provano l’apertura di `ShareSheet.RemoteContainerView`, selettore del test corretto senza cambiare la condivisione dell’app.
- `39482782993` (77fcbcf): compilazione fermata dalla disponibilità di `prefersHoverToolPreview`; protezione iOS 17.5 aggiunta.
- `39483133356` (eba004f): PASS, 178 XCTest nel simulatore (176 passati, due esclusioni dell’ambiente), 98 Swift Testing FSRS, 18 UI, Release senza firma.
- `39484841548` (2eb71af): core e unit passati, un test UI del testo non trova la casella; evidenza esportata e correzioni di sequenza del focus/accessibilità/riconoscitori in acea463, da verificare nella run seguente.
- `39488420878` (acea463): fallimento di una nuova asserzione sulla precisione frazionaria di una data ISO8601; test corretto alla precisione del contratto, senza cambiare il contenuto salvato.
- Run 39488740893: Core e unit passati, due UI Audio non trovavano comandi fuori dalla porzione visibile; comandi riposizionati. Run 39490272717: nuova aspettativa foto corretta da punti a pixel; il difetto UI testo rimane intermittente. Run 39515889190: job non avviati per blocco fatturazione GitHub. Nessuna modifica a pagamenti/limiti.
- Riscontro iPad della 0.12.0: compilazione fallita in LensGeometry e messaggio di anteprima AppController; patch 0.12.1 con import CoreGraphics e tipi espliciti predisposta, senza conferma Apple.
- Riscontro iPad della 0.12.1: errori SelectionCommands e LibraryView, warning PencilControls; patch 0.12.2 e viste SwiftUI suddivise. Nuova run 39589913621 su e5b3d44 ferma prima dei comandi per fatturazione, Apple saltato. Nessuna compilazione Apple dichiarata superata per la patch.
- Suite locale Swift Linux aggiornata: 164 XCTest (162 passati e due esclusioni previste), zero errori, più 98 Swift Testing FSRS passati. Backend: 23 test passati nella 0.12.0, invariato nella patch. Controlli incorporati: 33 complessivi; non eseguiti sull’iPad in questa sessione. Le ultime schermate richiedono ancora compilazione Apple. [Report completo](ROADMAP_VALIDATION.md). Nessuna prova fisica di fotocamera/Pencil/standby e nessuna chiamata AI a pagamento sono state eseguite da questa sessione.
