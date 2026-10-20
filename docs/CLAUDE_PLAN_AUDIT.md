# Piano di Claude — verifica e avanzamento

Fonte: documento dell’utente «NeuralNotes — stato del progetto (0.7.1) e roadmap delle funzionalità», allegato del 20 ottobre 2026. Il codice di partenza di questa lavorazione è la 0.9.1, commit `f9867b6`. La richiesta attuale autorizza sviluppo e test autonomi di tutti i lotti, senza altre domande.

Il documento viene usato come specifica di prodotto. Le dichiarazioni sulle API, sui servizi e sulle versioni future richiedono conferma nelle fonti ufficiali; non diventano automaticamente API disponibili sull’iPad 10 con iPadOS 18.

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
7. Selezione: trasformazioni presenti; aggiunti lazo libero, copia area immagine, conversione OCR, spessore e azione AI diretta. Spostamento dedicato tra pagine ancora da completare; copia/incolla tra pagine/quaderni già presente.
8. Testo: RTF presente; aggiunti continuazione degli elenchi e checklist azionabili senza entrare in modifica.
9. Finestra zoom: aggiunto navigatore visivo separato, senza un secondo canvas scrivibile; finestra di scrittura ingrandita dedicata ancora da completare.
10. Continuità: viewport unico presente; input freddo grande durante IO ancora protetto con attivazione differita.
11. Presentazione: righello presente; laser/schermo esterno da aggiungere.
12. Nastro per ripasso: aggiunto, con svelamento sul foglio, undo, backup ed export.
13. Post-it/timbri/livelli/blocco: aggiunti; oggetti sopra o sotto l’inchiostro, blocco della selezione e duplicazione con identità indipendenti.
14. Carta: aggiunti Cornell, agenda settimanale, pentagramma, isometrico, millimetrato e mappa; aggiunto modello PDF personale per le pagine successive, senza riprendere gli appunti del modello.
15. Scanner/drop/link: presenti; correzione media nel lotto iniziale e drop PDF da completare.

## Fase 2 — Lente e account AI

Pannello, area/sele­zione, streaming backend, fonti, conversazione, inserimento e flashcard sono presenti. Aggiunti selettore unico offline/backend/OpenAI/Claude/Gemini/Responses compatibile, credenziali distinte nel portachiavi, consenso per motore/destinazione/modello, glossario modificabile con fonti, dizionario di sistema dalla selezione e cache persistente limitata a 32 risposte per selezione/azione. I provider personali restituiscono il risultato finale, mentre il backend mantiene lo streaming reale. Aggiunta scheda strutturata `/v1/lookup` nel backend e nella Lente: definizione/spiegazione/esempi/termini correlati, citazioni verificate, inserimento e salvataggio nel glossario. Sedici test backend locali passati. Resta il login personale: non vengono simulati client OAuth o risposte del provider. Hosting e credenziali non sono configurati.

Sono state consultate le fonti ufficiali OpenAI [sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), [integrazione web](https://developers.openai.com/siwc/website) e [output strutturati](https://developers.openai.com/api/docs/guides/structured-outputs). Il percorso commerciale richiede registrazione/approvazione; non viene inventato un client ID o riutilizzato un client di un’altra app. La disponibilità del percorso open-source non equivale all’abilitazione di questa app privata.

## Fase 3 — ricerca e organizzazione

1. Ricerca globale: presente; aggiunti filtri testo/PDF/grafia/audio/glossario e cartella, con anteprima centrata sulla corrispondenza e testo evidenziato. Posizione grafica sul canvas da completare.
2. OCR: cache di revisione e indicizzazione nelle pause presenti; aggiunta scansione controllata dei quaderni preesistenti, una pagina per volta, annullabile e riprendibile per revisione; esclusione degli editor aperti.
3. Libreria: recenti/copertine/cartelle presenti; aggiunti tag portabili nel quaderno, pin e Inbox con nota rapida. Colore delle cartelle ancora da completare.
4. Struttura: titoli/segnalibri/ordine presenti; aggiunte sezioni/sottosezioni con filtro e assegnazione dalle anteprime, collegamenti inseribili nel foglio ed elenco dei collegamenti in entrata. Identità rimappate in clone/import e metadati separati dall’inchiostro. I link verso altri quaderni richiedono ancora apertura manuale del quaderno di origine.
5. Sistema: nota rapida/Inbox, Spotlight, App Intents e widget da sviluppare compatibilmente con i target di firma e il runner.
6. Export: nativo/PDF/testo trascrizioni presenti; aggiunti PNG/JPG/Markdown, copia area selezionata e stampa.

## Fase 4 — PDF

Selezione/copia, evidenziazione per riga, sottolineatura, indice, link nativi, vista affiancata e pagine bianche intermedie presenti. Aggiunti ricerca asincrona evidenziata, estratti con etichetta della pagina e raccolta Markdown delle evidenziazioni. Il margine/ritaglio non distruttivo resta da completare; gli estratti hanno un collegamento interno riapribile con lo strumento Oggetti e sono elencati nelle fonti in entrata.

## Fase 5 — audio

Trascrizione lunga a finestre con checkpoint e isolamento di blocchi silenziosi/falliti presente nella 0.9.1. SpeechAnalyzer dipende da sistema/SDK più recente. Aggiunti replay visivo non distruttivo dei tratti, segnalibri persistenti, velocità 0,5–2× e import audio a file (senza leggere tutta la registrazione in memoria). Sbobina strutturata ancora da completare; diarizzazione richiede un motore reale, non nomi di parlanti simulati.

## Fase 6 — studio

1. Conversione grafia: OCR presente, aggiunta sostituzione della selezione, con undo; allineamento avanzato ancora da completare.
2. Tutor: chat con fonti presente; ambiti cartella/materia e modalità interrogazione da completare.
3. Ripasso: aggiunto FSRS-6 originale, sorgenti con commit fissato e test upstream, migrazione dei vecchi stati al primo ripasso. Aggiunti registro atomico dei ripassi, statistiche reali, serie giornaliera e previsione delle scadenze su calendario; i ripassi anteriori a questa versione non vengono inventati. Quiz generativi e simulazione d’esame da completare.
4. Guide/mappe: sintesi estrattiva presente; guide generative e diagrammi modificabili da completare.
5. Matematica/immagini: OCR presente; LaTeX e verifica dei passaggi richiedono un motore configurato e valutazione sulle fonti.
6. Ordine automatico: titoli/tag/Inbox da completare.
7. Writing Tools: dipendono da hardware Apple Intelligence; il normale UITextView resta il fallback utilizzabile sull’iPad 10.

FSRS: [sorgente ufficiale](https://github.com/open-spaced-repetition/swift-fsrs), commit `4fbaf20184d62f82a9f44f343337c61a2c5483e9`, licenza MIT conservata in `THIRD_PARTY_NOTICES.md` e nelle risorse dell’app. Nessun download di package richiesto al Playground: sorgenti inclusi nel Core.

## Fase 7 e aspetti trasversali

CloudKit/conflitti predisposti nella 0.9; firma, contenitore e prova a due dispositivi ancora esterni. Cartelle/tombstone/outbox, condivisione di sola lettura, adattamento iPhone/Mac, primo avvio guidato, accessibilità e privacy di pubblicazione richiedono i rispettivi completamenti. Toolbar flottante, dock, focus, profili materia, icone/copertine e recenti sono già presenti. EventKit/orario lezioni e collegamenti automatici devono avere azioni esplicite e non creare eventi senza un comando dell’utente.

L’ordine dei lotti viene mantenuto, ma i numeri di versione originali descrivevano una roadmap dalla 0.7.1: non sono prove di completamento o pubblicazione. La consegna finale deve indicare ciò che è eseguito, ciò che è solo predisposto e le dipendenze effettivamente non attivabili in questa sessione.

## Esecuzioni Apple di questa lavorazione

- `39478731365` (137d78a): PASS, FSRS/nuove carte/elenchi e gesti.
- `39480369723` (25c353b): errore UI di riconoscimento della condivisione; log provano l’apertura di `ShareSheet.RemoteContainerView`, selettore del test corretto senza cambiare la condivisione dell’app.
- `39482782993` (77fcbcf): compilazione fermata dalla disponibilità di `prefersHoverToolPreview`; protezione iOS 17.5 aggiunta.
- `39483133356` (eba004f): PASS, 178 XCTest nel simulatore (176 passati, due esclusioni dell’ambiente), 98 Swift Testing FSRS, 18 UI, Release senza firma.
- `39484841548` (2eb71af): core e unit passati, un test UI del testo non trova la casella; evidenza esportata e correzioni di sequenza del focus/accessibilità/riconoscitori in acea463, da verificare nella run seguente.
- `39488420878` (acea463): fallimento di una nuova asserzione sulla precisione frazionaria di una data ISO8601; test corretto alla precisione del contratto, senza cambiare il contenuto salvato.
- Run 39488740893: Core e unit passati, due UI Audio non trovavano comandi fuori dalla porzione visibile; comandi riposizionati. Run 39490272717: nuova aspettativa foto corretta da punti a pixel; il difetto UI testo rimane intermittente. Run 39515889190: job non avviati per blocco fatturazione GitHub. Nessuna modifica a pagamenti/limiti.
- Suite locale Swift Linux: 120 XCTest (due esclusioni previste), zero errori, più 98 Swift Testing FSRS passati. Backend: 16 test passati. Le ultime schermate richiedono ancora compilazione Apple. [Report completo](ROADMAP_VALIDATION.md). Nessuna prova fisica di fotocamera/Pencil/standby e nessuna chiamata AI a pagamento sono state eseguite da questa sessione.
