# NeuralNotes 0.28.1 — correzioni dell’editor

Stato: **beta 1.0.0 (165) firmata e caricata su Apple il 2 novembre 2026**, [invio 41468355039](https://github.com/sminikiller/NeuralNotes/actions/runs/41468355039). `ARCHIVE SUCCEEDED`, `EXPORT SUCCEEDED` e `Upload succeeded` confermati. Elaborazione e disponibilità nell’app TestFlight non ancora verificate. Sorgenti applicativi: `2aa67595d15edc61b761faf85bfe58fc6d9e694c`.

## Correzioni

1. **Pagina nuova:** la sostituzione della sessione nativa invalida prima il vecchio contenuto. Il canvas rimane visibile e riceve normalmente i tocchi. Quando l’inchiostro è vuoto, una copertura del solo viewport mostra la pagina attuale sopra le vecchie tile, lasciando passare i tocchi; viene rimossa al primo nuovo tratto. La rasterizzazione resta limitata all’area visibile anche con PDF ingranditi. I livelli del foglio e le anteprime continuano a essere separati per pagina.
2. **Lazo:** la scelta predefinita seleziona insieme inchiostro e oggetti dell’app. Archi e poligoni vengono controllati sul loro contorno, con intersezione del lazo; il centro del riquadro non è più l’unico criterio. Gli oggetti bloccati restano protetti. La selezione del solo inchiostro PencilKit rimane un’opzione esplicita.
3. **Stile oggetti:** il primo comando della barra di selezione apre il pannello completo per contorno, colore, spessore, tratto, riempimento, opacità e parametri. Toolbar, menu contestuale e Solo foglio condividono il comando. La finestra conserva pagina e selezione di origine, senza reinizializzare le modifiche del pannello. Un’applicazione costituisce un passo di annulla.
4. **Guide:** righello più largo, trascinamento con un dito, rotazione con due dita e pizzico per ridimensionare; con scrittura a dito attiva, lo spostamento usa due dita. Suggerimento esterno. Aggiunte le squadre 45° e 30°/60° con aggancio a ciascuno dei tre lati; il lato scelto resta lo stesso fino al rilascio.
5. **Riconoscimento:** secondo adattamento degli angoli per figure chiuse irregolari, margine per angoli retti disegnati a mano e rimozione del vertice artificiale quando il tratto inizia lungo un lato. L’anteprima usa la figura riconosciuta che sarà salvata.
6. **Tutti gli strumenti:** elenco organizzato per attività. Ogni riga offre sia pressione prolungata sia pulsante delle opzioni, anche per strumenti non nei preferiti. Aprire le opzioni non spegne una guida già attiva. Le modifiche alle guide aggiornano immediatamente la visualizzazione.
7. **Evidenziatore:** Parole e Tratto libero usano il medesimo colore al 25%. Tutte le larghezze libere hanno anteprima personalizzata, senza il livello nativo che poteva mascherarla. Il PDF viene composto con il colore nello stesso contesto e la scrittura resta sopra. L’anteprima ritaglia solo l’impronta del gesto, conserva una base per tratto e non ricostruisce il PDF a ogni campione. Le parole già evidenziate non scuriscono durante la ripetizione. Anche l’anteprima live rispetta gli oggetti portati davanti e i nastri, come l’inchiostro salvato.
8. **Workflow:** separati stile delle forme selezionate e stile per le nuove forme; un solo pannello condiviso per ciascuna funzione. I menu di inserimento restano scorciatoie degli stessi comandi, senza implementazioni alternative.

## Verifiche concluse

- Suite completa sui sorgenti `08dd38a`: [41350441754](https://github.com/sminikiller/NeuralNotes/actions/runs/41350441754), Core 373 XCTest e 98 Swift Testing, 599 test nativi (2 saltati, nessun fallimento) e **44 test UI superati**. Il job ha raggiunto il limite di 60 minuti durante la successiva compilazione Release, dopo `TEST SUCCEEDED`: non è un fallimento dei test. Il limite del solo job Apple è stato portato a 75 minuti per lasciare tempo alla compilazione finale e alla conservazione delle prove.
- Unico cambiamento applicativo successivo: l’anteprima live dell’evidenziatore sta sotto gli oggetti portati davanti e ai nastri. Test finale sui sorgenti `2aa6759`: [41355924843](https://github.com/sminikiller/NeuralNotes/actions/runs/41355924843), **211 test nativi superati**, incluso il confronto dei pixel dell’oggetto prima e durante il tratto, Core superato, prova UI dell’evidenziatore superata, compilazioni Debug e Release riuscite. XCTest non riusciva a terminare l’app precedente prima di avviare la seconda prova UI, Solo foglio.
- Quella sola prova è stata ripetuta sugli stessi sorgenti su un simulatore nuovo: [41466087966](https://github.com/sminikiller/NeuralNotes/actions/runs/41466087966), **superata**, con i controlli su opzioni degli strumenti, trasferimento della selezione e dimensioni del canvas invariati. Nessun’altra modifica al codice per il tentativo.
- Aggiornamento della vecchia app: catalogo e manifest del quaderno di controllo conservati con hash identici prima/dopo. Backend e controlli portabili superati nella suite completa. Nessun cambiamento successivo al codice di archiviazione o dei servizi.
- Il pacchetto Playgrounds esatto dell’ultima revisione è stato compilato in Release per dispositivo e simulatore, avviato e osservato per 60 controlli. CRC e confronto dei **323 file** con sorgenti e risorse del commit `2aa67595d15edc61b761faf85bfe58fc6d9e694c` superati. SHA256 dello ZIP: `11da3eff072102bfbad11d8b980ecd1471b740576c880e69cecea62abe42c94c`.
- Ispezionate le prove visive di stile/selezione, evidenziatore, cronologia rapida, Solo foglio, goniometro, squadre, gomma e trasferimento tra pagine. La prova Solo foglio dell’ultima revisione è disponibile anche nel risultato del tentativo isolato.

Queste sono prove automatiche e visive sul simulatore; non misurano la latenza percepita di Apple Pencil su un iPad fisico. Identità dell’app, firma, segreti e corsia TestFlight rimangono quelli esistenti. Nessuna espansione di backend o iCloud.

## Uso dei comandi aggiornati

- **Lazo:** tocca il lazo, circonda tratti e oggetti, poi trascina la selezione. Tocca una forma anche nel suo interno per selezionarla; per un arco tocca il contorno. Nelle opzioni resta disponibile la selezione del solo inchiostro.
- **Stile:** dopo aver selezionato una forma, usa il primo pulsante della barra di selezione. Cambia colore, spessore, tratto, riempimento e parametri, poi scegli Applica. Annulla ripristina l'intera modifica in un passo. Lo stile delle nuove forme ha un comando distinto e un'etichetta esplicita.
- **Guide:** apri il pulsante + della toolbar, quindi Guide da disegno. Righello, goniometro e squadre si usano senza aggiungerli ai preferiti. Tieni premuta la riga, oppure tocca il pulsante delle opzioni. Sposta la guida con il dito e usa due dita per ruotare o pizzicare. Durante il tratto la penna resta agganciata al bordo iniziale.
- **Riconoscimento:** nelle opzioni della penna scegli Tieni ferma la punta o Automatico al rilascio e attiva le figure desiderate. Una figura irregolare può restare inchiostro: la modalità automatica mantiene una soglia più severa per proteggere la scrittura.
- **Evidenziatore:** nelle opzioni scegli Parole per selezionare il testo riconosciuto come con la Lente, oppure Tratto libero per disegnare liberamente. La larghezza reale è regolabile da 1 a 80 pt. La prima lettura delle parole di scansioni e grafia può richiedere preparazione.

Il simulatore verifica i gesti e il rendering previsti dalle prove automatiche; non sostituisce una prova della sensazione di trascinamento e della latenza con Apple Pencil sul dispositivo fisico.

## Consegna

ZIP verificato: `NeuralNotes-iPad-0.28.1.zip`, identico al pacchetto compilato e avviato dalla CI; il numero mostrato da Playgrounds è 0.28.1. La beta TestFlight usa il numero di distribuzione **1.0.0 (165)**. Versione e build della copia installata si leggono in Libreria → Informazioni su NeuralNotes.

L’archivio è firmato con l’identità esistente, Bundle ID `com.lorenzominichilli.neuralnotes`, iPadOS minimo 17.0 e iCloud disattivato per questa beta. Il rapporto dell’archivio è precedente all’invio: il suo campo `uploaded: false` non rappresenta l’esito successivo. La conferma del caricamento viene dal log della distribuzione alle 15:25:37 UTC.
