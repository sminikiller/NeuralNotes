# NeuralNotes 0.33.1

Apple ha ricevuto la build **1.0.0 (205)** il 17 novembre 2026 alle 14:38:25, ora italiana. [Upload TestFlight](https://github.com/sminikiller/NeuralNotes/actions/runs/44093381864).

App Store Connect conferma la build valida e attiva per il gruppo interno `io`. [Verifica di disponibilità](https://github.com/sminikiller/NeuralNotes/actions/runs/44095296305).

Nell’editor, Annulla e Ripristina restano a sinistra, la toolbar principale si adatta alla larghezza dei pulsanti e il timer REC si allinea accanto a Solo foglio. Una registrazione attiva non abbassa la toolbar. Nella vista Solo foglio la mini toolbar è ancorata nello stesso punto ed è espandibile. L’area di scrittura arriva al bordo inferiore e la barra pagine rimane compatta nella vista normale.

**Studio** è la prima voce del **+ cerchiato**. Si può aprire anche da **··· → Studio sul foglio**, dal menu della foto e dagli strumenti essenziali di Solo foglio. Il pannello contiene mappe, elenchi, scotch, post-it e capitoli introdotti nella [0.33](DELIVERY_0_33.md).

[Verifica Apple](https://github.com/sminikiller/NeuralNotes/actions/runs/44087496773) del commit `c659c86aba686b3e2513eb697555e7d4769e16f6`. Passati 452 XCTest Core, 98 Swift Testing, 291 test nativi e quattro test UI. I test verificano l’apertura di Studio dal catalogo e dalla mini toolbar, l’allineamento, il bordo inferiore in Solo foglio, la selezione degli oggetti e la barra pagine dopo la rotazione. Passate le compilazioni Debug e Release.

[ZIP Playgrounds verificato](https://github.com/sminikiller/NeuralNotes/actions/runs/44087496773/artifacts/14330978678). Tutti i 377 file corrispondono ai sorgenti verificati. Compilazione Release e avvio sul simulatore superati. SHA-256 `c21b86b1d86bd482e2689244dec7017239ca4edab6e07dc630f74beb71be6822`.

Sull’iPad, apri un quaderno in orizzontale e avvia una registrazione breve. Passa da vista normale a Solo foglio e riapri gli strumenti essenziali. Controlla che REC resti sulla stessa riga, che si possa toccare per aprire l’audio e che il foglio sfrutti il bordo inferiore. Poi apri Studio dal + cerchiato e inserisci una mappa o uno scotch.
