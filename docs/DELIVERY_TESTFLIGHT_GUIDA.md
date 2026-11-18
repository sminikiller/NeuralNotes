# NeuralNotes su TestFlight — Guida completa

Dal **18 novembre 2026**, la build **1.0.0 (212)** è disponibile su TestFlight per il gruppo interno `io`. App Store Connect conferma `VALID` e `IN_BETA_TESTING`. [Caricamento](https://github.com/sminikiller/NeuralNotes/actions/runs/44290090049) · [Conferma Apple](https://github.com/sminikiller/NeuralNotes/actions/runs/44292223832).

## Cosa c’è in questa build

La **Guida completa** contiene 84 tutorial e 122 esercizi. Si può cercare per funzione, opzione, gesto o scorciatoia. Ogni prova indica le azioni da eseguire e il risultato atteso. L’utente conferma l’esito e l’app conserva il progresso sul dispositivo. [Manuale](GUIDA_FUNZIONI.md).

## Da provare sull’iPad

1. Aggiorna **NeuralNotes** da **TestFlight** e controlla la build in **Libreria → Informazioni su NeuralNotes**.
2. Crea un quaderno di prova. Apri **⋯ → Guida completa**, cerca **scarabocchio** o **forma trattenuta** e apri un tutorial.
3. Tocca **Torna al quaderno per provare**. Esegui l’esercizio, riapri la guida dallo stesso menu e scegli **Riprendi il tutorial**. Spunta **Esito verificato** dopo aver confrontato il risultato. Controlla che il progresso sia presente anche dopo aver riaperto l’app.
4. Prova **Apri le opzioni di qualsiasi strumento** tenendo premuta la gomma. Con un PDF di esempio prova anche **Ritaglia un pezzo di PDF negli appunti**, sia come immagine sia come testo selezionabile.

## Verifiche

Sorgenti del rilascio `1ea79b123f0e58ff8bc992be2cdc1e16e1dcd8a7`. Passati 454 XCTest Core, 98 test Swift Testing, 291 test applicativi e il test UI della guida su iPad Pro 13″ (M5). La build Release nativa è riuscita. [Verifica Apple](https://github.com/sminikiller/NeuralNotes/actions/runs/44285553227).

Per Swift Playgrounds, lo ZIP generato dagli stessi sorgenti si compila in Debug con Xcode 26.6. Sono stati confrontati 379 file, con verifica CRC e SHA-256 `0f8a853bda3730a7e89a9464ad73cdde5e36b378990d0649afd09465ae9fe2ad`. [ZIP Playgrounds della guida](https://github.com/sminikiller/NeuralNotes/actions/runs/44285553227/artifacts/14418514315).
