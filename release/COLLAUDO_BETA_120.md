# NeuralNotes — collaudo della prima beta TestFlight

## Versione verificata

- App: **1.0.0 (120)**, Bundle ID `com.lorenzominichilli.neuralnotes`.
- Caricamento GitHub: [run 40386418791](https://github.com/sminikiller/NeuralNotes/actions/runs/40386418791), commit `3bf6410c8a16a0f58ab17515242d4d251befe94f`, concluso con successo.
- Il confronto con `f5cfc8d` non mostra differenze nei sorgenti dell'app, nel progetto e nel generatore: i commit successivi al caricamento riguardavano la guida.
- L'utente conferma sull'iPad il raddrizzamento prospettico delle foto e il doppio tap per ingrandire e tornare al foglio intero. Questa è una conferma manuale, distinta dai test automatici.
- Questa corsia interna disattiva iCloud; non è una versione con sincronizzazione iCloud già attiva.

## Verifica automatica conclusa

Il 27 ottobre è stato controllato l'esito della [verifica completa 40391428100](https://github.com/sminikiller/NeuralNotes/actions/runs/40391428100), eseguita il 26 ottobre sul commit `331cf54ed395a3aa1f9da86a2b60f2924699f73a`: **tutti e sei i job sono riusciti**.

- **Core su macOS:** 280 XCTest e 98 test Swift Testing superati.
- **Test nativi sul simulatore iPad:** 422 XCTest superati, 2 saltati perché specifici degli alias Darwin; i corrispondenti controlli passano su macOS. Altri 98 test Swift Testing superati.
- **Interfaccia iPad:** tutti i 30 test superati, incluso il test completo dei doppi tap e del comando per tornare al foglio intero. Passa anche la nuova prova nativa sulla fine delle animazioni e sulla conservazione dell'inchiostro.
- **Backend locale:** isolamento SQL, ciclo di vita degli account, Auth e Storage passano; il trasporto verso il provider AI è simulato. Questo non dimostra che un backend pubblico sia già attivo.
- **Aggiornamento:** sostituzione del vecchio binario senza disinstallare; catalogo e manifest del quaderno di prova restano identici.
- **App Playground:** compilato il pacchetto ZIP effettivo, installato e avviato sul simulatore; processo vivo per tutte le 60 osservazioni e libreria o guida visibile.
- **Distribuzione:** archivio Release 1.0.0 (122) validato con SDK iOS 26 e le quattro categorie di API richieste nel manifest privacy. È un archivio **non firmato e non caricato**, non una nuova build TestFlight.

La build installata dall'utente resta la **120**. Le modifiche del commit verificato riguardano l'attesa dello stato effettivo nei controlli PostgreSQL e zoom, con segnalazione accessibile dello zoom in corso; geometria, durata e gestione dei tocchi dello zoom restano quelle già provate sull'iPad. Non è stata pubblicata una nuova build solo per eseguire questi controlli.

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
