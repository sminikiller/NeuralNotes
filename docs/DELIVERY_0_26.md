# NeuralNotes 0.26 — Aggancio e allineamento

Aggancio e allineamento verificati con SDK Apple: **sei job della verifica completa verdi**, incluso l’archivio di distribuzione. La beta **1.0.0 (135)** è stata firmata e caricata su Apple il 29 ottobre 2026. Elaborazione e disponibilità effettiva in TestFlight non ancora confermate.

## Contenuto
- Motore Core per bordi/centri di oggetti e pagina, margine carta, griglia normale/isometrica, spazi uguali, ridimensionamento e rotazione. Soglia 6 punti schermo convertita con lo zoom.
- Indice per celle degli assi e vicini ordinati costruito una sola volta a inizio gesto. Guide temporanee da 1 pixel fisico, mai salvate. Le query di spaziatura esaminano fino a 32 vicini per lato.
- Workspace: preferenze opzionali per oggetti, griglia, guide e proporzioni. Default: oggetti e guide attivi, griglia attiva solo sui modelli di carta con reticolo.
- Secondo dito durante un gesto oppure ⌥ sospendono l’aggancio senza spostare il punto di trascinamento primario. Due dita a inizio gesto restano disponibili per scorrere.
- Menu selezione e menu contestuale: sei allineamenti, distribuzione orizzontale/verticale, stessa larghezza/altezza; gruppi di inchiostro inclusi. Oggetti bloccati esclusi. Dimensione verticale del testo ottenuta scalando font e larghezza per conservare le righe.
- Maniglie delle forme e disegno di nuove forme usano griglia e agganci. La rotazione produce feedback leggero quando entra in uno scatto.

## Compatibilità e limiti
Nessun formato della pagina modificato: solo Workspace.snapping opzionale. Nessuna nuova dipendenza, modifica alla firma o attivazione iCloud. Fixture 0.25 con forme/stili/foto per apertura, salvataggio, PDF e backup. Il collaudo sul simulatore e i tempi del runner non attestano 60 fps o il comportamento fisico della Pencil sull’iPad 10.

## Come provarla
1. Inserisci tre rettangoli o caselle di testo e scegli **Oggetti**. Trascinane uno vicino al bordo o al centro di un altro: appare la guida e la posizione si aggancia.
2. Seleziona gli elementi, apri **Allinea e distribuisci**, scegli **Allinea in alto** e poi **Distribuisci in orizzontale**. Ogni comando si annulla e si ripristina in un passo.
3. Apri **Workspace → Aggancio**. Prova la griglia su carta quadrettata o isometrica, poi disattiva gli agganci per confrontare il trascinamento libero.
4. Durante un trascinamento già avviato, appoggia un secondo dito per sospendere l’aggancio; con una tastiera fisica puoi tenere premuto **⌥**. Due dita fin dall’inizio restano disponibili per scorrere.
5. Ruota una forma dalle sue maniglie: scatta ogni 15°, con aggancio più deciso agli angoli retti. Con VoiceOver sono disponibili le azioni **Ruota 15° a destra/sinistra**.

Questi passi non richiedono account, servizi AI o modifiche ai quaderni precedenti. Connettori e diagrammi appartengono alla fase 0.27 e non sono inclusi in questa versione.

## Verifiche
- [Pre-collaudo Apple 40890815865](https://github.com/sminikiller/NeuralNotes/actions/runs/40890815865): Core 319 XCTest e 98 Swift Testing superati; 117 test nativi superati, incluso allineamento misto, annulla, PDF/backup della fixture 0.25 e secondo dito; test UI di allineamento e preferenze superato. Build Release e pacchetto Playgrounds superati.
- La verifica completa precedente aveva superato 474 test nativi (2 saltati) e 32 test UI; il solo test UI nuovo toccava l’etichetta della riga invece dell’interruttore. Corretto il bersaglio del test e mantenuta l’attesa sul valore effettivo dell’interruttore.
- Dopo il pre-collaudo: mantenuto il modificatore di aggancio fino al rilascio del dito primario; azioni VoiceOver di rotazione rese esplicite a passi di 15°. I due test nativi aggiunti sono passati nella verifica completa.
- [Verifica completa 40901219596](https://github.com/sminikiller/NeuralNotes/actions/runs/40901219596), sorgenti `64a00b9fe2e90d1cedd15e924b3b18d2d689c0c3`: **conclusa, sei job verdi**. Core macOS **319 XCTest e 98 Swift Testing** superati; simulatore iPad **477 XCTest, 2 saltati, 0 fallimenti**, più **98 Swift Testing** superati; **tutti i 33 test UI superati**; build Release e archivio riusciti. I due test saltati verificano l’alias Darwin `/private/var`, non usato dal filesystem del simulatore. L’esecuzione 40894669678 è stata annullata perché verificava i sorgenti precedenti; non è una consegna riuscita.
- Pacchetto Playgrounds esatto: build simulatore e dispositivo generico riuscite, avvio dello ZIP con processo stabile e libreria/guida visibili per 60 controlli; schermata esaminata. SHA-256: `c7b951c230bd89052c0c778d57c2ef77c26a54c7ac4f971f797811dfed4fcd66`.
- Aggiornamento **0.20.8 → attuale** superato: quaderno SwiftData, manifest nativo, catalogo e trascrizione precedenti conservati. Fixture 0.25: apertura, salvataggio, PDF e backup/import nativo superati.
- Corretto anche l’avvio del PostgreSQL locale dei test: il controllo TCP attende il server definitivo, evitando quello temporaneo di inizializzazione. Nessuna modifica al backend pubblicato o ai dati degli utenti.

## Consegna
- ZIP esatto compilato: `.verification/NeuralNotes-iPad-0.26.0.zip`, con l’impronta riportata sopra.
- [TestFlight 40939882142](https://github.com/sminikiller/NeuralNotes/actions/runs/40939882142), sorgenti verificati `64a00b9fe2e90d1cedd15e924b3b18d2d689c0c3`, versione commerciale **1.0.0 (135)**: conclusa con successo, `ARCHIVE SUCCEEDED`, `EXPORT SUCCEEDED` e `UPLOAD_COMMAND_SUCCEEDED`. Elaborazione Apple/disponibilità sul dispositivo non confermate. La fase del piano è 0.26.0; la corsia di distribuzione mantiene la numerazione commerciale esistente.
- Schermata del pannello Aggancio della verifica completa esaminata: controlli leggibili, interruttore effettivamente disattivato, nessuna sovrapposizione del pannello ai bordi.
