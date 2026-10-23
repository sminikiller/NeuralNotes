# Usare NeuralNotes 0.20.8 con il solo iPad

La 0.20.8 corregge l'icona mancante riprodotta nella compilazione del pacchetto App Playground. Lo ZIP consegnato è quello estratto e compilato dalla [run 39942124235](https://github.com/sminikiller/NeuralNotes/actions/runs/39942124235), con manifest AppleProductTypes e risorse, per simulatore iOS arm64/x86_64. Questo non è il compilatore fisico di Playgrounds sull'iPad. Restano sei test funzionali falliti della verifica generale precedente: [evidenze e limiti](FIXES_0_20_8.md).

La 0.20.4 disattiva la Lente dopo la selezione: scegli l'azione dalla barra, leggi l'anteprima e inserisci la nota solo se vuoi. [Nuovo flusso e verifiche](WORKFLOW_0_20_4.md).

La 0.20.3 corregge il conflitto UIKit `hidden` che impediva la compilazione della 0.20.2. [Patch e limiti](FIXES_0_20_3.md). Usare il nuovo ZIP indicato qui sotto.

1. Conserva il vecchio progetto Swift Playground e i suoi dati.
2. Scarica NeuralNotes-iPad-0.20.8.zip in una cartella nuova di File, decomprimi e apri NeuralNotes.swiftpm con Swift Playground. Include selezione di parole/area/immagine, note formattate modificabili e ricerca del testo dei PDF grandi; [comandi e limiti](DELIVERY_0_20_2.md). Restano le correzioni precedenti di layout, righello, foto, recupero e PDF fino a 1 GiB / 5.000 pagine. Il funzionamento sul dispositivo resta da confermare e i servizi AI pubblici non sono attivati automaticamente.
3. Premi Esegui app. Apri il package intero, non il singolo AppController.swift. Attendi il caricamento da iCloud/File prima di eseguire.
4. La nuova versione dichiara microfono, fotocamera e riconoscimento vocale. Il sistema chiede il consenso quando usi la funzione; la negazione deve lasciare disponibile la scrittura.
5. Sidebar → Verifica sul dispositivo → Esegui controlli sul mio iPad. Sono 35 controlli, non ancora eseguiti su questo dispositivo dalla sessione di sviluppo. [Comandi della 0.12.0 e limiti](DELIVERY_0_12_0.md), [verifiche effettive](ROADMAP_VALIDATION.md). Restano documentate [la trascrizione lunga](TESTING_0_9_1.md), [le funzioni della 0.9](STUDY_WORKSPACE_0_9.md), [salvataggio e recupero](CONSOLIDATION_0_8_1.md), [workspace e forme](TESTING_0_8.md), [zoom](FIXES_0_7_1.md) e [scorrimento](TESTING_0_7.md).

Le diverse copie del Playground possono avere dati separati. Per trasferire i quaderni, esportali dalla vecchia app e importa il .nnbackup dalla sidebar della nuova. Se hai già una cartella Notebooks accessibile in File, usa Recupero quaderni → Importa quaderni da una cartella. Il recupero automatico riguarda solo i pacchetti del contenitore corrente quando la libreria è vuota. Controlla la copia prima di abbandonare l’originale. Non premere Elimina i dati dell’app per risolvere un errore del progetto.

Per problemi di compilazione servono nome del file, riga e messaggio completo. Un warning di deprecazione e un errore rosso non sono la stessa cosa. Il progetto dispone ora di [verifica automatica su macOS](https://github.com/sminikiller/NeuralNotes/actions); i risultati effettivi sono in [VALIDATION.md](VALIDATION.md). Il compilatore e il comportamento del runner Swift Playground restano da verificare sull’iPad.

Il comando Nuova finestra è nel menu dell’editor; funziona solo se il processo ospitante espone più scene. Le schede interne funzionano nello stesso editor e il loro ripristino usa lo stato della scena iPadOS. Per provare il riavvio usa sempre la stessa copia del progetto.

[README](../README.md) · [Stato e limiti](VALIDATION.md).
