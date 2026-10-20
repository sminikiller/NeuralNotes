# Usare NeuralNotes 0.9.1 con il solo iPad

1. Conserva il vecchio progetto Swift Playground e i suoi dati.
2. Scarica NeuralNotes-iPad-0.9.1.zip in una cartella nuova di File, decomprimi e apri NeuralNotes.swiftpm con Swift Playground.
3. Premi Esegui app. Apri il package intero, non il singolo AppController.swift. Attendi il caricamento da iCloud/File prima di eseguire.
4. La nuova versione dichiara microfono, fotocamera e riconoscimento vocale. Il sistema chiede il consenso quando usi la funzione; la negazione deve lasciare disponibile la scrittura.
5. Sidebar → Verifica sul dispositivo → Esegui controlli sul mio iPad. Sono 27 controlli. Prova [la trascrizione lunga della 0.9.1](TESTING_0_9_1.md) e [le funzioni della 0.9](STUDY_WORKSPACE_0_9.md). Prova [compilatore, salvataggio e recupero della 0.8.1](CONSOLIDATION_0_8_1.md). Prova [workspace, toolbar, forme e copertine](TESTING_0_8.md). Prova [lo zoom con doppio tocco](FIXES_0_7_1.md). Poi [prova scorrimento e voltata della 0.7](TESTING_0_7.md) e le regressioni precedenti.

Le diverse copie del Playground possono avere dati separati. Per trasferire i quaderni, esportali dalla vecchia app e importa il .nnbackup dalla sidebar della nuova. Controlla la copia prima di abbandonare l’originale. Non premere Elimina i dati dell’app per risolvere un errore del progetto.

Per problemi di compilazione servono nome del file, riga e messaggio completo. Un warning di deprecazione e un errore rosso non sono la stessa cosa. Il progetto dispone ora di [verifica automatica su macOS](https://github.com/sminikiller/NeuralNotes/actions); i risultati effettivi sono in [VALIDATION.md](VALIDATION.md). Il compilatore e il comportamento del runner Swift Playground restano da verificare sull’iPad.

Il comando Nuova finestra è nel menu dell’editor; funziona solo se il processo ospitante espone più scene. Le schede interne funzionano nello stesso editor e il loro ripristino usa lo stato della scena iPadOS. Per provare il riavvio usa sempre la stessa copia del progetto.

[README](../README.md) · [Stato e limiti](VALIDATION.md).
