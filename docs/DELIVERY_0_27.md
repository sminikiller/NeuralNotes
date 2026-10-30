# NeuralNotes 0.27 — diagrammi e scrittura

Sorgenti verificati: `ae40c74c02aea385e7a2abaebd5832d945b6c085`.
Verifica completa: [41093624706](https://github.com/sminikiller/NeuralNotes/actions/runs/41093624706), sei job riusciti.
Beta **1.0.0 (142)** firmata e caricata su Apple con [41103296975](https://github.com/sminikiller/NeuralNotes/actions/runs/41103296975). Conferma esplicita nel log: Upload succeeded / UPLOAD_COMMAND_SUCCEEDED (30 ottobre 2026, 18:09 UTC). Apple sta elaborando il pacchetto; disponibilità nell’app TestFlight non ancora verificata.

## Novità

- Quattro punti blu sui blocchi: duplica e collega in una sola azione; trascina verso un altro oggetto per collegarlo, trattieni per lasciare un estremo libero.
- Connettori dritti, curvi e ortogonali, estremi riagganciabili e maniglia della curva. Seguono gli oggetti durante spostamento, ridimensionamento e rotazione; eliminare un blocco lascia il collegamento libero nella posizione precedente.
- Etichette centrate con formattazione, elenchi e rientri, adattamento del carattere e contrasto secondo il foglio. Le mappe AI usano blocchi e collegamenti modificabili con fonti conservate.
- Copia, spostamento tra pagine, ricerca, collegamenti audio, replay, PDF e backup includono i connettori e le etichette. La selezione usa il tracciato reale e le punte delle frecce.
- Evidenziatore libero da 1 a 80 punti reali, recenti separati e fusione moltiplica. Le parole digitali del PDF si evidenziano usando la stessa geometria della Lente. Sulle scansioni si riusano le parole già riconosciute dalla Lente, senza avviare OCR durante la scrittura.
- La figura riconosciuta rimane confermata fino al rilascio anche con piccoli movimenti. Il tratto irregolare non ricompare alla scrittura successiva; annulla/ripristina rispettano i singoli passaggi.

## Come provare sull'iPad

1. In TestFlight aggiorna NeuralNotes quando Apple rende disponibile la nuova build. Apri un quaderno esistente.
2. Tieni premuta la penna e attiva il riconoscimento mantenendo ferma la punta. Disegna una linea o un cerchio, fermati, muovi leggermente la punta e solleva. Scrivi un secondo tratto; annulla e ripristina.
3. Tieni premuto l'evidenziatore, scegli 1 o 2 punti e prova un tratto libero. Su un PDF digitale attiva Aggancia alle parole del PDF e passa sulla parola o subito sotto. Per una scansione usa prima la Lente, poi torna all'evidenziatore.
4. Crea una forma, selezionala con Oggetti e tocca uno dei quattro punti blu. Sposta il nuovo blocco: il collegamento deve seguirlo. Trascina un estremo verso un altro blocco per riagganciarlo.
5. Fai doppio tocco dentro la forma con Oggetti, modifica l'etichetta e salva. Seleziona il connettore per cambiare tracciato o stile.
6. Esporta PDF e backup nativo; importa il backup come copia e controlla blocchi, etichette, foto, collegamenti e audio. I quaderni originali restano nella libreria.

## Prove eseguite

- Core: 334 XCTest e 98 Swift Testing superati.
- Suite iPad nativa completa: 507 XCTest complessivi, inclusi quelli Core; 2 saltati per alias di percorso Darwin non applicabili al simulatore, zero fallimenti. Nessun doppio conteggio della suite Core.
- Interfaccia: tutti i 35 test superati, inclusi schema a sei blocchi con etichetta, scrittura PencilKit dopo conversione/cancellazione, doppio tocco zoom e geometria della barra pagine nei due orientamenti.
- Evidenziatore: misura effettiva da 1 pt nei punti e nel rendering, almeno il 98% dei glifi neri conservati, penna bianca sopra il colore, parole PDF ruotate a 0/90/180/270 gradi, dodici aggiornamenti con una sola ricostruzione della cache.
- Scansione: PDF composto solo da immagine, OCR Vision reale dopo la preparazione dell'evidenziatore, parola evidenziata, annulla/ripristina conservano le parole; nuovo inchiostro rende obsoleta la lettura precedente.
- Compatibilità: fixture 0.26, salvataggio e riapertura, PDF e backup/import, rimappatura di fonti e ancore audio. Aggiornamento automatico del binario 0.20.8 con quaderno e catalogo conservati.
- Build Release e archivio per dispositivo riusciti. Pacchetto Playgrounds compilato per simulatore e dispositivo, avviato dallo ZIP con 60 osservazioni. Controllo visivo di guida, diagrammi, etichetta, tratto nativo e barra pagine in verticale.

## Pacchetto e limiti

ZIP esatto della CI: `.verification/NeuralNotes-iPad-0.27.0.zip`.
SHA-256: `0a72cdcac7d37446021caa546d4ce0bee7c6e573088880b0eaac9fb86f285f5d`.
CRC integro e tutti i 284 sorgenti app/Core confrontati con la revisione verificata.

Le nuove proprietà dei modelli precedenti sono opzionali; originali delle immagini e vettori PencilKit sono conservati. Prove sul simulatore e misure sintetiche non sostituiscono latenza e falsi positivi della Pencil su iPad fisico. Nessuna attivazione iCloud o modifica ai servizi esterni; identità, firma e corsia TestFlight conservate. I lotti 0.28–0.31 restano successivi: le bozze locali del goniometro e delle transazioni non sono ancora funzioni dell'app.
