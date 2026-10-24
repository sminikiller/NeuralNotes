# NeuralNotes 0.24.0 / build 51 — foto e centro sincronizzazione

## Raddrizzamento non distruttivo

- Quattro vertici normalizzati con origine in alto a sinistra, ordinamento, controllo di convessità e dimensioni ricavate dalla media dei lati opposti. Il validatore rifiuta coordinate non finite, fuori immagine, quadrilateri degeneri o incrociati.
- `ImageElement` conserva prospettiva, rotazioni di un quarto di giro e miglioramento come metadati facoltativi. Le immagini dei vecchi quaderni continuano a decodificarsi. Nessuna migrazione della libreria SwiftData.
- Il pannello foto offre Rettangolo e Raddrizza, quattro maniglie da 44 punti, ingrandimento durante il trascinamento, rilevamento con Vision e alternativa rettangoli, rotazioni e contrasto/nitidezza. Il rilevamento automatico parte entrando in Raddrizza senza una correzione già impostata. Un risultato tardivo non sostituisce angoli modificati manualmente.
- L’ordine è: orientamento EXIF, prospettiva, rotazione, miglioramento, crop. La modifica della prospettiva o della rotazione azzera il crop, perché cambia il riferimento del ritaglio.
- Le maniglie aggiornano solo il contorno; il filtro di anteprima viene calcolato fuori dal main actor. Il rendering finale è condiviso da canvas, immagini esportate, PDF e Lente. La cache distingue tutte le correzioni.
- Camera, Foto e importazione di un’immagine passano dal pannello. Raddrizza è disponibile anche dalla selezione e dal menu contestuale delle immagini. Foto e chiedi applica le stesse correzioni all’immagine inviata all’AI e le conserva se la foto viene inserita nel quaderno.
- L’asset di base conservato all’importazione resta intatto; confermare modifica unicamente i metadati della pagina con la normale cronologia annulla/ripristina. Un’app precedente può ignorare questi nuovi metadati e mostrare l’immagine senza correzione.

## Account e centro sincronizzazione

- Un unico pulsante Account e servizi nella barra della libreria riunisce accesso, cloud NeuralNotes, iCloud e motore AI, con il rispettivo stato.
- Il centro mostra account, data dell’ultimo backup confermato, coda e conflitti senza contarli due volte.
- Backup alla chiusura facoltativo e distinto dalla sincronizzazione bidirezionale periodica. Si applica ai quaderni esplicitamente collegati all’account con Sincronizza adesso; non include automaticamente quaderni di un altro utente presenti nella libreria locale condivisa. I quaderni invariati non generano un’altra versione.
- La preferenza Solo Wi-Fi usa `NWPathMonitor`: Wi-Fi disponibile, connessione non costosa e non limitata. La copia preparata resta nella coda persistente; al ritorno della rete o al successivo controllo nell’app riprende l’invio. Le sessioni automatiche vietano anche traffico cellulare, costoso o limitato. I comandi manuali possono usare la rete disponibile.
- La preparazione attende il rilascio del quaderno da parte dell’editor e usa la coda esistente. Le chiusure durante un’altra operazione vengono serializzate. Non è un servizio di upload garantito dopo la terminazione dell’app da parte di iPadOS.
- Badge sulle copertine e nell’elenco: copia nel cloud con data, in coda, conflitto, solo sull’iPad. Se l’account è connesso ma l’indice non è stato verificato, il badge lo indica senza dichiarare il quaderno solo locale.
- Versioni cloud paginate con revisione, data e dimensioni. Scarica questa versione come copia verifica dimensioni e SHA-256 e importa con identità nuove, senza sostituire il quaderno corrente.
- Le preferenze e la coda rimangono separate per utente e servizio. Il logout non cancella né separa fisicamente i quaderni locali.

## Backend

- `GET /v1/platform/snapshots?document=<UUID>&offset=<n>`: 50 revisioni per pagina, dalla più recente, filtrate sul proprietario autenticato. I percorsi Storage non vengono esposti nell’elenco.
- `GET /v1/platform/download?document=<UUID>&revision=<n>`: URL firmato per una singola revisione, valido 60 secondi. RLS, filtro esplicito sul proprietario e verifica del percorso precedono la firma. Il download della versione attuale e quello dei materiali community restano compatibili.
- Nessuna nuova migrazione SQL: `nn_snapshots`, gli oggetti immutabili e le policy del proprietario esistono già. Il gateway deve essere aggiornato per esporre i due percorsi.
- Il codice predisposto non attiva un hosting pubblico né abilita automaticamente CloudKit: occorrono ancora servizio pubblicato e credenziali/configurazione di distribuzione già descritte in `backend/ACTIVATION.md`.

## Verifica

Le evidenze e i risultati della compilazione Apple vengono riportati qui a completamento dei test. I controlli di sintassi eseguiti su Windows non sostituiscono il type-checking Apple o il collaudo fisico di fotocamera, Pencil e iCloud.
