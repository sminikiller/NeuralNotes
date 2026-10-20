# 0.3.1 — controllo del backup e lavoro rimanente

## Evidenza ricevuta

La foto dell’utente mostra il fallimento di “Backup completo: esportazione, importazione e nuova identità” con il messaggio generico NativeArchiveFailure.corrupt. Sono visibili PASS per pagine, PDF ruotato/import/export, OCR, sintesi, modello temporale audio, flashcard e SwiftData. La parte superiore dei risultati non è nella foto: non si deduce l’esito dei controlli non visibili. Il funzionamento della scrittura era già stato confermato dall’utente.

## Intervento

Il writer dell’archivio e il merge costruivano i percorsi relativi sottraendo il numero di componenti del percorso assoluto della root. È un punto fragile in presenza di URL di directory e normalizzazioni/alias Darwin. La foto non identifica la riga o la fase del fallimento: questa causa resta un’ipotesi da verificare sul dispositivo, non un crash riprodotto qui.

La 0.3.1 usa una scansione condivisa PackageFiles: visita ogni cartella e compone i nomi relativi dai nomi dei figli. Non sottrae più componenti assoluti. Conserva i limiti, la cancellazione, il rifiuto dei link simbolici e dei percorsi non validi. Esclude dal backup i sidecar `.DS_Store` e `._*`, lasciando intatti gli originali. Non ignora genericamente i file sconosciuti e non disattiva i checksum.

La diagnostica distingue “Esportazione del backup” da “Importazione del backup”. Gli errori del formato distinguono voce non valida, checksum, troncamento e dati dopo la fine dell’archivio. Se la correzione non risolve il problema, il prossimo risultato sarà più utile per individuarne la causa.

Formato `NNBOOK01` e schema dei documenti restano gli stessi. Non vengono cancellati o riscritti i quaderni sull’iPad da questa consegna.

## Verifiche

Cinque test XCTest aggiunti: nomi relativi e round trip con URL directory true/false, nomi Unicode/spazi e cartelle annidate; alias `/var` e `/private/var` sui sistemi che li espongono; esclusione dei sidecar senza cancellarli; rifiuto symlink prima di creare l’archivio; lettura del vettore CRC32 indipendente `123456789`.

Controlli locali superati: grafo Xcode 124 oggetti e membership, plist/privacy/asset, parsing di 54 file Swift autorevoli e packaging iPad con 49 sorgenti/risorse più manifest. Sono presenti 44 metodi XCTest ma **non eseguiti qui**. Windows non ha Swift o SDK Apple; Docker CLI è presente ma il motore non è in esecuzione e non è stato avviato. Non è stata eseguita una build Apple né riprodotto il fallimento iPad.

Aprire **NeuralNotes-iPad-0.3.1.zip** in una nuova cartella, conservando il vecchio progetto. Eseguire **Verifica sul dispositivo**. Se il backup passa, fare anche un export su File e reimportarlo come copia, controllando scrittura, immagini/PDF e, se presenti, registrazioni reali. Non usare “Elimina i dati dell’app”.

## Cosa manca per completare il prodotto

| Area | Già presente | Ancora necessario |
|---|---|---|
| Backup/affidabilità | Codice di export/import/merge, revisioni e controlli | Confermare questa correzione; recovery degli orfani, gestione spazio/purge, test di interruzione durante i commit |
| Editor | PencilKit, pagine, oggetti, schede e foto | Undo unificato di oggetti/pagine; ripristino schede al lancio; coordinamento di più finestre; qualità e memoria misurate |
| PDF | Import, annotazioni separate, ricerca testo ed export | Inchiostro vettoriale nel PDF esportato; copertura di crop/rotazioni e file grandi su iPad |
| Audio/OCR | Registrazione, timestamp, trascrizione locale e ricerca | Prove di registrazioni lunghe/interruzioni/drift; robustezza dei collegamenti dopo lazo/cancellazioni; OCR su grafia e foto reali |
| AI | Estrazione locale, ripasso, embedding opzionali; client e server Responses | Hosting HTTPS, credenziali/modello e prova live; qualità del tutor/grounding; classificazione argomenti; nessun LLM locale integrato |
| Sincronizzazione | Progetto local-first separato dal cloud | CloudKit, coda offline, conflitti e prova su due dispositivi; collaborazione successiva |
| Distribuzione | Sorgenti Xcode e App Playground | Build/test Apple, firma, configurazione TestFlight/App Store e verifiche accessibilità/prestazioni |

Non c’è una percentuale di completamento misurata. Funzioni implementate, prove superate e dipendenze esterne sono stati distinti per evitare di dichiarare il prodotto finito sulla sola base del codice.
