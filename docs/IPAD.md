# Usare NeuralNotes 0.15.0 con il solo iPad

1. Conserva il vecchio progetto Swift Playground e i suoi dati.
2. Scarica NeuralNotes-iPad-0.15.0.zip in una cartella nuova di File, decomprimi e apri NeuralNotes.swiftpm con Swift Playground. Include recupero da cartella, cestino pagine, cinque strumenti focus, righello vincolante e testo sul foglio. [Comandi e limiti 0.15](DELIVERY_0_15_0.md). La compilazione Apple resta da confermare.
3. Premi Esegui app. Apri il package intero, non il singolo AppController.swift. Attendi il caricamento da iCloud/File prima di eseguire.
4. La nuova versione dichiara microfono, fotocamera e riconoscimento vocale. Il sistema chiede il consenso quando usi la funzione; la negazione deve lasciare disponibile la scrittura.
5. Sidebar → Verifica sul dispositivo → Esegui controlli sul mio iPad. Sono 35 controlli, non ancora eseguiti su questo dispositivo dalla sessione di sviluppo. [Comandi della 0.12.0 e limiti](DELIVERY_0_12_0.md), [verifiche effettive](ROADMAP_VALIDATION.md). Restano documentate [la trascrizione lunga](TESTING_0_9_1.md), [le funzioni della 0.9](STUDY_WORKSPACE_0_9.md), [salvataggio e recupero](CONSOLIDATION_0_8_1.md), [workspace e forme](TESTING_0_8.md), [zoom](FIXES_0_7_1.md) e [scorrimento](TESTING_0_7.md).

Le diverse copie del Playground possono avere dati separati. Per trasferire i quaderni, esportali dalla vecchia app e importa il .nnbackup dalla sidebar della nuova. Se hai già una cartella Notebooks accessibile in File, usa Recupero quaderni → Importa quaderni da una cartella. Il recupero automatico riguarda solo i pacchetti del contenitore corrente quando la libreria è vuota. Controlla la copia prima di abbandonare l’originale. Non premere Elimina i dati dell’app per risolvere un errore del progetto.

Per problemi di compilazione servono nome del file, riga e messaggio completo. Un warning di deprecazione e un errore rosso non sono la stessa cosa. Il progetto dispone ora di [verifica automatica su macOS](https://github.com/sminikiller/NeuralNotes/actions); i risultati effettivi sono in [VALIDATION.md](VALIDATION.md). Il compilatore e il comportamento del runner Swift Playground restano da verificare sull’iPad.

Il comando Nuova finestra è nel menu dell’editor; funziona solo se il processo ospitante espone più scene. Le schede interne funzionano nello stesso editor e il loro ripristino usa lo stato della scena iPadOS. Per provare il riavvio usa sempre la stessa copia del progetto.

[README](../README.md) · [Stato e limiti](VALIDATION.md).
