# NeuralNotes 0.29 — testo e scrittura assistita

Stato: candidata compilata con SDK Apple; il collaudo finale raggruppato è in corso, quindi non ancora consegnata. La beta PDF 0.28.2 è stata firmata e caricata come TestFlight 1.0.0 (177). Le correzioni 0.28.1 rimangono conservate.

## Contenuto della fase

- Apice e pedice per selezioni e caratteri successivi. Dimensioni originali di ogni run conservate in un gruppo RTF ignorabile dai lettori precedenti; font e baseline standard rimangono disegnabili in UIKit/PDF. Grassetto/corsivo/sottolineato e ⌘=/⇧⌘= sul vero UITextView. Ogni modifica di stile si annulla separatamente senza perdere il campo attivo.
- Incolla RTF, limiti su byte/caratteri, incolla semplice con ⇧⌘V e stile della destinazione. Le scorciatoie di navigazione non assorbono normali lettere nel campo.
- Set nominati fino a 12 colori, massimo 20 per attività, con scelta, rinomina, riordino ed eliminazione. Preferiti e recenti di ogni strumento restano indipendenti.
- Calligrafica nativa PencilKit `reed`, compilata solo con compilatore compatibile e mostrata da iPadOS 26. Le versioni precedenti non mostrano una penna simulata.
- Evidenziatore rettangolare: forma riempita senza contorno a fusione moltiplica e opacità predefinita 25%, modificabile col lazo. Aggancio facoltativo alle righe del PDF. Campo opzionale `ShapeElement.rectangularMarker`: cataloghi precedenti identici. Cancellazione e conteggio appartengono solo a Evidenziatore, con protezione dei blocchi; nessun doppio conteggio tra forme e marker. Una sola operazione di annulla per passata, anche con più righe.
- Finestra di scrittura: pannello inferiore circa 30%, zoom 2–4×, riquadro trascinabile sull’originale, margini, frecce e a capo con rigatura. Un canvas PencilKit temporaneo conserva coordinate, pressione, maschere, azimuth e inchiostro originali. Il canvas principale rimane autorevole; solo al rilascio riceve il valore definitivo e la normale cronologia/audio. Il percorso editor normale resta selezionato quando il pannello è chiuso. Passaggio pagina/background/strumenti incompatibili chiude il pannello e conserva il tratto già consegnato.
- Riproduzione: Segui, Mostra tutto con tratto corrente temporaneamente turchese, navigazione ai segnalibri e riprese del parlato dopo pause nella trascrizione. Non si elimina o salta automaticamente audio sulla sola base di un buco nella trascrizione.
- Indice comprimibile, spostamento di interi sottoalberi, rientro/de-rientro e annulla delle sole sezioni con verifica dello stato atteso. I successivi aggiornamenti del catalogo audio non vengono sovrascritti.
- Testo Resta attivo, ricerca globale ⇧⌘F, schede ⌘T/⌘W; G/R rimangono goniometro/righello. Le scorciatoie di formattazione appartengono al risponditore testo e compaiono nel pannello ⌘.
- Sei nuove voci nella guida ricercabile, con passaggi e limiti reali.

## Controlli da concludere prima della consegna

Eseguire l’intera fase con SDK26.6: test Core geometria/compatibilità/riordino/palette/audio, test nativi RTF/PDF e annulla campo attivo, canvas figlio/annulla-nuovo tratto/marker/gomma/coordinata, pixel moltiplica e rendering replay. Eseguire le prove UI della finestra con tratto vero, annulla/ripristina e ripristino del layout, palette, mantenendo le regressioni PDF, riconoscimento e marcatura già verdi. Ispezionare gli screenshot, verificare lo ZIP esatto della CI, quindi usare la corsia TestFlight esistente. I risultati SDK già conclusi e i controlli finali ancora aperti sono riportati sotto; nessun upload 0.29 è ancora dichiarato.

Restano da misurare su iPad fisico pressione Apple Pencil, latenza e rotazione durante una scrittura reale. Non sono verificabili con il solo parser Windows.


## Collaudo completo e ultimo lotto di correzioni

La [run41992864208](https://github.com/sminikiller/NeuralNotes/actions/runs/41992864208), sorgenti0b8a647, ha passato Core386+98, Release, PlaygroundsRelease dispositivo/simulatore+60controlli, aggiornamento con quaderni precedenti e backend. Dei639 test nativi:636 passati,2saltati,1fallito con due asserzioni di colore. Dei47 testUI:40passati e7interrotti prima della scrittura nella navigazione delle impostazioni.

Il test del marker rettangolare assumevaRGB(1,1,0), mentre il giallo della palette è(1,.83,.12). Il controllo ora confronta tutti e tre i canali col vero evidenziatore libero e con l'equazione multiply25%, mantenendo tolleranze strette e il controllo sul nero dei contenuti. Non cambia il colore dell'app per adattarlo a un oracolo errato.

Il filmato CI della finestra zoom mostra che gli swipe lunghi saltavano direttamente dall'inizio del Workspace alle righe successive a Gesti e automatismi, che viene virtualizzata. Un helper condiviso usa brevi trascinamenti lenti e richiede comunque la riga reale esistente e toccabile. La voce riceve un identificatore accessibile stabile. Nessuna fixture salta l'interfaccia; scrittura, evidenziatore, annulla e zoom restano gesti e verifiche reali.

L'audit ha anche corretto un caso dei margini della finestra zoom: dopo un viewport limitato dalla pagina, ridurre i margini ripristina la vera larghezza del pannello. Una provaCore controlla il roundtrip. La formula è locale alla finestra facoltativa e non cambia doppio tap o cachePDF. Un controllo statico intercetta dichiarazioni multiple incompatibili con Observable prima di iniziare AppleCI.

[Verifica finale42001223527](https://github.com/sminikiller/NeuralNotes/actions/runs/42001223527), sorgentiab73e4f5bd9bb12f615cda1791ac373473c530c9: Core completo, nativi critici con tutte le nuove classi, i sette scenariUI ancora da concludere, Release e pacchettoPlaygroundsRelease con avvio. Riutilizza i quaranta scenariUI già conclusi, evitando di ripeterli per la sola formula dei margini o per il helper di scorrimento. In corso: non è dichiarato alcun nuovo PASS o upload0.29. La beta realmente caricata rimane1.0.0(177), PDF0.28.2.


QA visiva del set colori: esaminata la PNG originale della prova UI già passata (725F9891-C92E-4856-A9EF-CA1E41E01A2C, run41992864208). Selezione Biologia, cinque colori, modifica/creazione e descrizione delle preferenze per strumento visibili; pannello entro lo schermo, navigatore pagine compatto e canvas integri. Non sostituisce la prova ancora aperta della finestra zoom.
