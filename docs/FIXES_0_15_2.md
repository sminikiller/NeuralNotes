# Correzione 0.15.2 / build 29 — override del righello

22 ottobre 2026. La seconda foto documenta un errore di compilazione rimasto in RulerGuideView dopo la patch 0.15.1. La patch precedente era incompleta: oltre al conflitto del selettore move:, gestureRecognizerShouldBegin(_:) era dichiarato senza override.

UIView definisce già questo metodo: [documentazione Apple](https://developer.apple.com/documentation/uikit/uiview/gesturerecognizershouldbegin%28_%3A%29). La dichiarazione ora usa `override func gestureRecognizerShouldBegin`. Restano i nomi dedicati nnHandleRulerPan: e nnHandleRulerRotation: della patch precedente. Verificati gli altri metodi della classe: draw ha già override, l’inizializzatore coder è required e gli altri due callback del delegato hanno firme distinte. Le altre implementazioni di gestureRecognizerShouldBegin nel progetto sono in coordinatori NSObject, non in sottoclassi UIView.

La logica dei gesti non cambia. Nessuna modifica a formato, archivio o percorsi dei quaderni, nessun reset dei dati.

Controlli locali ripetuti: grafo con 406 oggetti, 257 sorgenti Swift e 313 metodi XCTest presenti; grammatica Swift e parsing del compilatore in modalità 5. Non equivalgono a compilazione UIKit: i controlli precedenti non avevano rilevato l’override mancante. **Compilazione Apple della 0.15.2 non eseguita**, nessuna dichiarazione di funzionamento verificato sull’iPad. Il fallimento della 0.15.1 resta registrato. L’ultimo blocco della CI Apple è documentato nel [registro delle verifiche](ROADMAP_VALIDATION.md).

Core e backend sono invariati, perciò le suite non sono state rieseguite per questa sola dichiarazione. Ultime prove effettive del Core: 182 XCTest (180 passati, due esclusioni Darwin) e 98 FSRS; backend: 23 test a fixture nella lavorazione precedente.

Pacchetti: NeuralNotes-iPad-0.15.2.zip e NeuralNotes-Sorgenti-0.15.2.zip, versione 0.15.2/build 29, generati dai sorgenti canonici con controllo integrità ZIP e corrispondenza byte per byte. Aprire il pacchetto NeuralNotes.swiftpm intero. Conservare vecchio progetto e dati: non occorre cancellare l’app o i quaderni. [Funzioni e recupero della 0.15](DELIVERY_0_15_0.md).
