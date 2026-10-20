# Correzioni 0.2.1 — penna e percorsi

## Evidenza ricevuta

L’utente riferisce che, in dark mode, la penna nera scrive bianco e la bianca scrive nero. Lo screenshot dei controlli 0.2 mostra:

- PencilKit salvataggio/riapertura: `invalidPath`.
- Copia pagina: `missingItem`, dipendente dal mancato salvataggio precedente.
- Protezione percorsi: PASS, ma la vecchia prova controllava solo il rifiuto di un percorso vietato.
- PDF e modello audio: `invalidPath`.
- OCR, riferimenti della sintesi locale e persistenza SwiftData/cestino: PASS sul dispositivo.

La 0.2 è quindi stata eseguita sul dispositivo, con errori reali. Questi esiti non sono una certificazione delle altre funzionalità né un risultato XCTest locale.

## Inchiostro

La superficie di carta era bianca mentre PKCanvasView ereditava l’aspetto scuro. La 0.2.1 imposta `.light` esclusivamente sul canvas e sulla superficie, mantenendo il chrome dell’app adattivo. Il colore selezionato viene risolto in un colore UIKit fisso per la carta. La stessa trait collection chiara è applicata quando PencilKit produce immagini per OCR ed export PDF, per evitare risultati differenti tra canvas ed esportazione.

I disegni esistenti non vengono riscritti o convertiti. Il bianco rimane bianco: su carta bianca sarà intenzionalmente poco visibile. Per controllarlo usare una zona colorata o un’immagine importata.

## Percorsi

Il vecchio resolver confrontava `result.path` con `root.path + "/"`, dopo aver normalizzato separatamente l’intera destinazione e la directory. Due problemi: slash finali dei directory URL e normalizzazione Darwin degli alias `/private/var` per percorsi esistenti rispetto a file ancora da creare.

Il nuovo resolver normalizza una sola volta il pacchetto esistente, poi costruisce la destinazione tramite singoli componenti relativi. Rifiuta componenti vuoti, `.`, `..`, NUL, backslash, due punti e link simbolici sotto il pacchetto, inclusi link pendenti. Non confronta prefissi testuali e non risolve nuovamente la destinazione inesistente. La protezione dei documenti rimane attiva.

Fonti Apple: [risoluzione symlink e `/private`](https://developer.apple.com/documentation/foundation/nsurl/resolvingsymlinksinpath), [override dell’aspetto per una view](https://developer.apple.com/documentation/uikit/uiview/overrideuserinterfacestyle).

## Regressioni aggiunte

- Creazione/lettura di file nuovi con root URL sia directory sia non-directory.
- Alias Darwin `/var`/`/private/var`, quando presente sul sistema di test.
- Symlink esterni e pendenti rifiutati; traversal e componenti invalidi rifiutati.
- Colori nero/bianco e trait del canvas in contenitori chiari/scuri.
- Il controllo incorporato dei percorsi ora scrive e rilegge anche percorsi validi, oltre a rifiutare quelli vietati.
- Errori dei controlli leggibili e dipendenza della duplicazione esplicitata.

## Stato e nuova verifica

Controlli locali: grafo Xcode 108 oggetti, risorse/plist, sintassi di 40 file Swift e packaging. 29 XCTest forniti, non eseguiti qui; manca un compilatore/SDK Apple. Nove controlli incorporati da rieseguire su iPad, non dichiarati già superati.

1. Conservare il progetto precedente e aprire **NeuralNotes-iPad-0.2.1.zip** in Swift Playground.
2. Eseguire **Verifica sul dispositivo** e controllare tutti i nove risultati.
3. In dark mode scrivere con nero, rosso e bianco; ripetere in modalità chiara. Il colore fisico deve restare quello selezionato.
4. Salvare, cambiare pagina, chiudere/riaprire e verificare tratti e colori.
5. Riprovare PDF e audio; gli errori di percorso non devono ricomparire. Verificare anche OCR/export dei tratti neri in dark mode.

Il formato dei documenti non cambia e non è richiesta migrazione. Un nuovo App Playground può comunque usare uno spazio dati diverso: conservare la vecchia versione finché la nuova è verificata.
