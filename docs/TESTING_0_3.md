# NeuralNotes 0.3 — percorso sul tuo iPad

## Apertura e dati

Salva `NeuralNotes-iPad-0.3.zip` in una nuova cartella di File, estrai e apri **NeuralNotes.swiftpm** con Swift Playground, quindi **▶︎ Esegui app**. Conserva il progetto precedente: un nuovo App Playground può avere uno spazio dati diverso. Non premere “Elimina i dati dell’app”. Puoi importare una cartella `.nnbook` esportata dalle versioni precedenti; i nuovi export sono file `.nnbackup`. L’importatore dei quaderni non accetta progetti `.swiftpm`.

L’utente ha confermato che nella 0.2.2 l’inchiostro è visibile sul foglio. La segnalazione residua riguarda il controllo della carta. La 0.3 verifica gli override dichiarati di carta/canvas e legge pixel di disegni neri e bianchi renderizzati sotto aspetto chiaro e scuro, evitando il confronto dei tratti effettivi di una vista UIKit fuori finestra. L’esito di questa nuova prova sull’iPad è ancora da conoscere.

## Funzioni e criteri di accettazione

| Funzione | Prova | Risultato richiesto |
|---|---|---|
| Diagnostica | Libreria → Verifica sul dispositivo | Dodici controlli verdi; condividere i risultati di un eventuale fallimento senza cancellare dati |
| Schede | Scrivi e studia → + sulla barra superiore | Apri un secondo quaderno e torna al primo: pagina, strumenti e contenuto conservati; nessuna scrittura sul documento sbagliato |
| Cambio scheda/audio | Registra e scrivi, poi cambia scheda | Salvataggio e pausa dell’audio; nessuna registrazione nascosta nella scheda inattiva; ripresa volontaria al ritorno |
| Pagine | Pulsante Pagine nella toolbar | Miniature reali, navigazione corretta, Riordina e trascina le righe; ordine conservato dopo riavvio |
| Titoli/segnalibri | Tieni premuta una miniatura | Rinomina, aggiungi segnalibro, filtra Solo segnalibri e riapri dopo riavvio |
| Oggetti | Strumento Oggetti, seleziona testo/immagine | Cornice, trascinamento stabile allo zoom; angolo inferiore destro ridimensiona; duplica/elimina o apri Modifica |
| Foto | Azioni → Inserisci da Foto | Immagine decodificata/ridotta, selezionabile sul foglio e conservata dopo riavvio |
| Copertina | Menu contestuale del quaderno → Copertina fotografica | Scegli da Foto e salva: visibile in griglia, elenco e riepilogo, anche dopo riavvio; copertina a colori ripristinabile |
| Audio da tratto | Scrivi durante la registrazione; poi Ascolta tratto e toccalo | Registrazione in pausa se necessario, riproduzione dal timestamp associato |
| Backup | Esporta quaderno nativo → Salva su File; poi sidebar → Importa quaderno o backup | File `.nnbackup`; copia con pagine, vettori, media, copertina, esercizi e riferimenti indipendenti. Originale intatto |
| Unione | In un altro quaderno: Aggiungi pagine da un backup | Pagine in coda, originali conservati, media e riferimenti della copia utilizzabili |
| Ripasso | Azioni → Flashcard e ripasso → Crea esercizi dalle fonti | Domanda, Mostra risposta, Ancora/Bene/Facile; progressi e prossimo ripasso persistono dopo riavvio |
| Flashcard personali | Compila domanda e risposta nel pannello Ripasso | Salva con riferimento alla pagina corrente; elimina tramite scorrimento laterale |
| Schema di area/foto | Importa foto, Riconosci un’area, seleziona e riconosci, Crea schema dell’area | Schema estrattivo salvato con fonte della pagina e riapribile nello storico di Studia |
| Storico studio | Studia → Elaborazioni salvate | Riapertura, condivisione testo e navigazione alle fonti del quaderno attivo |
| AI remota | Con server configurato: Studia → backend remoto | Consenso/token necessari; risposta con riferimenti ammessi; errori espliciti per token scaduto, limite o timeout |

Per PDF, salvataggio, interruzioni audio e OCR seguire anche [TESTING_0_2.md](TESTING_0_2.md). Completare un ciclo chiusura/riapertura dello stesso progetto. Verificare portrait, landscape, Split View e dark mode.

## Formato e affidabilità

SwiftData mantiene lo schema v1. Titolo/segnalibro pagina, copertina e flashcard sono campi JSON opzionali: i documenti precedenti restano decodificabili. L’archivio `NNBOOK01` contiene indice JSON, payload non compressi e checksum CRC32. Lettura/scrittura a blocchi da 256 KB, massimo 16 GB e 50.000 file, indice massimo 16 MB: l’audio completo non diventa un singolo valore Data. I checksum rilevano corruzione, non attestano autenticità.

L’importazione non modifica il file originale: estrazione temporanea, controllo di struttura/file/percorsi e poi registrazione della copia. I payload PencilKit/PDF/media devono comunque essere decodificati dai framework della piattaforma. Nuovi UUID per documento, pagine, audio, elementi, elaborazioni e flashcard; i riferimenti locali vengono rimappati. I riferimenti a documenti esterni rimangono esterni.

L’unione copia i media sotto un prefisso proprio, scrive header/catalogo e aggiorna il manifest per ultimo. Un’interruzione può lasciare file o voci di catalogo non utilizzati; non sostituisce pagine/media originali. Non c’è una transazione atomica unica su tutti i file né purge automatico delle pagine eliminate. Export e unione richiedono audio in pausa.

## Limiti aperti

- Compilazione Apple, XCTest, gesti, latenza, memoria e registrazioni reali da verificare: Windows non dispone di Swift/Xcode/SDK Apple.
- Sei schede per sessione, un solo canvas montato. Ripristino automatico delle schede al lancio e più finestre simultanee non implementati.
- Undo/redo riguarda l’inchiostro PencilKit; oggetti e riordini non hanno uno storico unificato.
- Il collegamento audio usa curva interpolata e timestamp originali. Lazo e cancellazioni complesse richiedono prove; drift non misurato.
- Schemi e flashcard automatici locali sono estrattivi. Nessun LLM locale o modello Core ML personalizzato installato/simulato.
- Backend Responses reale nel codice, con sette test locali: modello, credenziali, hosting HTTPS e prova live ancora necessari.
- CloudKit/collaborazione tra dispositivi, import ZIP generici e distribuzione firmata/TestFlight non attivi. CloudKit resta progettato separatamente come richiesto nel prompt originale.
- Export PDF: PDF e testo via Core Graphics, inchiostro raster per singola pagina; il formato nativo conserva i vettori.

La 0.3 è un ampio avanzamento funzionale, non una dichiarazione di equivalenza completa a Goodnotes o di distribuzione pronta.
