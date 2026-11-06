# NeuralNotes 0.30 — livelli per pagina

La fase è implementata e verificata sul commit **da31bc198ae6f29d86383d4855cf171dd2cffdaa**. La beta **1.0.0 (190)** è stata firmata e caricata su Apple il6novembre2026 alle13:38UTC con [42226140084](https://github.com/sminikiller/NeuralNotes/actions/runs/42226140084). Log Upload succeeded e UPLOAD_COMMAND_SUCCEEDED presenti. Elaborazione e disponibilità in TestFlight non ancora confermate.

## Cosa cambia

- Fino a16 livelli per pagina: mostra/nascondi, blocca, rinomina, riordina, duplica, svuota, elimina, unisci al livello sotto e regola l’opacità. Ogni modifica si annulla e ripristina.
- Penna, evidenziatore, gomma, lazo, testo e forme lavorano sul livello attivo. Gli altri proprietari restano protetti; il nome attivo compare discretamente sotto la toolbar. Un solo canvas PencilKit rimane vivo.
- Le pagine precedenti si aprono con la Base senza migrare o riscrivere gli archivi originali. I riferimenti dei disegni restano immutabili; cronologia, copia/spostamento tra pagine, backup nativo e importazione conservano tutti i proprietari, anche nascosti o bloccati.
- La fusione mantiene i gruppi modificabili, l’ordine fra oggetti e inchiostro, i dati dei punti, le maschere, i semi nativi e i rimandi audio. La ricerca/OCR comprende tutti i proprietari; la selezione interattiva riguarda quelli visibili.
- Export PDF, PNG e JPEG: tutti i livelli, solo i visibili o una scelta esplicita. Dal menu del singolo livello si apre **Esporta solo questo livello**. Il PDF conserva tracciati vettoriali e testo selezionabile una sola volta, anche con opacità e unioni annidate.

## Come provarlo sull’iPad

1. Apri un quaderno, premi **Livelli** nella barra superiore e aggiungi un livello. Il nome attivo appare sotto la toolbar.
2. Scrivi o disegna, poi tocca l’occhio: quel contenuto scompare e il PDF di sfondo rimane intatto. **Annulla** ripristina anche il proprietario attivo.
3. Blocca un livello e prova a selezionare o cancellare: i suoi contenuti rimangono protetti. Tocca un altro nome per lavorare lì.
4. Dal menu del livello prova nome, copia, riordino, opacità e unione. Una sola azione Annulla ripristina l’operazione.
5. Prova **Esporta solo questo livello**, poi l’export dei visibili. Per conservare integralmente tutti i livelli usa il formato nativo.

La guida completa dei livelli viene inclusa anche nel catalogo interattivo insieme alla fase0.31; queste istruzioni sono già disponibili nel manuale.

## Rendering e protezione dei dati

Il dettaglio viene preparato dopo un fallback pronto, senza attendere un secondo tocco. Le cache dei livelli hanno budget12+36MiB per host; buffer temporanei, anteprime, inchiostro e backingUIView sono separati:48MiB non è il picco totale. Le miniature vengono preparate una alla volta. La cache PDF in background della0.28.2 resta invariata.

Il PDF usa un contenitore di forme vettoriali costruito tramite API CGPDF pubbliche: carta/PDF importato rimangono in uno scope con i propri profili; soltanto i gruppi RGB creati dall’editor usano sRGB. Questo evita lo spostamento di colore dei gruppi Generic RGB generati da Quartz. Font, mappe Unicode e immagini vengono copiati come risorse, senza rasterizzare la pagina. Il contenitore scrive per pagina/proprietario e deduplica i flussi ripetuti; non carica l’intero quaderno in memoria. Limiti preventivi:2milioni di oggetti,128MiB per singolo flusso decodificato e40MP per risorsa immagine, non per documento.

Il renderer PDF ricostruisce geometricamente i pennelli testurizzati: le loro frange possono differire dal renderer privato PencilKit. PNG/JPEG mantengono l’aspetto raster, il nativo conserva tutti i dati modificabili. Il confronto foto misura gli interni e il centro della sovrapposizione, evitando di scambiare la frangia della penna sottostante per un cambiamento della foto. Le tolleranze pixel restano4 per colore e3 per contorni.

## Verifiche concluse

- [Verifica finale42221285845](https://github.com/sminikiller/NeuralNotes/actions/runs/42221285845), Xcode26.6: Core430 XCTest +98 Swift Testing,271 test nativi critici senza errori,2UI PDF/Livelli senza errori, **TEST SUCCEEDED** e **BUILD SUCCEEDED** in Release.
- App Playground reale in Release per dispositivo e simulatore, installazione e60 osservazioni del processo: PASS. Non è una prova su iPad fisico.
- La suite completa precedente42098289365 aveva concluso48/49 UI e l’aggiornamento conservando il quaderno; il caso residuo dei livelli e altri controlli sono passati nei5UI di42119500167. Sono conservate quelle prove senza ripetere le schermate non coinvolte dall’ultimo fix di export.
- Le prove native finali verificano opacità dell’intero gruppo, testo Unicode unico e selezionabile, assenza di immagini sostitutive per penna/testo, fusione/annulla, replay, proprietari, scambio senza secondo tocco, pixel delle foto e PDF sorgente con trasparenze proprie. Il file originale del PDF rimane identico.
- ZIP esatto **367file**, CRC e confronto dei sorgenti/risorse con il commit: PASS. SHA256 **a904aba3f278dedc86b98edb6c4505588930a7c258a0057e898d012d616eeb64**. Artifact13503374966 della run finale, non una ricostruzione locale.

Firma, identità dell’app, container e corsia TestFlight non cambiano. La beta continua senza iCloud firmato; nessuna espansione del backend. Le prove prolungate con Pencil e iPad fisico rimangono distinte dal collaudo automatico.
