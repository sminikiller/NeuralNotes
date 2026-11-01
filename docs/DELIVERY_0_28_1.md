# NeuralNotes 0.28.1 — correzioni dell’editor

Stato: implementazione raggruppata; controlli locali superati, verifica Apple finale da eseguire. Non ancora pubblicata su TestFlight. La beta già caricata resta 1.0.0 (159).

## Correzioni

1. **Pagina nuova:** la sostituzione della sessione nativa invalida prima il vecchio contenuto. Il livello di inchiostro vuoto resta invisibile e riappare al primo aggiornamento del nuovo tratto; l’input rimane disponibile. I livelli del foglio e le anteprime continuano a essere separati per pagina.
2. **Lazo:** la scelta predefinita seleziona insieme inchiostro e oggetti dell’app. Archi e poligoni vengono controllati sul loro contorno, con intersezione del lazo; il centro del riquadro non è più l’unico criterio. Gli oggetti bloccati restano protetti. La selezione del solo inchiostro PencilKit rimane un’opzione esplicita.
3. **Stile oggetti:** il primo comando della barra di selezione apre il pannello completo per contorno, colore, spessore, tratto, riempimento, opacità e parametri. Toolbar, menu contestuale e Solo foglio condividono il comando. La finestra conserva pagina e selezione di origine, senza reinizializzare le modifiche del pannello. Un’applicazione costituisce un passo di annulla.
4. **Guide:** righello più largo, trascinamento con un dito, rotazione con due dita e pizzico per ridimensionare; con scrittura a dito attiva, lo spostamento usa due dita. Suggerimento esterno. Aggiunte le squadre 45° e 30°/60° con aggancio a ciascuno dei tre lati; il lato scelto resta lo stesso fino al rilascio.
5. **Riconoscimento:** secondo adattamento degli angoli per figure chiuse irregolari, margine per angoli retti disegnati a mano e rimozione del vertice artificiale quando il tratto inizia lungo un lato. L’anteprima usa la figura riconosciuta che sarà salvata.
6. **Tutti gli strumenti:** elenco organizzato per attività. Ogni riga offre sia pressione prolungata sia pulsante delle opzioni, anche per strumenti non nei preferiti. Aprire le opzioni non spegne una guida già attiva. Le modifiche alle guide aggiornano immediatamente la visualizzazione.
7. **Evidenziatore:** Parole e Tratto libero usano il medesimo colore al 25%. Tutte le larghezze libere hanno anteprima personalizzata, senza il livello nativo che poteva mascherarla. Il PDF viene composto con il colore nello stesso contesto e la scrittura resta sopra. L’anteprima ritaglia solo l’impronta del gesto, conserva una base per tratto e non ricostruisce il PDF a ogni campione. Le parole già evidenziate non scuriscono durante la ripetizione.
8. **Workflow:** separati stile delle forme selezionate e stile per le nuove forme; un solo pannello condiviso per ciascuna funzione. I menu di inserimento restano scorciatoie degli stessi comandi, senza implementazioni alternative.

## Controlli

- Controllo locale di progetto, risorse e grammatica dei sorgenti Swift; nessuno di questi sostituisce la compilazione SDK.
- Nove test Python di preflight distribuzione superati.
- Aggiunti test Core su squadre, aggancio, intersezione degli archi/poligoni e figure disegnate a mano con partenza lungo un lato.
- Aggiunti test nativi su lazo misto, applicazione dello stile/annulla, visibilità della pagina vuota, opzioni e ridimensionamento guide, anteprima libera prima del rilascio e corrispondenza dei pixel tra Parole, Tratto libero e anteprima su PDF.
- Rafforzata la prova UI esistente della stella per usare il Lazo predefinito. Nuova prova UI delle opzioni del goniometro fuori dai preferiti e delle due squadre.
- Compilazione Apple, XCTest e prove UI: esito ancora da acquisire prima di dichiarare la consegna verificata.

Il pacchetto locale 0.28.1 è un candidato: la consegna userà il pacchetto esatto della verifica finale. Non sono cambiati identità, firma, segreti, backend o sincronizzazione.
