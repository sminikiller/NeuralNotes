# Gate di accettazione 0.8

Stato: **INCOMPLETO sul dispositivo**. I controlli di struttura/sintassi e packaging passano; build Apple e test Swift non eseguiti qui. Il vecchio piano della Fase 1, già autorizzato dall’utente dopo le proprie prove, è conservato in [history/ACCEPTANCE_PHASE_1.md](history/ACCEPTANCE_PHASE_1.md).

- [ ] Il nuovo Playground compila e apre la libreria senza eliminare dati esistenti.
- [ ] Tutti i 25 controlli incorporati passano, in particolare il backup precedentemente fallito.
- [ ] Foto/camera, crop/rotazione, forme e selezione mista superano il percorso [TESTING_0_5.md](TESTING_0_5.md).
- [ ] Undo/redo ripristina oggetti e pagine senza perdere tratti, anche dopo cambio pagina.
- [ ] Schede/ultima pagina riaperte nella stessa installazione; verifica multiwindow o registra il limite del runner.
- [ ] PDF vettoriale leggibile e allineato; originali e testo conservati; backup reimportato con nuove identità.
- [ ] Recupero/spazio provati su quaderni temporanei; nessuna cancellazione automatica dei contenuti.
- [ ] Prova sintetica 50 pagine/CAF60s completata e risultati annotati.
- [ ] Registrazioni reali lunghe, file grandi, interruzioni, memoria e layout/accessibilità verificati secondo il piano.
- [ ] Su Mac: core test + unit/UI test e build Release senza firma con tools/verify_macos.sh, log e .xcresult conservati.

Firma/distribuzione, configurazione backend e futura sincronizzazione hanno gate separati: non sono impliciti in questi controlli.

```text
Data e versione app:
iPad / iPadOS / Swift Playground:
Build: PASS / FAIL + messaggio completo
Controlli incorporati: 25/25 oppure elenco errori
Foto / gruppi / undo / schede / finestre:
PDF / backup reimportato / recupero:
Prova sintetica: tempo, spazio, risultato
Registrazione reale: durata, pause, interruzioni, drift
Documento grande: pagine, dimensione, tempi, problemi
Build/test Mac e percorso .xcresult, se disponibili:
Gate 0.8: PASS / FAIL / INCOMPLETO
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

Gate 0.8: [workspace, toolbar, forme, righello e copertine](TESTING_0_8.md). Richiedono prova iPad, soprattutto l’anteprima durante il contatto Pencil.
