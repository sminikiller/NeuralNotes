# Gate di accettazione 0.9.0

## Aggiornamento 0.23.0 — candidato delivery

- [x] Annulla della pagina corrente senza attesa del disco, budget sintetico di 150 ms, writer precedente bloccato/errore e nuova scrittura senza ricomparsa del tratto. Conferma UI sui pixel del canvas.
- [x] Sincronizzazione account fra due librerie di prova, conflitti, ripresa dopo interruzione, download corrotto rifiutato, indice paginato e consenso automatico separato per account/quaderno. Trasporto del modello nativo simulato; servizi Auth/database/Storage provati separatamente con servizi reali locali.
- [x] 45 tutorial ricercabili: copertura di tutti gli strumenti del workspace, passaggi e progressi persistenti verificati.
- [x] ZIP effettivo compilato Release con Xcode 16.4 e 15.4, sorgenti dei due pacchetti confrontati; app dello ZIP avviata sul simulatore. Nuovo binario installato sopra 0.20.8 conservando il quaderno di controllo.
- [ ] Servizio account/SMTP/AI pubblico, iCloud firmato e prova su due dispositivi reali.
- [ ] Prove fisiche iPad di registrazione lunga/standby, fotocamera/scanner, grandi documenti e aggiornamento del contenitore Playgrounds conservando gli appunti reali.

Esiti, ripetizioni e limiti in [DELIVERY_0_23_0.md](DELIVERY_0_23_0.md). Non è una pubblicazione App Store completata.

## Aggiornamento 0.21.0 — verifiche automatiche e fisiche distinte

- [x] Sei verifiche prima fallite risolte; suite completa e ripetizioni mirate documentate, Release e ZIP reale compilati. [Evidenze 0.21.0](DELIVERY_0_21_0.md).
- [x] Auth email/refresh/logout, isolamento fra due account, quote, prenotazione/upload/download Storage privato, conflitti e cancellazione riprendibile: servizi reali **locali**, provider AI simulato.
- [x] Aggiornamento 0.20.8 → binario 0.21 su simulatore: quaderno SwiftData, manifest/catalogo e trascrizione di controllo conservati. Non è una prova del contenitore Playgrounds dell’utente.
- [x] File sintetico di sei ore: IO a finestre, ripresa, correzioni e timestamp verificati con riconoscimento simulato.
- [ ] Registrazione reale prolungata, standby, fotocamera/scanner e aggiornamento conservando i quaderni reali sull’iPad.
- [ ] Hosting/Auth/SMTP/provider pubblici, prova AI con chiave reale, iCloud firmato e due dispositivi.

Le liste sotto sono storiche e conservano i gate fisici non ancora verificati.


La build e le suite automatiche correnti sono riportate in [VALIDATION.md](VALIDATION.md). L’accettazione sul dispositivo resta aperta; seguire prima [STUDY_WORKSPACE_0_9.md](STUDY_WORKSPACE_0_9.md).

- [x] CI Apple 0.9: core, unit/integrazione e 16 UI test, Debug e Release senza firma. Backend 12/12; esiti e limiti in VALIDATION.md.

- [ ] Zoom PDF/testo e scorrimento su iPad 10, con memoria e primo contatto sulle pagine grandi annotati.
- [ ] Sei penne, preset, gomma parziale/per tratto e solo evidenziatore; undo/redo e riapertura.
- [ ] Selezione ruotata/ridimensionata/ricolorata e scarabocchio su testo formattato.
- [ ] RTF, scanner reale multipagina, drop da altre app e collegamenti apribili.
- [ ] Selezione/copia, indice, link ed evidenziazione PDF affiancato, comprese pagine ruotate ed export.
- [ ] Ricerca globale e OCR della grafia reale con apertura del risultato nella pagina corretta.
- [ ] Versioni automatiche riaperte come copie e backup rinviato durante la registrazione.
- [ ] Lente offline e, separatamente, backend HTTPS configurato: streaming/Stop/perdita rete senza risposte incomplete salvate.
- [ ] App firmata con Team `64R668842U`, contenitore CloudKit attivo e prova di conflitto su due dispositivi.

## Gate mantenuti dalle consegne precedenti

Stato: **INCOMPLETO sul dispositivo**. I controlli di struttura/sintassi e packaging passano; build e test Apple vengono eseguiti dalla CI privata, con esiti in [VALIDATION.md](VALIDATION.md). Il vecchio piano della Fase 1, già autorizzato dall’utente dopo le proprie prove, è conservato in [history/ACCEPTANCE_PHASE_1.md](history/ACCEPTANCE_PHASE_1.md).

- [ ] Il nuovo Playground compila e apre la libreria senza eliminare dati esistenti.
- [ ] Tutti i 26 controlli incorporati passano, in particolare il backup precedentemente fallito.
- [ ] Foto/camera, crop/rotazione, forme e selezione mista superano il percorso [TESTING_0_5.md](TESTING_0_5.md).
- [ ] Undo/redo ripristina oggetti e pagine senza perdere tratti, anche dopo cambio pagina.
- [ ] Schede/ultima pagina riaperte nella stessa installazione; verifica multiwindow o registra il limite del runner.
- [ ] PDF vettoriale leggibile e allineato; originali e testo conservati; backup reimportato con nuove identità.
- [ ] Recupero/spazio provati su quaderni temporanei; nessuna cancellazione automatica dei contenuti.
- [ ] Prova sintetica 50 pagine/CAF60s completata e risultati annotati.
- [ ] Registrazioni reali lunghe, file grandi, interruzioni, memoria e layout/accessibilità verificati secondo il piano.
- [x] CI macOS 0.8.2: core test + unit/UI test e build Release senza firma con tools/verify_macos.sh, log e .xcresult conservati. [Esito e due esclusioni specifiche del simulatore](VALIDATION.md).

Firma/distribuzione, configurazione backend e futura sincronizzazione hanno gate separati: non sono impliciti in questi controlli.

```text
Data e versione app:
iPad / iPadOS / Swift Playground:
Build: PASS / FAIL + messaggio completo
Controlli incorporati: 26/26 oppure elenco errori
Foto / gruppi / undo / schede / finestre:
PDF / backup reimportato / recupero:
Prova sintetica: tempo, spazio, risultato
Registrazione reale: durata, pause, interruzioni, drift
Documento grande: pagine, dimensione, tempi, problemi
Build/test Mac e percorso .xcresult, se disponibili:
Gate 0.8.2: PASS / FAIL / INCOMPLETO
```

Gate specifici 0.6: import PDF come quaderno dalla libreria; carta per pagina/default; focus completo e pulsante trascinabile; avanzamento al fondo; scarabocchio configurabile con undo; trascrizione con pausa/riapertura pannello, rinomina/correzione ed export temporizzato. Non spuntati prima della prova reale.

Gate aggiuntivi 0.6, ancora da verificare:

- [ ] Dopo pinch, doppio tocco e Pagina intera tornano alla pagina completa.
- [ ] Navigazione verticale e swipe orizzontale cambiano pagina senza perdere modifiche; scelta conservata alla riapertura.
- [ ] Annerimento/zig-zag cancella la zona prevista dopo sollevamento Pencil; undo/riapertura/PDF conservano il resto.
- [ ] Testo con Pencil funziona nel campo in pagina con i gesti Scribble realmente abilitati sul dispositivo.
- [ ] Il lettore mostra tutte le trascrizioni; risultati vuoti sono espliciti e ritentabili; rinomina non perde testo.

Gate urgente 0.6.1: [prova layout/input](FIXES_0_6_1.md).

- [ ] Il canvas riempie l’area dell’editor come prima, senza un contenitore scorrevole esterno.
- [ ] Pencil scrive in tutte le modalità senza scorrere/sfogliare; le dita navigano secondo la preferenza.
- [ ] La stessa area del canvas è conservata cambiando modalità, orientamento e focus.

Gate aggiuntivi 0.7: [scorrimento e voltata](TESTING_0_7.md).

- [ ] Verticale continuo con gap ridotto, offset invariato al cambio della pagina attiva e nessun riquadro scorrevole esterno.
- [ ] Scrittura sul foglio corretto dopo scorrimento, prefetch e formati diversi; primo contatto non pronto segnalato.
- [ ] Voltata orizzontale nei due sensi senza flash o perdita di inchiostro; Riduci movimento e rotazione verificati.

Gate zoom 0.7.1: [doppio tocco e margini laterali](FIXES_0_7_1.md).

Gate 0.8.2: [workspace, toolbar, forme, righello e copertine](TESTING_0_8.md). Richiedono prova iPad, soprattutto l’anteprima durante il contatto Pencil.

Gate 0.8.2: [compilazione reale del riconoscitore, salvataggio e recupero](CONSOLIDATION_0_8_1.md).

Gate aggiuntivi 0.8.2: scarabocchio senza rettangolo, forma confermata fino al sollevamento, riapertura ultima pagina modificata e copertina automatica. Seguire [FIXES_0_8_2.md](FIXES_0_8_2.md).
