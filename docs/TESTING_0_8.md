# NeuralNotes 0.8 — build 15

## Workspace e toolbar flottante

La toolbar è ora un overlay sul canvas, con materiale traslucido, angoli arrotondati e ombra. Il foglio mantiene il canvas nativo esteso e il doppio tocco larghezza/pagina intera della 0.7.1.

Apri l’icona dei cursori nella toolbar oppure **Azioni → Workspace e preferiti**. Scrittura, Matematica, Lettura e Disegno sono punti di partenza modificabili. Puoi duplicare, rinominare ed eliminare configurazioni, scegliere fino a otto preferiti e riordinarli con Modifica. Restano sempre disponibili tutti gli strumenti dal pulsante +. Colori, spessori, posizione della toolbar, barra pagine, stato salvataggio e automatismi si salvano nel catalogo del quaderno e seguono backup e duplicazione. Non scrivono nelle preferenze personali globali; al primo avvio i vecchi valori personali dei gesti vengono copiati come punto di partenza.

Per Penna ed Evidenziatore le palette sono separate: preferiti e tre colori recenti, tre spessori recenti e selettore personalizzato. I tre colori rapidi nella toolbar danno precedenza ai recenti; la palette completa si apre dalla tavolozza. Il pulsante stella aggiunge/rimuove il colore dai preferiti. Le forme condividono una palette propria. Il righello usa `PKCanvasView.isRulerActive`, l’API pubblica [PencilKit di Apple](https://developer.apple.com/documentation/pencilkit/pkcanvasview/isruleractive).

Prova:

1. In Scrittura scegli blu per Penna e arancione per Evidenziatore. Alternali: ciascuno deve recuperare il proprio colore e spessore. Usa quattro colori e verifica che i recenti siano tre, senza duplicati.
2. Passa a Matematica: prova linea, freccia, cerchio e righello fra i preferiti. Cambia la posizione della toolbar e nascondi la barra pagine. Torna a Scrittura: la configurazione precedente deve restare invariata.
3. Duplica un’attività, rinominala e riordina tre preferiti. Chiudi e riapri il quaderno nella stessa copia dell’app. Verifica anche un altro quaderno e un backup reimportato.
4. Prova toolbar in alto, basso e sui due lati, anche con selezione di oggetti, rotazione e Split View. La pagina deve restare interamente raggiungibile con pan/zoom; l’overlay può coprire temporaneamente la zona sottostante, come nelle immagini di riferimento.

## Focus e audio

In Solo foglio rimangono due comandi flottanti: il pulsante della mini toolbar, inizialmente chiusa, e il comando per ripristinare tutti gli strumenti. La mini toolbar mostra i primi tre preferiti del workspace e Annulla; può essere richiusa. Il gruppo si può trascinare come il precedente pulsante focus. Un indicatore rosso con REC e durata resta visibile durante la registrazione anche in focus; durante la trascrizione compare l’avanzamento. Toccarlo apre Audio, senza interrompere la registrazione.

Registra, entra in focus, apri/riduci la mini toolbar e scrivi con gli strumenti rapidi. Verifica indicatore, durata, apertura di Audio e ritorno agli strumenti completi. Standby, background e gestione delle interruzioni usano il percorso audio precedente e devono essere provati sul dispositivo; questo aggiornamento non dimostra che funzionino in ogni runner.

## Forme trascinate e pressione prolungata

Scegli una forma dalla toolbar o dal menu Inserisci foto o forma. Appoggia Pencil e trascina: per linea/freccia il punto iniziale è la coda e quello finale è la punta; per cerchio/ellisse e rettangolo i due punti definiscono gli angoli opposti del riquadro. L’anteprima segue la punta e la forma viene salvata al rilascio. Usa Oggetti per spostarla/ridimensionarla. Nella modalità forme un dito traccia e due dita scorrono; Pencil resta esclusa dallo scorrimento.

Con Penna o Evidenziatore disegna una linea leggermente tremolante, un cerchio chiuso o un rettangolo chiuso e ferma la punta per circa **0,65 secondi senza sollevarla**. Un feedback e l’anteprima precisa confermano il riconoscimento. Muovere ancora la punta ripristina il disegno libero; sollevarla conserva la correzione come inchiostro PencilKit vettoriale. Il riconoscimento è conservativo: scarabocchi, curve aperte, figure troppo piccole o irregolari possono non essere corretti. L’algoritmo riconosce rettangoli allineati al foglio; non raddrizza poligoni arbitrariamente ruotati. Con righello attivo il riconoscimento automatico resta disattivato.

Il monitor dei tocchi non sostituisce il motore di scrittura PencilKit. Durante l’anteprima della figura riconosciuta viene mostrata una copia dell’inchiostro precedente; il tratto definitivo viene sostituito solo dopo la consegna del nuovo tratto da PencilKit. Se i callback non coincidono con una sola nuova pennellata, i dati originali vengono conservati. Il rendering temporaneo richiede una prova fisica su questo iPad.

Prova frecce nei quattro versi e una linea verticale; cerchi in entrambi i versi di trascinamento; Annulla/Ripristina, riapertura, cambio pagina e PDF vettoriale. Per il riconoscimento prova pressione prolungata, rilascio immediato senza correzione, ripresa del movimento e disattivazione del gesto dal workspace. Controlla che scarabocchio per cancellare e normale scrittura continuino a funzionare. Il righello deve apparire, potersi posizionare con le dita e guidare la Penna; il suo pulsante lo nasconde.

## Libreria e copertine

La dashboard propone Nuova idea, Importa e Riprendi da qui con accesso diretto agli ultimi cinque quaderni aperti ancora disponibili nell’ambito selezionato. I recenti sono locali a questa installazione; non vengono aggiunti al contenuto del backup. La griglia è più densa e le copertine più compatte. Nuovi quaderni alternano i colori disponibili e le copertine prive di una personalizzazione usano motivi/simboli stabili, diversi per identità.

Apri **Copertina** nella scheda del quaderno oppure **Personalizza copertina** dal menu contestuale. Scegli colore libero, uno dei quattro motivi, un simbolo o una foto. Salva, riapri, duplica ed esporta/importa un backup. I cataloghi precedenti senza personalizzazioni restano leggibili. Verifica anche la rimozione della foto e il ritorno a colore/motivo.

## Verifiche effettive

Sono forniti **129 metodi XCTest** (67 core, 49 integrazione, 13 UI): 14 aggiunte coprono palette indipendenti/limiti, profili e JSON precedente, dati invalidi, estremi direzionali, riconoscimento conservativo, catalogo/clone, riapertura workspace e preferenze globali, undo/redo delle forme, stile marker, policy del righello e mini toolbar. Tre controlli incorporati aggiunti portano Verifica sul dispositivo a **25**; verificano dati e geometria, non simulano una Pencil.

In Windows sono verificati struttura Xcode, membership dei sorgenti, grammatica Swift e integrità/contenuti dei due ZIP. **Compilazione Apple, type checking, XCTest/UI, gesti Pencil, righello, prestazioni e aspetto finale non eseguiti qui.** Esegui prima i 25 controlli temporanei, poi il percorso manuale sopra. Conserva vecchio Playground e backup dei quaderni prima di aprire la nuova copia.
