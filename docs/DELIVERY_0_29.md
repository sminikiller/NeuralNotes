# NeuralNotes 0.29 — testo e scrittura assistita

Stato: implementazione candidata locale, non ancora compilata con SDK Apple e non pubblicata. La beta PDF 0.28.2 viene verificata e consegnata separatamente. Il precedente lavoro 0.28.1 rimane disponibile.

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

Eseguire l’intera fase con SDK26.6: test Core geometria/compatibilità/riordino/palette/audio, test nativi RTF/PDF e annulla campo attivo, canvas figlio/annulla-nuovo tratto/marker/gomma/coordinata, pixel moltiplica e rendering replay. Eseguire le prove UI della finestra con tratto vero, annulla/ripristina e ripristino del layout, palette, mantenendo le regressioni PDF, riconoscimento e marcatura già verdi. Ispezionare gli screenshot, verificare lo ZIP esatto della CI, quindi usare la corsia TestFlight esistente. Nessun risultato SDK ancora dichiarato per 0.29.

Restano da misurare su iPad fisico pressione Apple Pencil, latenza e rotazione durante una scrittura reale. Non sono verificabili con il solo parser Windows.
