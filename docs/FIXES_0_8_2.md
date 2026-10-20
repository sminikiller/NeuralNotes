# NeuralNotes 0.8.2 — build 17

## Scarabocchio

La cancellazione segue una traccia arrotondata lungo lo scarabocchio reale, invece del rettangolo che lo contiene. Un giro ripetuto non riempie l'interno: cancella soltanto l'inchiostro attraversato. Restano le maschere vettoriali di PencilKit, con undo/redo, salvataggio e PDF vettoriale. Le coordinate della cancellazione tengono conto anche di tratti spostati, ingranditi o ruotati.

Le parole digitate richiedono che almeno metà della loro area sia coperta dalla traccia. Un piccolo contatto al bordo o una parola soltanto racchiusa nello scarabocchio non bastano. Il riconoscimento del gesto resta euristico e configurabile per workspace; immagini e forme-oggetto non vengono cancellate dal gesto.

## Conferma delle forme

Dopo circa 650 ms di punta ferma, linea/ellisse/rettangolo riconosciuti restano confermati fino al sollevamento. I piccoli spostamenti e gli ultimi campioni touch non eliminano più l'anteprima o la forma in attesa. Sollevare la Pencil salva la geometria precisa come tratto PencilKit con lo stesso stile; un evento di cancellazione ripristina la visibilità del canvas e conserva l'inchiostro libero consegnato da PencilKit.

## Ripresa e copertina

La data dell'ultima modifica viene salvata insieme alla pagina, con precisione inferiore al secondo. Alla riapertura si sceglie la pagina modificata più di recente, anche se prima della chiusura si è visitata un'altra pagina o si è cambiato l'ordine dei fogli. Le pagine rimosse non partecipano alla scelta. I vecchi quaderni senza date continuano a usare l'ultima pagina visualizzata finché non si modifica una pagina nella nuova versione.

In libreria: pressione prolungata sul quaderno → **Personalizza copertina** → **Ultima pagina modificata** → **Salva**. L'anteprima include carta, testo, immagini, PDF e inchiostro; mostra tutto il foglio senza tagliare i bordi. Si aggiorna tornando in libreria dopo il salvataggio. La scelta segue il quaderno nei backup e nelle copie. Si può tornare alla foto o alla copertina a colori. Non viene cambiata automaticamente la copertina degli altri quaderni.

I due nuovi campi sono facoltativi nel formato v1: non servono conversioni o cancellazioni dei quaderni. Una nuova copia del Playground può comunque avere uno storage diverso: conservare il progetto precedente ed esportarne i quaderni prima di importare una copia.

## Verifica

11 nuove regressioni: tre core (date/ordine/eliminazione, scritture e letture, modalità copertina), sette di integrazione (forme confermate e annullate, ripresa/vecchi quaderni, scarabocchio reale/trasformato, parole) e una UI (scelta della copertina dopo riavvio). Esteso anche il test di clonazione per includere data e modalità della copertina.

Esito corrente della CI: vedere [VALIDATION.md](VALIDATION.md). I test del monitor touch passano attraverso gli stessi metodi usati dal gesto, con campioni deterministici: non simulano pressione, latenza e movimenti di una Pencil fisica.

Prova sul proprio iPad:

1. Scrivi due parole vicine e cancella parte della prima con uno scarabocchio irregolare; controlla seconda parola, undo/redo e riapertura.
2. Disegna una linea e un cerchio, fermati fino alla correzione, muovi leggermente la punta e sollevala: la forma precisa deve restare.
3. Modifica pagina 2, visita pagina 1 senza scrivere, chiudi e riapri: deve tornare a pagina 2.
4. Attiva la copertina automatica, modifica un'altra pagina e torna in libreria: l'anteprima deve mostrare quella pagina.
