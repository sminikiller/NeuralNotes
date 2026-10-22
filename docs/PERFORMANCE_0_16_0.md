# Apertura dei quaderni — 0.16.0 / build 30

22 ottobre 2026. Analisi della segnalazione di 6–12 pagine che richiedono fino a 30 secondi. Il ritardo reale sull’iPad non è stato riprodotto o cronometrato dalla sessione: nessuna garanzia di apertura entro un secondo deriva dai test Linux.

## Cosa veniva caricato

1. EditorViewModel.open leggeva il catalogo e tutti i JSON delle pagine. lastEditedPage li rileggeva tutti per trovare la più recente; load li rileggeva una terza volta. Anche cambiare pagina ripeteva la scansione completa.
2. I JSON contengono testi/RTF, coordinate degli oggetti, riferimenti ai media e altri metadati. Non sono solo numeri di pagina. I byte di foto, PDF e tratti delle altre pagine non vengono tutti caricati da pages(). Il disegno PencilKit della pagina attiva viene letto e decodificato per scrivere.
3. Lo scorrimento verticale preparava fino a sei pagine vicine, una alla volta, con anteprime a 1200 pixel. Una copertina impostata sull’ultima pagina modificata avviava un altro passaggio sui JSON e il rendering di quella pagina.
4. Ogni flush, anche senza modifiche e durante la chiusura, lanciava subito indicizzazione e possibile backup completo. Il backup calcola CRC e legge i media, usando lo stesso attore seriale delle pagine. Aprire di nuovo o caricare una pagina poteva aspettare quel lavoro. È un meccanismo concreto di blocco trovato nel codice; non dimostra da solo che tutti i 30 secondi segnalati avessero questa causa.
5. Il caricamento audio apriva AVAudioPlayer per ogni parte delle registrazioni non terminate, anche normalmente in pausa con durate già salvate. Il lavoro di preparazione del player avveniva sul MainActor.

## Correzioni

- Un solo passaggio iniziale sui JSON delle pagine. La scelta dell’ultima modifica usa i dati già letti. Il caricamento e il cambio della pagina richiedono il solo JSON di destinazione, con controllo di appartenenza al manifest e recupero del disegno precedente invariati. Da circa 3N letture di intestazioni a N+1 per l’apertura; da N a una per il caricamento successivo.
- Copertina ultima pagina: eliminato il secondo passaggio ridondante sui JSON.
- Flush senza modifiche: non avvia più manutenzione. Dopo l’apertura o un salvataggio reale, indicizzazione e backup attendono almeno otto secondi di inattività. Scrittura, scelta dello strumento, modifica testo, movimento oggetti, flush e chiusura cancellano il lavoro automatico; la generazione del task impedisce che un vecchio task cancellato rimuova quello nuovo.
- La scansione di indicizzazione controlla l’annullamento fra i file. Il backup aveva già controlli a blocchi: l’interruzione lascia le vecchie copie intatte e rimuove il temporaneo. I backup manuali restano operazioni esplicite complete; il limite di spazio e le due copie protette non cambiano. Sessioni molto brevi o senza pause possono non produrre subito un nuovo backup automatico: il documento originale continua a essere salvato normalmente.
- Audio: riuso del catalogo già caricato. Le sessioni normalmente in pausa con durate note non riaprono i media. Per registrazioni interrotte o parti con durata sconosciuta, lettura della durata tramite AVAudioFile in un task esterno al MainActor, senza costruire un player. Nessuna registrazione viene ripresa automaticamente.
- Anteprime verticali limitate a tre pagine vicine a 800 pixel, una alla volta; resta il budget di cache di 48 MiB e la protezione dell’input sulla pagina corretta. La barra dei numeri usa LazyHStack.
- **Azioni → Documento → Spazio e recupero → Tempi dell’ultima apertura** mostra catalogo, metadati, pagina/inchiostro, foglio pronto e recupero audio. “Foglio pronto” misura il modello caricato: non il primo frame di UIKit, il rendering PDF/foto, la presentazione della finestra o un download iCloud precedente alla lettura.

## Prove effettive

Swift 6.1.2 Linux, build di test, log `.verification/core-work-0.16.log`: **184 XCTest Core eseguiti, 182 passati, due esclusioni Darwin preesistenti, zero errori; 98 FSRS passati**.

Nuova prova di IO con 20 oggetti testo e quattro riferimenti immagine per pagina, un file audio sparso di 300 MiB e un payload disegno fittizio di tre byte. Le immagini e il disegno non vengono decodificati da UIKit/PencilKit. Risultati dell’ultima esecuzione:

| Pagine | Lettura di tutti i JSON | JSON e payload della pagina scelta |
| --- | ---: | ---: |
| 6 | 3,90 ms | 1,01 ms |
| 12 | 6,31 ms | 0,76 ms |
| 300 | 158,16 ms | 1,14 ms |

La prova rende illeggibile una pagina fuori schermo prima di leggere quella scelta: la lettura di destinazione riesce senza aprirla. Questo verifica l’accesso isolato, non la validità completa di un quaderno o i tempi di apertura reali dell’app. Un’altra prova interrompe un backup con un media da 16 MiB e verifica temporaneo rimosso e due copie precedenti conservate.

Due nuovi test Apple predisposti, **non eseguiti**: selezione indipendente da un’intestazione non attiva danneggiata; manutenzione differita, assente dal flush pulito/chiusura e ancora eseguita dopo un salvataggio reale seguito da inattività.

Grafo di progetto: 408 oggetti, 258 Swift, 317 metodi XCTest presenti. Grammatica e parsing del compilatore Swift in modalità 5 ricontrollati. Non sostituiscono compilazione con SDK Apple o prova fisica. Il blocco CI documentato nelle lavorazioni precedenti non è stato aggirato; nessuna nuova esecuzione Apple riuscita è dichiarata. Backend invariato, nessuna nuova prova di API o trascrizione live.

## Limiti rimasti

L’apertura iniziale legge ancora tutti i JSON e ne conserva gli oggetti/testi: il costo dei metadati cresce con N. Non è un indice persistente con paginazione completa su richiesta. Il lavoro sui tratti e sulle immagini è invece limitato alla pagina attiva e alle anteprime vicine. Un singolo foglio con moltissimi tratti, immagini grandi, un PDF costoso da disegnare o File/iCloud non ancora locale può restare lento. La decodifica PencilKit attiva e parte del rendering restano sul thread UI. I tempi aggiunti separano le fasi di lettura, ma non misurano ancora il primo frame disegnato. Un obiettivo di un secondo va verificato sull’iPad su documenti reali e con una build Apple.

Pacchetti 0.16.0/build 30: NeuralNotes-iPad-0.16.0.zip e NeuralNotes-Sorgenti-0.16.0.zip. Nessuna modifica al formato nativo o migrazione distruttiva dei dati. Restano le [correzioni del righello](FIXES_0_15_2.md) e le [funzioni/limiti del recupero](DELIVERY_0_15_0.md).
