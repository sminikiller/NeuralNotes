# NeuralNotes 0.26 — Aggancio e allineamento

Implementazione candidata, non ancora verificata con SDK Apple né pubblicata. Ultima beta caricata: 1.0.0 (128), fase 0.25.

## Contenuto
- Motore Core per bordi/centri di oggetti e pagina, margine carta, griglia normale/isometrica, spazi uguali, ridimensionamento e rotazione. Soglia 6 punti schermo convertita con lo zoom.
- Indice per celle degli assi e vicini ordinati costruito una sola volta a inizio gesto. Guide temporanee da 1 pixel fisico, mai salvate. Le query di spaziatura esaminano fino a 32 vicini per lato.
- Workspace: preferenze opzionali per oggetti, griglia, guide e proporzioni. Default: oggetti e guide attivi, griglia attiva solo sui modelli di carta con reticolo.
- Secondo dito durante un gesto oppure ⌥ sospendono l’aggancio senza spostare il punto di trascinamento primario. Due dita a inizio gesto restano disponibili per scorrere.
- Menu selezione e menu contestuale: sei allineamenti, distribuzione orizzontale/verticale, stessa larghezza/altezza; gruppi di inchiostro inclusi. Oggetti bloccati esclusi. Dimensione verticale del testo ottenuta scalando font e larghezza per conservare le righe.
- Maniglie delle forme e disegno di nuove forme usano griglia e agganci. La rotazione produce feedback leggero quando entra in uno scatto.

## Compatibilità e limiti
Nessun formato della pagina modificato: solo Workspace.snapping opzionale. Nessuna nuova dipendenza, modifica alla firma o attivazione iCloud. Fixture 0.25 con forme/stili/foto per apertura, salvataggio, PDF e backup. Il collaudo sul simulatore e i tempi del runner non attestano 60 fps o il comportamento fisico della Pencil sull’iPad 10.

## Verifiche
In corso: test Core della geometria, test nativi con annulla/ripristina, compatibilità e PDF, test UI di selezione e preferenze. Nessun risultato SDK dichiarato prima dell’esecuzione.
