# NeuralNotes 0.20.5 / build 41 — riduzione delle espressioni SwiftUI della Lente

23 ottobre 2026. L'utente segnala che la build si blocca, senza un nuovo messaggio del compilatore o log di Playgrounds. **La causa del blocco sull'iPad non è accertata.** Non viene attribuita con certezza a memoria, prestazioni del dispositivo, cache o timeout del compilatore.

## Cosa risulta verificato

- La 0.20.4 supera grammatica e parsing Swift 5; questi controlli non compilano UIKit/SwiftUI e non possono dimostrare che la build Apple riesca.
- La CI GitHub più recente visibile è ancora ferma al commit `2372f89`: [run 39858791254](https://github.com/sminikiller/NeuralNotes/actions/runs/39858791254), senza step eseguiti e con job Apple saltato per il blocco di fatturazione già documentato. Le patch successive non hanno avviato nuove run identiche. Questo blocco del servizio non identifica il problema in Playgrounds.
- Il corpo di `LensPanel` univa conversazione, anteprima, comandi, riferimenti, fogli e callback in un'unica grande espressione SwiftUI. Nel progetto esiste già un precedente errore reale di timeout del type checker in `EditorView`, documentato nella [0.20.1](DELIVERY_0_20_1.md). Non è una prova che questa sia la causa della segnalazione attuale.

## Intervento nella 0.20.5

Diviso il pannello in viste con tipi opachi indipendenti: intestazione, stato delle fonti, conversazione, anteprima, azioni, stato della generazione, comandi rapidi e campo domanda. Estratto il callback del glossario. Divisi anche i pulsanti della risposta della Lente: Vai alla nota, Inserisci, Scarta e Copia.

L'intervento riduce l'ampiezza delle singole espressioni da risolvere e serve a contenere il rischio di timeout del type checker. **Non è stata misurata una riduzione del tempo di build e non viene dichiarato risolto un errore Apple non disponibile.**

Il flusso rimane quello della 0.20.4: selezione temporanea, ritorno allo strumento precedente, risposta in anteprima, inserimento esplicito o scarto. Non cambiano provider, richieste, credenziali, modelli del documento o dati salvati.

## Verifiche

Grafo/membership: 468 oggetti, 300 file Swift, 405 metodi XCTest individuati; grammatica, controlli AST e parsing Swift 6.1.2 in modalità 5. Verifica ZIP e corrispondenza byte per byte con i sorgenti. Queste sono verifiche locali, non type checking con l'SDK Apple.

Core e backend invariati, senza ripetere suite che non coprono il problema di build SwiftUI: ultimi risultati Core della 0.20.4, 260 XCTest (258 passati, due skip Darwin) e 98 FSRS; backend 48 test e integrazione locale della 0.20.2 con modello simulato. Nessuna nuova prova iPad, simulatore, CI Apple o provider live.

## Pacchetto

`NeuralNotes-iPad-0.20.5.zip`: decomprimere in una cartella separata e aprire il pacchetto `NeuralNotes.swiftpm` intero con Playgrounds. Conservare il vecchio progetto e i quaderni. Non serve eliminare i dati dell'app per sostituire i sorgenti; non è un rimedio a un errore di compilazione. Se compare un nuovo errore SDK, la diagnosi va corretta in base al file e alla riga indicati, senza dedurla dai soli test Core.
