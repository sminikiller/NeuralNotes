# Correzione 0.14.1 / build 26 — delegati del PDF

La foto dell’iPad documenta due errori di compilazione reali della 0.14.0 in `PDFConceptResearch.swift`: conformità ridondante di `ConceptPDFView` a `UIGestureRecognizerDelegate` e metodo ereditato dichiarato senza `override`. I controlli sintattici su Windows/Linux non avevano rilevato questi vincoli dell’SDK Apple.

`PDFView` espone già la conformità. La sottoclasse non la dichiara più e non ridefinisce più `gestureRecognizer(_:shouldReceive:)`. Il gesto della Lente filtra soltanto Apple Pencil tramite `allowedTouchTypes` ed è abilitato/disabilitato da `conceptMode`; non assegna sé stesso come delegato e lascia intatti i metodi ereditati di PDFKit. Questo evita anche di filtrare involontariamente i gesti nativi di selezione e scorrimento quando la Lente è spenta.

La prova Apple del PDF esterno ora verifica il riconoscitore identificato, l’ingresso solo Pencil, l’assenza di delegato personalizzato e l’attivazione/disattivazione. È predisposta, non eseguita. Le altre sottoclassi PDFView nel progetto sono state cercate: questa è l’unica.

Versione aggiornata a 0.14.1/build 26; pacchetti rigenerati dai sorgenti canonici con controllo byte per byte e integrità ZIP. Grafo, membership e parsing Swift vengono ricontrollati; non sostituiscono la compilazione con SDK Apple. Il Core e il backend sono invariati: restano valide le ultime esecuzioni di 174 XCTest Core (172 passati, due skip Darwin) e 98 FSRS, e i 23 test backend a fixture della 0.12. Non vengono dichiarati rieseguiti per questa patch.

La CI Apple rimane non disponibile per il blocco di fatturazione documentato nella run [39589913621](https://github.com/sminikiller/NeuralNotes/actions/runs/39589913621). Nessuna compilazione Apple della patch è dichiarata superata. La foto prova il fallimento della 0.14.0, non il funzionamento della nuova versione.

Apri l’intero `NeuralNotes.swiftpm` dello ZIP aggiornato. Conserva il vecchio Playground e i quaderni: non serve cancellare i dati per correggere il progetto. [Funzioni della 0.14](DELIVERY_0_14_0.md), [stato dei test](ROADMAP_VALIDATION.md).
