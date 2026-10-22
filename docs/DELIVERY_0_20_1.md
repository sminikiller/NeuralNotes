# NeuralNotes 0.20.1 / build 37: Lente AI più comoda e note collegate al testo

22 ottobre 2026. Ramo `claude/ai-attivazione`, dopo la 0.20.0 ([consegna 0.20.0](DELIVERY_0_20_0.md)).

Nasce dalle prove sull'iPad della 0.20.0. Lettura e OCR funzionavano, ma i riquadri della Lente erano messi male:

- la scheda copriva gli appunti a metà pagina;
- a volte era tagliata in alto, sotto la barra, o fuori dallo schermo;
- con le foto compariva in cima, poco visibile;
- la barra della Lente stava in basso, in mezzo al documento;
- la nota inserita era un grande riquadro giallo sopra il PDF.

## Dove compare la Lente

- **Pannello a destra.** La conversazione su una selezione si apre in un pannello affiancato alla pagina, che si stringe: niente resta coperto. Il pannello ha tre schede:
  - **Selezione:** la conversazione sull'ultima cosa sottolineata, cerchiata o fotografata;
  - **Note:** l'elenco delle note della Lente;
  - **Pagina:** la chat su tutta la pagina.
- **Larghezza.** Il bordo del pannello si trascina per allargarlo o stringerlo.
- **Finestra mobile.** Il pulsante con i due rettangoli sposta la conversazione in una finestra sopra la pagina.
  - Si trascina dalla barra in alto.
  - Non esce mai dallo schermo e lascia libera la barra degli strumenti.
  - La prima volta si apre dal lato opposto alla selezione.
  - L'icona con la barra laterale la riaggancia a destra.
- **Con il PDF affiancato aperto,** la conversazione compare sotto il PDF, così il PDF resta visibile.

## Barra della Lente

- **Posizione.** È una sola riga compatta subito sotto la barra degli strumenti, non più in mezzo alla pagina. Con la barra sul lato sinistro o destro si apre dal pulsante ✨.
- **Comandi:**
  - modo Testo o Immagine;
  - nota automatica;
  - fotocamera: scatta, ritaglia e chiedi, oppure scegli da Foto;
  - **Note**, con il numero di note della pagina;
  - chat della pagina;
  - guida (?);
  - connessione AI (triangolo arancione se manca);
  - esci.
- **Guida breve.** Compare finché non premi «Ho capito» e torna con «?».
- **Pressione lunga su «Lente AI»** nella barra in alto: note della Lente, ultima conversazione, chat sulla pagina. Il tocco semplice attiva o disattiva lo strumento, come ⌘K.

## Conversazione

- **Selezione.** Il testo letto resta modificabile. Con le foto c'è anche l'anteprima e «Inserisci la foto nella pagina».
- **Domande pronte:** Spiega, Chi è / Cos'è (solo per termini brevi), Riassumi, Semplifica, Esempio, Approfondisci, Domande di ripasso, Traduci, e Descrivi per le immagini.
- **Domande successive.** Il campo in basso resta sempre visibile. Le ultime due risposte vengono inviate come contesto, quindi «e in parole più semplici?» funziona.
- **Risposte una sotto l'altra.** Ognuna ha:
  - «Inserisci come nota», che diventa «Vai alla nota» dopo l'inserimento;
  - Copia.

## Foto e chiedi

1. Scatta la foto, oppure sceglila da Foto.
2. Si apre «Cosa vuoi chiedere?»: trascina un rettangolo sulla parte che ti serve (una formula, un grafico, un paragrafo). «Tutto» usa la foto intera.
3. All'AI vanno solo la parte ritagliata e il testo letto con l'OCR.
4. Se vuoi, inserisci la foto nella pagina con lo stesso ritaglio.

## Note della Lente

Restano caselle di testo normali: si spostano, si ridimensionano, si esportano e si annullano. In più:

- **Collegate al testo.** Ogni nota ricorda la pagina e la zona che spiega.
  - Con la Lente attiva, o con la nota selezionata, la zona è evidenziata e una linea tratteggiata la unisce alla nota.
  - «Mostra il testo di origine» porta lì.
- **Spostamento.** Con la Lente attiva basta trascinare la nota o la sua icona; con lo strumento Oggetti funziona come sempre.
- **Riduzione a 💡.**
  - Il cerchietto con la freccia, in alto a destra della nota, la riduce a una piccola icona 💡 nel punto in cui si trova.
  - Un tocco sull'icona la riapre e la riporta dentro la pagina.
  - Funziona con il dito con qualunque strumento e con Pencil quando è attiva la Lente. Con lo strumento Oggetti il tocco seleziona l'icona; per aprirla usa «Apri nota» nel menu.
- **Note lunghe o senza spazio.** Se la risposta è lunga, o accanto al testo non c'è posto, la nota viene inserita già ridotta a 💡 accanto al testo invece di coprire la pagina.
- **Modifica.** Un tocco su una nota con la Lente attiva apre l'editor. Lo stesso editor si raggiunge dall'elenco o dal menu della nota con lo strumento Oggetti. Permette di:
  - cambiare titolo e testo;
  - scegliere il colore (giallo, azzurro, verde, rosa);
  - ridurre la nota o aprirla;
  - mostrare il testo di origine;
  - chiedere ancora alla Lente;
  - eliminare la nota.

  La riga «conoscenza generale, non dalle tue fonti» resta.
- **Elenco delle note** (scheda Note):
  - tutte le note del quaderno, pagina per pagina;
  - ricerca e filtro «Questa pagina»;
  - un tocco porta alla pagina, centra la nota e la evidenzia per un attimo;
  - scorrendo: elimina e riduci/apri; con la pressione lunga: modifica e testo di origine;
  - «Apri tutte» e «Riduci a 💡» per la pagina aperta.
- **Testo letto dalla Lente.** Le note della Lente non vengono più rilette come parte della selezione: sono risposte, non materiale tuo.
- **Copie.** Nei quaderni copiati il collegamento punta alle pagine della copia.

## Formato del quaderno

- **Nuovo campo.** Le caselle di testo hanno il campo facoltativo `lensNote`: titolo, riga di origine, zona collegata, stato ridotto e data.
- **Compatibilità.** I quaderni precedenti si aprono senza migrazioni e le note già inserite restano caselle normali.
- **Versioni vecchie.** Una versione precedente dell'app ignora il campo e mostra le note aperte. Se salva la pagina, il collegamento e lo stato ridotto di quelle note si perdono.

## Verifiche eseguite

| Prova | Esito |
|---|---|
| Swift Core Linux 6.1.2 (Docker) | 248 XCTest: 246 passati, 2 skip Darwin preesistenti, 0 errori; 98 FSRS passati |
| Nuovi test Core (7) | Lettura dei quaderni vecchi e andata e ritorno del campo, elenco per pagina e testo modificabile, controlli dentro la pagina e linea solo se separati, posto per l'icona, posizione libera o coperta, validazione, copia del quaderno |
| Sintassi | Grammatica di 295 file Swift (tree-sitter); `swiftc -parse` Swift 5 di 294 sorgenti di app e test |
| Scritti ma non eseguiti | Test d'integrazione dell'app sulle note (inserimento collegato, riduzione a icona, modifica, inserimento ridotto delle risposte lunghe, annulla) e test UI (barra sotto gli strumenti, elenco note nel pannello) |
| Non eseguito | Compilazione con l'SDK Apple, test sul simulatore, prova sull'iPad, chiamate AI reali |

## Pacchetto

Il pacchetto è `.verification/NeuralNotes-iPad-0.20.1.zip`, nella cartella `AppAppunti-claude`. Aprilo in File, decomprimilo in una cartella nuova e apri `NeuralNotes.swiftpm` con Swift Playgrounds.

Conserva il Playground precedente.
