# NeuralNotes — collaudo della prima beta TestFlight

## Versione verificata

- App: **1.0.0 (120)**, Bundle ID `com.lorenzominichilli.neuralnotes`.
- Caricamento GitHub: [run 40386418791](https://github.com/sminikiller/NeuralNotes/actions/runs/40386418791), commit `3bf6410c8a16a0f58ab17515242d4d251befe94f`, concluso con successo.
- Il confronto con `f5cfc8d` non mostra differenze nei sorgenti dell'app, nel progetto e nel generatore: i commit successivi al caricamento riguardavano la guida.
- L'utente conferma sull'iPad il raddrizzamento prospettico delle foto e il doppio tap per ingrandire e tornare al foglio intero. Questa è una conferma manuale, distinta dai test automatici.
- Questa corsia interna disattiva iCloud; non è una versione con sincronizzazione iCloud già attiva.

## Trasferire un quaderno da Playgrounds, un passo alla volta

1. Apri l'app esistente dentro Swift Playgrounds e scegli **un solo quaderno di prova**, con scrittura a penna, una foto e, se presenti, audio e trascrizione.
2. Dal menu di esportazione scegli il **formato nativo / backup del quaderno**, non PDF o solo testo.
3. Salva il file nell'app **File**, in una cartella che ritrovi facilmente. Conserva questa copia.
4. Apri NeuralNotes installata da **TestFlight**. Nella libreria usa **Importa quaderno o backup** e seleziona il file appena salvato.
5. Controlla numero e ordine delle pagine; apri una pagina iniziale, una centrale e l'ultima. Verifica inchiostro, testo e immagini, incluso un eventuale ritaglio o raddrizzamento.
6. Apri l'audio importato: avvia la riproduzione e spostati verso la fine. Controlla che anche la trascrizione e i suoi tempi siano presenti.
7. Chiudi il quaderno, riaprilo e verifica che il contenuto sia rimasto. Aggiungi un piccolo tratto di prova, chiudi e riapri di nuovo per verificare il salvataggio.
8. Quando il primo quaderno è corretto, ripeti per gli altri. **Conserva l'app Playgrounds e gli export originali** finché hai verificato tutti i quaderni.

Le due app usano contenitori diversi: l'assenza dei vecchi quaderni all'apertura della beta non dimostra che siano stati cancellati. La migrazione manuale va verificata con i file effettivi dell'utente; il test automatico di aggiornamento della stessa app non copre da solo il passaggio da Playgrounds.
