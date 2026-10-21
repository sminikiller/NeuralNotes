# Correzione 0.15.1 / build 28 — selettori del righello

22 ottobre 2026. La foto dell’iPad documenta un fallimento reale della compilazione della 0.15.0 in RulerGuideView: `move:` coincide con un metodo ereditato da UIResponder. Il tipo Swift del parametro non distingue due metodi con lo stesso selettore Objective-C; aggiungere soltanto override non è la correzione.

Rinominati l’azione e il relativo `#selector` in `nnHandleRulerPan:`. Anche la rotazione usa un nome specifico, `nnHandleRulerRotation:`. Nessun override di move viene introdotto. La ricerca delle altre azioni private Objective-C con nomi di modifica standard non ha trovato altre occorrenze nel progetto. Il comportamento e i dati del righello restano quelli della 0.15; nessuna migrazione o cancellazione dei quaderni.

Controlli: grafo di 406 oggetti, membership di 257 file Swift, 313 metodi XCTest presenti; grammatica e parsing del compilatore Swift in modalità 5. Questi controlli non risolvono i simboli UIKit e non avevano rilevato il conflitto della 0.15.0. La foto costituisce la prova del problema SDK; **nessuna compilazione Apple della patch è dichiarata riuscita**. L’ultimo tentativo CI documentato resta quello bloccato prima dei comandi, descritto nel [registro delle verifiche](ROADMAP_VALIDATION.md).

Core e backend non sono cambiati: non sono state rieseguite le loro suite per questa modifica ai selettori. Restano le prove effettive della 0.15.0: 182 XCTest Core (180 passati, due skip Darwin), 98 FSRS passati; backend 23 fixture nella lavorazione precedente. Non sono nuove prove del righello sull’iPad.

Pacchetto aggiornato `NeuralNotes-iPad-0.15.1.zip`, versione 0.15.1/build 28; sorgenti e report in `NeuralNotes-Sorgenti-0.15.1.zip`. Generazione dai sorgenti canonici, controllo integrità ZIP e confronto byte per byte. Aprire il pacchetto NeuralNotes.swiftpm intero e conservare la copia precedente con i suoi dati. [Funzioni e recupero della 0.15](DELIVERY_0_15_0.md).
