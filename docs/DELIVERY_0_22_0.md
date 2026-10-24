# NeuralNotes 0.22.0 / build 49 — consegna iPad

## Interfaccia

La fascia numerata e la riga permanente dei messaggi sono sostituite da un'unica barra inferiore con controlli alti 48 punti, oltre all'area sicura del gesto Home. I controlli di navigazione mantengono un'area di tocco di almeno 44 punti, definita anche per le parti trasparenti attorno alle icone.

- Trascinare la barra mostra un numero ingrandito sopra il cursore. La pagina viene aperta soltanto al rilascio: i numeri intermedi non avviano caricamenti di PDF, immagini o inchiostro.
- Toccare il contatore apre «Vai alla pagina». Il numero viene validato; un valore fuori intervallo non apre un altro foglio.
- Frecce precedente/successiva alle estremità del documento disabilitate; nelle finestre strette vengono nascoste per lasciare spazio al cursore e al contatore.
- Aggiunta pagina con «+»; menu «Azioni pagina» per panoramica, duplicazione, inserimento, riordino ed eliminazione. La griglia completa, i segnalibri e il cestino delle pagine restano accessibili.
- Stato e salvataggio raccolti in un'icona: il popover mostra il messaggio completo e «Salva adesso». Il salvataggio automatico non produce notifiche ripetute.
- Le conferme delle azioni esplicite compaiono al centro in basso per tre secondi. Non intercettano i tocchi sul foglio; un salvataggio intermedio non ne interrompe il timer.
- I quaderni aperti sono nel titolo con una freccia e il numero delle schede, senza una riga aggiuntiva sopra l'editor. L'elenco permette apertura, passaggio e chiusura delle schede, mantenendo la precedente gestione di salvataggio e audio.
- La modalità «Solo foglio» nasconde anche barra inferiore e selettore dei quaderni. Il controllo della registrazione resta indipendente.

Il formato dei quaderni non cambia. Il pacchetto conserva le correzioni di Annulla e cancellazione tramite scarabocchio della 0.21.2. Include anche le cinque correzioni di compatibilità con Swift 5.10 già individuate nel lavoro precedente (catture esplicite dei task audio/PDF e tipi espliciti della sintesi locale), senza flag sperimentali del compilatore.

## Verifiche della consegna

**Verifiche finali PASS**, revisione dell'app `32ec31c`.

| Prova | Esito |
| --- | --- |
| Core macOS | 268 XCTest e 98 FSRS passati. Tre nuove regressioni del cursore: estremi, valori non validi, tutti gli indici fino a 1.500 pagine e salto numerico. Non è un benchmark di un PDF reale di 1.500 pagine. |
| Editor/audio nativi | 93 test passati: 46 integrazione, 30 affidabilità, 9 trascrizione, 2 compressione, 6 contenuti/AI locale. |
| Interfaccia finale | Cinque test passati: proporzioni in verticale/orizzontale e aree cliccabili; trascinamento/salto/stato/focus; apertura/passaggio/chiusura delle schede; tratto nativo/Annulla/nuovo tratto con confronto dei pixel; testo/Annulla/Ripristina. |
| Release del progetto iOS | `BUILD SUCCEEDED`, senza firma. |
| ZIP App Playground / Xcode 16.4 | Release per simulatore e dispositivo iOS senza firma: entrambe `BUILD SUCCEEDED`. App dello ZIP installata e avviata sul simulatore, viva per 60 iterazioni e libreria/guida visibile, controllata tramite OCR. |
| ZIP App Playground / Xcode 15.4 | Stessa revisione finale, Swift 5.10, Release per simulatore e dispositivo iOS senza firma: entrambe `BUILD SUCCEEDED`. |
| Controlli portabili | Struttura, grammatica di 305 file Swift, risorse, pacchetto e 53 test Node passati. |

[Verifica finale Apple e ZIP avviato](https://github.com/sminikiller/NeuralNotes/actions/runs/40047775770), [compatibilità Swift 5.10](https://github.com/sminikiller/NeuralNotes/actions/runs/40047781343), [risultato UI leggibile e schermate](https://github.com/sminikiller/NeuralNotes/actions/runs/40048961966). Quest'ultimo conferma 98 test selezionati, zero fallimenti e zero test saltati (93 nativi e cinque UI).

La [suite completa precedente](https://github.com/sminikiller/NeuralNotes/actions/runs/40044396173), `2697ed8`, ha anche verificato:

- aggiornamento del binario 0.20.8 → 0.22.0 su iPad Simulator, sopra la versione precedente senza disinstallazione né reset: quaderno SwiftData e impronte del catalogo/manifest di controllo conservati;
- servizi reali locali di email OTP/Auth, refresh/logout, PostgreSQL RLS, Storage privato, quote e cancellazione riprendibile con conservazione dell'altro account; trasporto AI simulato, nessuna chiamata a un provider a pagamento;
- tutte le classi native e UI, con gli esiti dettagliati sotto. Le rifiniture successive riguardano aree di tocco e due controlli UI; storage, account e servizi non cambiano.

La suite completa su `2697ed8` ha eseguito 268 XCTest Core e 98 FSRS su macOS, poi 400 XCTest nell'host iOS (398 passati, due saltati: controlli del solo alias Darwin `/private/var`, eseguiti su macOS) e 98 FSRS. Tutti i 132 test nativi dell'app sono passati. I 27 UI hanno avuto 25 successi e due fallimenti:

1. Il test del selettore tornava dall'editor alla panoramica e tentava subito di creare un quaderno: ora percorre prima il ritorno alla libreria. Ripetuto con successo su `d8b3227`.
2. Il test del layout confrontava con 48 punti anche lo sfondo esteso all'area sicura Home: sul simulatore il suo rettangolo accessibile è alto 73 punti, di cui 25 riservati al sistema. Le evidenze mostrano il canvas alto 687 su 834 punti in orizzontale (oltre l'82%). Il controllo ora misura cursore, distanza dal canvas e limite dello sfondo separatamente, conservando il requisito di spazio del foglio. Sono state anche estese le aree cliccabili delle icone tramite `contentShape`.

Le schermate e l'albero accessibile della prima suite sono conservati dalla [verifica delle evidenze](https://github.com/sminikiller/NeuralNotes/actions/runs/40047398264). La prima suite completa non viene dichiarata verde: entrambi i controlli corretti sono poi passati nella verifica finale. Non viene rivendicata una nuova esecuzione di tutti i 27 UI sull'ultima revisione.

## Archivio consegnato

`NeuralNotes-iPad-0.22.0.zip`: **511.870 byte, 230 file**. È l'archivio compilato e avviato nella CI finale, non un pacchetto rigenerato dopo il controllo.

SHA-256: `681d4201b341f40db1c54d1d803b4a32c8130350a6cef99047271d48e85e3061`.

CRC, elenco esatto dei file e contenuti confrontati con i sorgenti: normalizzazione LF/CRLF per 112 file di testo; confronto binario esatto delle risorse. L'archivio intermedio `e49cec…` resta solo fra le evidenze. Il vecchio ZIP 0.21.2 dell'utente conserva l'impronta `27a5325a8f25b51cad795b525dc93f328fe2c0cc5da834b25267705f95cac2dd`.

## Schermate

[Orizzontale](images/editor-0.22-landscape.png) · [Verticale](images/editor-0.22-portrait.png).

Quaderno di controllo su iPad Simulator. L'orizzontale è un fotogramma della registrazione della suite completa, prima della rifinitura delle aree cliccabili, che non modifica l'aspetto. La verticale proviene dalla verifica finale. La cattura statica orizzontale di XCTest contieneva un buffer ritagliato con metadati di orientamento incoerenti: è conservata fra le evidenze originali e non viene usata come anteprima.

La [prima esecuzione](https://github.com/sminikiller/NeuralNotes/actions/runs/40043939839) ha passato 268 Core, 98 FSRS e i servizi locali, poi si è fermata nello script prima dei test nativi: Bash 3.2 considera non inizializzata l'espansione dell'array vuoto dei filtri con `set -u`. Corretto lo script e riavviata la suite completa; le verifiche duplicate ancora in corso della prima esecuzione sono state annullate. Non viene conteggiata come suite completa passata.

## Ambito della delivery

Questa è la consegna del progetto App Playground per iPad. La 0.21.2 rimane conservata come versione precedente confermata dall'utente. Copie distinte del Playground possono avere contenitori separati: conservare progetto e backup nativi prima di passare alla nuova copia; non usare «Elimina i dati dell'app» per l'aggiornamento.

La compilazione e le prove su simulatore non equivalgono alla prova della Pencil, della fotocamera o di ore di registrazione sull'iPad fisico. Hosting/Auth/SMTP/provider AI pubblici, contenitore iCloud firmato e distribuzione TestFlight/App Store mantengono i gate separati descritti in [ACCEPTANCE.md](ACCEPTANCE.md) e [backend/ACTIVATION.md](../backend/ACTIVATION.md). Questa consegna non li dichiara attivati.
