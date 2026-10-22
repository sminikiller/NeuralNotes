# NeuralNotes 0.20.4 / build 40 — seleziona, leggi, decidi

23 ottobre 2026. La Lente rimaneva attiva dopo il gesto e intercettava anche spostamenti successivi. Inoltre un tocco o una sottolineatura breve potevano avviare la spiegazione e inserirla direttamente come nota. Il flusso ora richiede una decisione esplicita prima della richiesta AI e una seconda decisione prima dell'inserimento sul foglio.

## Flusso applicato

1. **Attiva la Lente** dalla toolbar. Tocco su parola, passata sulle parole, lazo, area o foto creano una selezione evidenziata.
2. **Il gesto finisce e la Lente si disattiva.** Torna lo strumento precedente, con la sua palette. Lo scorrimento con il dito usa di nuovo il comportamento di quello strumento; non parte una nuova selezione della Lente.
3. **Scegli dalla barra sulla selezione:** Spiega apre una risposta in anteprima; Chiedi apre la conversazione; Cerca e Copia lavorano sul testo già letto; X elimina la selezione. Per una zona o foto non ancora letta, Cerca/Copia sono disabilitati e restano Spiega/Chiedi.
4. **Leggi e decidi:** Inserisci come nota è l'unico comando che aggiunge quella risposta al foglio; Copia porta via il testo; Scarta elimina soltanto la risposta non inserita dall'anteprima. È possibile continuare con altre domande senza creare note.
5. **Nuova selezione** nella barra o nel pannello riattiva la Lente. È disponibile anche il normale pulsante della toolbar. L'uso resta temporaneo, senza aggiungere impostazioni o una seconda modalità persistente da ricordare.

Il risultato dello spostamento dipende dallo strumento ripristinato: tornando alla penna si può scrivere con Pencil e scorrere secondo le preferenze del quaderno; tornando a Oggetti si possono muovere gli oggetti. La Lente non si riattiva per questi gesti. Un gesto che non individua alcun contenuto può lasciare la selezione attiva per riprovare.

La vecchia preferenza `lens.autoAnnotate`, anche se salvata a `true`, non avvia più richieste né aggiunge note. Rimossi il relativo pulsante e i vecchi percorsi automatici, compreso il pannello della chat sulla pagina e il testo del PDF affiancato. Aprire o evidenziare una selezione prepara eventualmente testo/OCR locali; non invia da solo una richiesta al provider. Consenso e connessione restano necessari per Spiega/Chiedi.

## Anteprime e protezioni

- La selezione resta evidenziata e la barra segue zoom/scorrimento anche dopo l'uscita dalla Lente.
- La risposta reca la dicitura **Anteprima · non aggiunta al foglio**. Inserire due volte la stessa risposta non crea duplicati; dopo Annulla si può inserirla nuovamente.
- Scartare una risposta già inserita non elimina la nota. Per rimuovere una nota salvata restano i comandi dell'elenco note e Annulla.
- Una risposta riferita a un'altra pagina chiede di tornare alla pagina d'origine prima dell'inserimento, evitando una nota appoggiata per sbaglio a un altro testo.
- Una sessione sostituita o una pagina cambiata durante la preparazione non avviano una nuova richiesta con il contesto sbagliato.

## Icone più piccole

L'icona ridotta della nota passa da **30 a 24 punti**; il cerchietto di chiusura da **24 a 20**. La lampadina interna passa da 17 a 14. L'area geometrica di tocco resta almeno 44 punti schermo alle scale supportate, separata dalla parte disegnata; ai margini della vista può essere ritagliata dal contenitore. Corpo, font e dati delle note esistenti non vengono riscritti.

## Verifiche e limiti

- Suite Core Swift 6.1.2 Linux: **260 XCTest, 258 passati, due skip Darwin preesistenti, zero fallimenti; 98 FSRS passati**. Nuova prova delle icone compatte e delle aree di tocco a diversi zoom, con aggiornamento delle aspettative geometriche precedenti.
- Due nuove prove native predisposte: tocco/area ripristinano lo strumento senza sessione AI o note automatiche, anche con la vecchia preferenza attiva; anteprima/scarto, inserimento esplicito, protezione dai duplicati, undo e pagina errata. **Non eseguite con Apple.** Allineata anche un'aspettativa preesistente al titolo attuale del menu testuale.
- Progetto: 468 oggetti, 300 sorgenti Swift e 405 metodi XCTest individuati; grammatica, controlli AST e parsing Swift 5. Non sono type checking SDK né prove di gesti fisici.
- Backend invariato e non rieseguito per questo lotto: restano i 48 test della 0.20.2 e l'integrazione locale con provider simulato. Nessuna nuova chiamata AI live o attivazione di servizi.

La compilazione SDK Apple e la prova sul dispositivo non sono disponibili nella sessione; la CI è ancora bloccata dalla fatturazione documentata nelle [verifiche](ROADMAP_VALIDATION.md). Restano quindi da confermare in Playgrounds le animazioni, l'interazione fra Pencil e dita e le dimensioni percepite sul dispositivo. Non viene dichiarato che tutte le funzionalità dell'intera roadmap siano state provate.

## Pacchetto

`NeuralNotes-iPad-0.20.4.zip` include questo flusso e la [correzione UIKit della 0.20.3](FIXES_0_20_3.md). Aprire in una cartella nuova e conservare il vecchio Playground e i quaderni. Nessuna migrazione distruttiva, reset dei dati o modifica del formato nativo richiesti.
