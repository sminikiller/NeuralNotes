# Milestone NeuralNotes

**Regola di avanzamento:** una fase successiva inizia dopo build, test e criteri di accettazione della precedente. Al 19 ottobre 2026 la Fase 1 ha codice e controlli strutturali, ma non ha ancora superato il gate Apple. Non iniziare Fase 2 finché [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) non è completato.

Percorso adattato all’hardware disponibile: l’utente ha soltanto un iPad di decima generazione con iPadOS 18.7.8. Aggiunto un App Playground nativo `.swiftpm`, generato dagli stessi sorgenti, per compilazione ed esecuzione direttamente in Swift Playground. Prima verifica del ciclo crea/rinomina/riapri sul dispositivo seguendo [docs/IPAD.md](docs/IPAD.md). Test Xcode, Release e distribuzione rimangono verifiche distinte ancora da eseguire; nessuna falsa dichiarazione di superamento del gate.

## Fase 1 — Progetto, libreria, creazione documenti

Implementato: progetto Xcode condiviso, package locale, modelli V1, repository e ViewModel, libreria con sidebar, creazione/apertura/rinomina, copertine colore, cartelle e sottocartelle, preferiti, ricerca e ordinamento, layout griglia/elenco, duplicazione dei documenti vuoti, eliminazione logica e ripristino dell’ultima eliminazione. Errori espliciti, manifest atomico, controllo di integrità, test forniti.

Criteri di accettazione:

1. Build Debug e Release con l’SDK installato; nessun errore di compilazione e warning di concorrenza analizzati.
2. Test core, integrazione SwiftData e ciclo di vita UI tutti verdi.
3. Su iPad fisico: creare, rinominare, chiudere completamente l’app, riaprire, ritrovare e aprire il quaderno con stesso titolo e identità.
4. Modifiche a cartelle, copertina, posizione e preferiti sopravvivono al riavvio; duplicazione usa UUID nuovi; eliminazione non danneggia gli altri quaderni.
5. Verifica in portrait/landscape, finestra ridotta/Split View, dark mode, Dynamic Type e VoiceOver; niente comandi inaccessibili.
6. Errori di IO e documenti corrotti non causano reset/perdita silenziosa; test negativi passano.

Stato: **implementazione da validare su piattaforma Apple**. Il conteggio pagine è zero e non esiste un editor operativo.

## Fase 2 — Scrittura PencilKit e pagine

Avvio solo dopo il gate Fase 1. Introdurre canvas UIKit, strumenti nativi, undo/redo, zoom/pan separati da Pencil, pagine multiple, aggiunta/eliminazione/duplicazione, sfondi bianco/rigato/quadrettato/puntinato e autosave revisionato vettoriale.

Accettazione: tratti identici dopo riapertura e interruzione forzata; nessuna conversione raster del documento; strumenti e undo funzionanti; test su pagine e revisioni, pressione memoria e sessione Pencil prolungata. Misurare latenza e frame time su iPad reale, senza dichiarare soglie non misurate. Documentare policy di salvataggio e recovery prima di procedere.

## Fase 3 — PDF, immagini, testo e formato nativo esportabile

Importare PDF originali immutabili e immagini, visualizzare con PDFKit, annotare in layer PencilKit separati, caselle di testo editabili, allegati. Export PDF composto ed export nativo completo con metadati, asset e versione del formato; convalida dei percorsi e degli hash in import.

Accettazione: PDF originale invariato byte per byte; annotazioni allineate con crop box/rotazioni 0/90/180/270 e zoom; export multi pagina leggibile; round trip nativo senza perdita; import malformati gestiti con errore e senza file esterni al pacchetto. Duplicazione estesa a tutti i contenuti e cestino persistente accessibile.

## Fase 4 — Audio sincronizzato

Recorder/player AVFoundation, timeline, pausa/ripresa, permessi, interruzioni e cambi rotta. Aggiungere AudioSession, AudioTimelineSegment e StrokeAnchor prima di registrare il primo tratto associato all’audio.

Accettazione: registrazione recuperabile dopo interruzione/riavvio; seek da tratto al corretto segmento; pause senza timestamp falsi; drift misurato e tolleranza dichiarata; test storage pieno, microfono negato e interruzioni. Scrittura sempre disponibile se l’audio fallisce.

## Fase 5 — OCR, trascrizione, ricerca

Vision per OCR; Apple Speech per trascrizioni e segmenti temporali; ricerca testuale locale per testo OCR, PDF e trascrizioni con riferimenti alle fonti. Servizi separati dal writer di pagina, cancellabili e incrementali.

Accettazione: ricerca restituisce pagina o minuto corretto; test su bounding box e mapping temporale; permessi e lingue non supportate comunicati; nessun OCR inventato e nessuna promessa di offline dove non supportato. Indici ricostruibili senza perdere originali.

## Fase 6 — AI opzionale, riassunti e tutor

Introdurre i contratti AIProvider, LocalAIProvider, RemoteAIProvider, EmbeddingService, DocumentIndexingService e RetrievalService. Backend con provider intercambiabili, gestione sicura credenziali e capability locali rilevate sul dispositivo.

Task: riassunti lezioni/PDF/aree selezionate, mini schemi da foto, chat documento/cartella/materia, flashcard/quiz, collegamento appunti/trascrizione, ricerca semantica, riconoscimento argomenti, confronto fra fonti e citazioni pagina/minuto.

Accettazione: provider sostituibili senza cambiare UI/dominio; nessun segreto del provider nell’app; rifiuto di citazioni non riconducibili alle fonti; dataset di valutazione per grounding e retrieval; gestione rete assente/cancellazione; canvas e save indipendenti dall’AI. Esplicitare requisiti OS/hardware dei modelli locali.

## Fase 7 — CloudKit, affidabilità e distribuzione

Sync local-first con outbox, asset separati, tombstone, conflitti che conservano revisioni divergenti, retry/quota. Profilazione Pencil, memoria, IO, energia e accessibilità. Valutare più scene solo con coordinamento dei writer. Collaborazione in tempo reale in milestone separata.

Accettazione: scrittura e commit offline, convergenza di due dispositivi, test di conflitti/doppie modifiche/eliminazioni, migrazioni da release precedenti e recovery; sessioni grandi senza crescita memoria non limitata. Firma, archivio, privacy effettiva, icone, TestFlight e checklist App Store completati sul Mac/account dell’utente.
