# NeuralNotes 0.21.1 / build 46

## Annullamento e nuova scrittura

PencilKit può consegnare il disegno finale dopo `didEndUsingTool`. Inoltre il salvataggio può registrare quel tratto mentre il comando Annulla è già in corso. L’editor sceglieva la voce della cronologia prima di attendere il salvataggio: la voce selezionata e il disegno corrente potevano quindi appartenere a momenti diversi.

Il comando ora chiude il tratto in arrivo prima di salvare e sceglie la voce della cronologia soltanto dopo il salvataggio. L’attesa aggiuntiva è presente solo se rimane un gesto senza variazioni di disegno, con un massimo di circa 200 ms di attese programmate; non è un limite al tempo del salvataggio. Un nuovo tratto dopo Annulla elimina il vecchio ramo di Ripristina.

Il ripristino cancella gli stati temporanei dell’editor e installa un nuovo contenitore `PKDrawing` con i tratti dello snapshot. Inchiostro, maschere, trasformazioni e date dei singoli tratti restano conservati. La cronologia nativa residua viene svuotata, mentre Annulla/Ripristina continuano a usare la cronologia dell’editor.

Durante il ripristino, `CanvasHost` intercetta i nuovi tocchi tramite lo strato di protezione già usato per le pagine in apertura. Il canvas e il suo responder restano attivi, così PencilKit può terminare le notifiche pendenti. Non vengono disattivati e riattivati il riconoscitore nativo o la registrazione del suo UndoManager. La stessa sostituzione del disegno viene usata al cambio pagina.

Non sono previste migrazioni o cancellazioni dei documenti.

## Prove

- Penna ed evidenziatore: due tratti, annullamento del secondo, nuovo tratto in un’altra posizione, confronto di numero e posizione dei tratti, annulla/ripristina e ricaricamento dal documento.
- Ultimo tratto consegnato 30 ms dopo la fine del gesto: Annulla deve eliminare quel tratto e conservare il precedente; una nuova scrittura e il ricaricamento devono mantenere soltanto il contenuto corretto.
- Canvas con delegate e finestra UIKit: rimozione delle azioni native residue, conservazione della maschera del tratto sopravvissuto e disponibilità del ripristino dell’editor.
- Salvataggio sospeso e poi fallito: nuovi tocchi intercettati, responder attivo, cronologia riprovabile e normale accesso al canvas dopo l’errore.
- UI: input reale attraverso il riconoscitore di PencilKit sul simulatore; primo tratto visibile, annullamento, secondo tratto in un’altra zona, confronto dei pixel delle due zone e annulla/ripristina del nuovo tratto.
- Test esistenti di editor e affidabilità, compresi cambio pagina, animazione del libro, forme e cancellazione; quattro UI audio per lettura, modifica, archiviazione e condivisione.

## Risultati Apple

| Prova | Risultato |
| --- | --- |
| Core macOS, [39997944588](https://github.com/sminikiller/NeuralNotes/actions/runs/39997944588) | 265 XCTest e 98 FSRS passati. |
| Editor sul simulatore, stessa esecuzione | Tutti i 73 test passati: 43 integrazione e 30 affidabilità, comprese le quattro nuove regressioni. Nessuna esclusione o interruzione del runner. |
| UI, [40001794761](https://github.com/sminikiller/NeuralNotes/actions/runs/40001794761) | Tutti i cinque test passati: quattro audio e il ciclo completo di disegno/annulla/nuovo tratto/annulla/ripristina, con confronto dei pixel. `TEST SUCCEEDED`. |
| Identità del codice | Il seguito UI verifica tramite `git diff --exit-code` che app, Core, progetto, dipendenze e generatore coincidano con la revisione già verificata `7baad30`. Le successive modifiche riguardano soltanto test e CI; app invariata da `c0c9a91`. |
| Release iOS | `BUILD SUCCEEDED` nella run 39997944588. |
| ZIP App Playground | Estratto e compilato con il suo manifest reale, Xcode 16.4, simulatore iOS 18.5 arm64/x86_64, nella run 39997944588. |
| Struttura e backend | Controlli di progetto/grammatica/pacchetto e 53 test Node passati. Backend non modificato. |

La run 39997944588 era terminata con due errori UI: scheda audio non selezionata correttamente dal test e acquisizione dei pixel prima del rendering. Le prove UI sono state corrette e ripetute nella run 40001794761 sugli stessi identici sorgenti dell'app. Non viene presentata la prima run come una suite interamente verde; gli esiti positivi riportati provengono dalle due esecuzioni indicate.

## Pacchetto e limiti

ZIP Apple consegnato: `NeuralNotes-iPad-0.21.1.zip`, 506095 byte, 226 file. SHA-256: `b0f83fd9a40ef3dc2fb564fc613c74bc3cd561cd67c9daba3f7856d7e6cf5156`. Archivio verificato tramite CRC e confronto dei contenuti con i sorgenti; soltanto i fine riga dei file di testo vengono normalizzati per confrontare Windows e macOS.

I test UI sul simulatore usano il dito per generare input nativo nel canvas. Non equivalgono a una prova della Apple Pencil fisica sull’iPad dell’utente. I servizi online e le prove hardware ancora aperte sono descritti nella consegna 0.21.0; questa correzione riguarda l’editor.
