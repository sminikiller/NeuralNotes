# Gate Fase 1 — da completare su Mac e iPad

> **Aggiornamento:** l’utente ha confermato tutti i controlli manuali richiesti della Fase 1 («tutto perfetto») e ha autorizzato il proseguimento. La checklist seguente è il piano originale, non prova di esecuzione XCTest/Xcode. Per la 0.2 usare [TESTING_0_2.md](TESTING_0_2.md). Le voci Mac rimangono non eseguite.

Stato: **non verificato su piattaforma Apple**. Non spuntare i criteri sulla base dei soli controlli Python o della lettura del codice.

## Percorso disponibile con il solo iPad

Il dispositivo dell’utente è iPad di decima generazione con iPadOS 18.7.8. È stato aggiunto l’App Playground `NeuralNotes.swiftpm`, con gli stessi sorgenti e storage del progetto Xcode. Seguire [IPAD.md](IPAD.md): compilare ed eseguire in Swift Playground, creare/rinominare e riavviare lo stesso progetto. La compilazione e questo ciclo sul dispositivo sono ancora da verificare.

Il percorso iPad permette una prima verifica manuale reale. **Non sostituisce** l’esecuzione dei test automatici, la build Release e le verifiche di distribuzione elencate sotto. Registrare separatamente le evidenze: non dichiarare automaticamente completato tutto il gate dopo una sola esecuzione in Playground.

## Build e test sul Mac

- [ ] Annotare versione macOS, `xcodebuild -version`, `xcrun swift --version`, SDK e runtime simulatore.
- [ ] Aprire `NeuralNotes.xcodeproj`, risolvere il solo package locale, verificare target iPadOS 17.
- [ ] Eseguire `bash tools/verify_macos.sh` e conservare output e `.xcresult`.
- [ ] Nessun errore di build Debug/Release; analizzare i warning Swift concurrency, macro e availability.
- [ ] Tutti i test core, repository e UI verdi. Il test UI deve terminare e rilanciare il processo, senza resettare lo storage al secondo avvio.

## Percorso principale su iPad fisico

1. Avviare l’app: libreria vuota visibile, nessun contenuto di esempio.
2. Premere **+**, scrivere “Fisica”, scegliere copertina Laguna, salvare.
3. Aprire Fisica: scheda riepilogativa, stato “Quaderno salvato sul dispositivo”, formato v1, zero pagine.
4. Premere **Modifica**, rinominare “Fisica II”, scegliere Lavanda, salvare.
5. Tornare alla libreria, terminare l’app dal selettore app; riavviarla dall’icona.
6. Ritrovare “Fisica II”, copertina Lavanda, aprirlo nuovamente senza errori.

- [ ] Tutti i sei passaggi riusciti sullo stesso container, senza reinstallare l’app.

## Azioni e persistenza

- [ ] Creare cartella “Università”; dal suo menu contestuale creare sottocartella “Primo anno”.
- [ ] Modificare il quaderno e assegnarlo alla sottocartella; verificare il filtro sidebar.
- [ ] Aggiungere ai preferiti, verificare filtro Preferiti e successivo riavvio.
- [ ] Duplicare il quaderno vuoto: originale intatto, copia apribile e identità distinte (test integrazione).
- [ ] Eliminare copia dopo conferma e annullare l’eliminazione; riaprire la copia ripristinata.
- [ ] Provare a eliminare una cartella non vuota: errore esplicito, dati intatti.
- [ ] Rinomina cartella persistente dopo riavvio.
- [ ] Ricerca per titolo, caratteri Unicode, nessun risultato; ordinamento e toggle elenco/griglia.
- [ ] Layout e ordinamento preferiti conservati al riavvio.
- [ ] Nessun nome vuoto, multilinea o oltre 120 caratteri; errore non perde modifiche già salvate.

## UI e affidabilità

- [ ] Portrait e landscape: toolbar, form, sidebar e navigazione accessibili.
- [ ] Split View/finestra stretta: passaggio sidebar/libreria e back funzionanti.
- [ ] Aspetto chiaro/scuro e Dynamic Type fino alle dimensioni di accessibilità: niente testo essenziale tagliato o azioni irraggiungibili.
- [ ] VoiceOver: titolo quaderno, preferiti, apertura e azioni personalizzate comprensibili.
- [ ] Controlli con tastiera hardware e ⌘N.
- [ ] Test integrità e IO negativi verdi; record conservato se il manifest non è disponibile.
- [ ] In un container di test con pacchetto orfano, avviso all’avvio e file preservati. Non manipolare il container di uso normale per questa prova.

## Verbale

```text
Data:
Mac / macOS:
Xcode / Swift / SDK:
Simulatore / runtime:
iPad / versione iPadOS:
Risultati build e test / percorso xcresult:
Risultato ciclo di vita fisico:
Problemi e correzioni:
Gate Fase 1: PASS / FAIL / INCOMPLETO
```

Avviare la Fase 2 solo con gate PASS. Allo stato attuale il gate è **INCOMPLETO**.
