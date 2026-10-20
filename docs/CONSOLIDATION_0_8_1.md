# NeuralNotes 0.8.1 — build 16

## Correzione del compilatore segnalata sull’iPad

La foto dell’utente mostra un errore reale in HeldShapeRecognition: “The compiler is unable to type-check this expression in reasonable time”. Le formule annidate per distanza dalla retta, lunghezza, bordi e scostamento dall’ellisse sono state riscritte in cicli e passaggi Double espliciti. Sono mantenute le soglie precedenti; aggiunta una regressione per rette diagonali nei due versi e verticali. Il parsing grammaticale non dimostrava la compilabilità dell’espressione originale.

## Salvataggio

Il flush salva prima l’inchiostro e il testo, poi le configurazioni del workspace. Un catalogo non leggibile non impedisce più di mettere su disco una pagina valida; la chiusura resta bloccata e segnala l’errore delle configurazioni da recuperare. Se arrivano modifiche durante una scrittura, il flush salva anche lo stato successivo prima di consentire il cambio pagina. Scrittura simulata interrotta e spazio esaurito mantengono lo stato da salvare e consentono un nuovo tentativo.

Durante un tratto attivo sono bloccati chiusura/cambio pagina, sostituzione dello strumento e modifiche distruttive alla selezione. Non cambiano coordinate dell’inchiostro, canvas esteso o formato delle pagine.

Se un errore delle configurazioni impedisce di chiudere il quaderno, **Editor → Azioni → Spazio e recupero** consente di ripristinare il catalogo senza uscire. Richiede una copia leggibile e nessuna registrazione/trascrizione in corso; salva prima la pagina e reinserisce le sessioni ancora in memoria, inclusa la registrazione in pausa il cui checkpoint era fallito. Il test di integrazione verifica il recupero con l’editor aperto, l’inchiostro conservato e la sessione audio ripersistita.

## Regressioni emerse nella CI iPad

La compilazione e l’esecuzione completa del simulatore hanno consentito di provare i test fino ad allora soltanto forniti. Il filtro Pencil del pinch viene applicato anche dopo la creazione del riconoscitore da parte di UIScrollView. Il comando Fine ha un pulsante identificabile sopra la tastiera, e il suggerimento del testo è spostato lontano dalla toolbar superiore. La sessione dell’editor ha una copia persistente per il riavvio di una sola finestra; le nuove finestre continuano a preferire lo stato della propria scena, evitando di riaprire automaticamente il documento di un’altra finestra.

Le prove sono state corrette dove l’aspettativa non descriveva UIKit o i dati iniziali: il rebase dello scroll deve conservare la posizione entro un pixel fisico, non entro un millesimo di punto del documento; l’undo della carta confronta l’aspetto originale completo, che può essere già esplicito; il test pinch allestisce un canvas con zoom attivo; il test export scorre la lista per raggiungere il comando. Il foglio di condivisione espone l’identificatore sul controller UIKit effettivo.

## Recupero del catalogo

Ogni aggiornamento valido di catalog.json conserva la copia precedente in recovery/catalog.previous.json, dentro il formato di pacchetto già ammesso dai backup. Il catalogo comprende sessioni audio, trascrizioni, impostazioni e copertina. Non è un backup esterno del quaderno e non protegge dalla perdita dell’iPad o dell’intero container.

Se il catalogo corrente manca ma esiste la copia precedente, l’app richiede il recupero anziché creare silenziosamente un catalogo vuoto. **Libreria → Recupero quaderni** distingue problemi dell’indice delle pagine e del catalogo. Il ripristino è esplicito, richiede il quaderno chiuso e rifiuta schemi futuri o copie prive dei media necessari. Conserva i byte del catalogo attuale e protegge dalla pulizia tutti i media presenti al momento del recupero, anche se il catalogo danneggiato non permette più di ricostruirne le relazioni. La copia precedente protegge inoltre i propri media durante la pulizia ordinaria. Questi file conservati possono occupare spazio: non sono rimossi automaticamente.

Duplicazione/importazione aggiorna anche la copia del catalogo con le nuove identità, per non ripristinare riferimenti audio del documento sorgente. I quaderni precedenti senza copia del catalogo restano leggibili; la protezione viene creata dopo aggiornamenti del catalogo nella nuova versione.

## Prove

1. Apri il nuovo Playground in una cartella separata, senza eliminare il precedente. Conferma che HeldShapeRecognition compili; poi esegui Verifica sul dispositivo e le prove della 0.8.
2. Su un quaderno temporaneo prova scrittura, cambio pagina, Annulla/Ripristina, chiusura/riapertura, focus e workspace. Prova il cambio pagina con un tratto in corso: non deve interrompere il tratto né perderlo.
3. Le prove automatiche simulano catalogo interrotto/mancante, schema futuro, media mancanti, ripristino, pulizia, backup reimportato, errore di spazio e modifiche durante una scrittura. Non danneggiare i tuoi quaderni reali per eseguire queste prove.
4. In Verifica sul dispositivo → Ambiente di esecuzione puoi leggere sistema, versione app, SDK se esposto dal runner, fascia del compilatore e moduli disponibili nell’SDK. La presenza del modulo non certifica il supporto dell’hardware o del sistema.

## Automazione Apple

Il workflow .github/workflows/verify.yml esegue prima controlli strutturali/grammaticali e i sette test Node senza chiamate AI, quindi build, Swift test e UI test iPad su un runner macOS. Usa tools/verify_macos.sh e conserva log e .xcresult. Le azioni sono fissate a commit verificati delle rispettive release. Il workflow non carica l’app su TestFlight e non distribuisce servizi.

I test del simulatore non provano Pencil fisica, standby, microfono reale o il compilatore specifico di Swift Playground: servono ancora le prove dell’iPad. Il risultato della CI deve essere indicato nei log della consegna; non viene dedotto dalla semplice presenza del workflow.

Il repository privato [sminikiller/NeuralNotes](https://github.com/sminikiller/NeuralNotes) è stato creato con autorizzazione dell’utente. La prima esecuzione macOS ha eseguito i 74 test core con zero errori, incluso HeldShapeRecognition, usando Xcode 16.4 / Swift 6.1.2. Ha poi rilevato due opzionali da aprire esplicitamente nei test Core Graphics. La seconda ha rilevato un crash interno del compilatore nell’ispezione PDF dei test: il visitor C sincrono è stato separato dalla closure ricorsiva. Le esecuzioni fallite restano visibili in Actions; l’esito complessivo viene registrato in VALIDATION.md dopo il completamento.
