# Fase 0.31 — rifinitura della grafia

La 0.31.0 è verificata con Xcode 26.6 e pronta per l’upload TestFlight. Sorgenti verificati `bd8bd29b8790bf1612a263b34b23d7101645904a`. [Verifica finale](https://github.com/sminikiller/NeuralNotes/actions/runs/42878279466)

## Come provare la grafia sull’iPad

1. Scrivi un paragrafo con la penna, selezionalo con il lazo e apri **Grafia** nella barra della selezione. Il comando agisce sulla grafia del livello attivo, senza spostare foto o testo digitato.
2. Prova **Raddrizza**: controlla l’anteprima e, se serve, attiva Allinea a sinistra o Appoggia sulle righe. **Annulla** scarta la proposta; **Applica** conferma.
3. **Uniforma dimensione** avvicina l’altezza delle parole senza sostituire le lettere. **Ripulisci tratto** offre tre intensità: confrontale prima di confermare.
4. In **Riadatta alla larghezza**, trascina i due bordi o usa il cursore; le parole vanno a capo. Con VoiceOver le maniglie sono controlli regolabili, con posizione e larghezza lette ad alta voce.
5. **Spazio tra le righe** regola l’interlinea della selezione. Se la proposta supera il foglio, Applica resta disabilitato. Dopo una conferma, Undo ripristina l’originale in un passo e Redo riapplica la modifica.



## Comportamento e protezione dei dati

La rifinitura è geometrica e lavora sul dispositivo. Raggruppa righe e parole, stima la linea di base e sposta, ruota o scala i tratti esistenti. Non cambia le parole riconosciute dall’OCR. Suggerimenti OCR già disponibili vengono usati solo sulle pagine composte da grafia, evitando interferenze da PDF, foto, testo digitato e altri livelli.

Le trasformazioni affini riutilizzano il percorso PencilKit originale. La pulizia cambia solo le coordinate mantenendo numero e indici dei punti, estremi, pressione, dimensioni, tempi, opacità, inclinazione, secondaryScale e threshold quando disponibile. Maschere, seme, inchiostro e collegamenti audio conservano la propria identità. Per misurare grafia parzialmente cancellata si usa solo la parte visibile; la pulizia mantiene comunque i campioni originali.

L’anteprima non scrive file e non sostituisce il disegno autorevole. Applica verifica nuovamente pagina, livello, budget della cronologia e ingombri dipinti; conferma tutto in un solo passo di annulla. Cambiare pagina, livello o strumento, avviare il replay o chiudere il quaderno scarta l’anteprima. Undo durante l’anteprima annulla solo la proposta: non consuma anche l’ultima azione reale.

Le modifiche delle maniglie vengono accorpate con un worker alla volta e aggiornano il risultato durante il trascinamento. L’anteprima copre solo il viewport, ha cache limitata a due milioni di pixel e lascia disponibili zoom e scorrimento. Non avvia una nuova decodifica PDF. Le ottimizzazioni PDF e il renderer dei livelli restano quelli delle fasi precedenti.

Il catalogo Guida e Novità comprende i tutorial di Livelli e Grafia; il manuale è aggiornato in [GUIDA_FUNZIONI.md](GUIDA_FUNZIONI.md). Grafia compare anche nelle azioni della selezione della mini-toolbar in Solo foglio.

## Limiti dichiarati

- Selezione fino a **4.000 tratti e 500.000 punti**; oltre il budget viene richiesto un paragrafo più piccolo.
- Uniforma dimensione limita ogni scala a **0,8–1,25**. Riadatta sposta parole intere, senza dividerle.
- Una proposta fuori pagina non viene applicata: non taglia né elimina appunti.
- Il correttore ortografico del §9.3 era facoltativo e resta escluso. Nessuna espansione AI, backend o iCloud.
- La qualità percepita su grafia reale e le prove prolungate con Apple Pencil richiedono il collaudo fisico, distinto dai test sintetici e dal simulatore.

## Verifiche e consegna

- **448 XCTest Core, 98 Swift Testing, 283 test nativi e 2 test UI** superati. Le prove verificano i campioni originali dei tratti, le maschere, le cinque righe raddrizzate e l’esattezza dopo riapertura, Undo, Redo e importazione del backup. [Verifica finale](https://github.com/sminikiller/NeuralNotes/actions/runs/42878279466)
- Le due prove UI aprono l’editor reale. Controllano anteprima, Annulla, Applica, Undo e Redo, trascinamento delle maniglie e dimensioni del foglio. Nelle immagini si vedono i tratti originali sbiaditi, le righe dritte dopo Redo e i due bordi regolabili. [Prove UI](https://github.com/sminikiller/NeuralNotes/actions/runs/42878279466/artifacts/13793352447)
- I cinque test UI su livelli, PDF denso, evidenziatore a parole, finestra di scrittura e doppio tap erano già verdi nel collaudo precedente. Le correzioni finali riguardano la rifinitura della grafia. [Regressioni precedenti](https://github.com/sminikiller/NeuralNotes/actions/runs/42871758090)
- Compilazione Release dell’app e del pacchetto Playgrounds per dispositivo e simulatore superata. Avvio dello ZIP sul simulatore con **60 osservazioni** e libreria/guida visibile. [Pacchetto verificato](https://github.com/sminikiller/NeuralNotes/actions/runs/42878279466/artifacts/13793134439)
- ZIP **NeuralNotes-iPad-0.31.0.zip** con **373 file**. CRC e confronto di sorgenti e risorse passati. SHA-256 `c37e25b1af15e8c88d181ecf2d4f82df84474bc82dd07b6234e6aed48b14bbff`.

Il test del quaderno in formato 0.30 conserva il testo OCR e attraversa salvataggio, riapertura, PDF vettoriale, backup nativo e importazione come copia. La guida integrata contiene 63 tutorial. Le prove con materiale reale su iPad completano il collaudo percettivo della grafia.
