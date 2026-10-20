# NeuralNotes 0.7.1 — build 14

Il doppio tocco con le dita o doppio clic con puntatore alterna due viste:

1. Dal foglio intero centrato passa alla larghezza dell’area editor: il bordo sinistro e quello destro del foglio coincidono con i bordi del canvas, senza il precedente margine di 12 punti. In orizzontale si vede una porzione più alta del foglio da scorrere verticalmente.
2. Il doppio tocco successivo ripristina il foglio intero con i margini vuoti. Da un ingrandimento manuale il doppio tocco torna al foglio intero.

Il comando **Pagina intera** nella barra continua sempre a ripristinare il foglio intero. Con disegno tramite dito attivo usa il doppio tocco con due dita; Pencil rimane esclusa dal gesto. Lo zoom mantiene il centro verticale visibile quando possibile e non modifica l’inchiostro. Vale per pagina singola, scorrimento verticale continuo e sfoglio orizzontale. Rotazione, cambio modalità e apertura di una nuova pagina ripristinano la vista intera come prima; il passaggio continuo di pagina conserva invece lo zoom e la posizione del documento.

## Prova su iPad

Apri NeuralNotes-iPad-0.7.1.zip come progetto separato, conservando il precedente e i backup dei quaderni.

1. Con iPad in orizzontale, apri un foglio verticale e premi Pagina intera. Controlla i margini vuoti laterali.
2. Fai doppio tocco sul foglio: i bordi laterali devono raggiungere quelli dell’editor. Scorri verso il basso e scrivi un tratto con Pencil.
3. Ripeti il doppio tocco: il foglio deve tornare interamente visibile e centrato. Il tratto deve restare nella stessa posizione del documento.
4. Ripeti più volte, anche in verticale, in focus e nelle tre modalità di navigazione. Nel flusso continuo prova una pagina successiva alla prima e fogli di formati diversi.
5. Prova doppio clic con mouse/trackpad se disponibile, disegno con dito e due dita per il gesto, zoom manuale seguito da doppio tocco e pulsante Pagina intera dopo la vista a larghezza.

## Verifiche

Due nuove regressioni di integrazione controllano bordi, ritorno alla geometria iniziale, ripetizione/rotazione, dati dell’inchiostro e pagina attiva nelle tre modalità. Aggiornato il test UI per la sequenza completa dei due doppi tocchi e il controllo geometrico già presente in Verifica sul dispositivo. Totale: 115 metodi XCTest forniti e 22 controlli incorporati.

Su Windows si verificano struttura del progetto, grammatica Swift e contenuti dei pacchetti. Compilazione Apple, XCTest, riconoscimento reale del gesto e animazione non eseguiti qui. [Validazione](VALIDATION.md) · [Scorrimento e voltata](TESTING_0_7.md).
