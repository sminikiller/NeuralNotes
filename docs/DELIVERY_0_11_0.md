# NeuralNotes 0.11.0, build 21 — anteprima

Sorgenti e App Playground aggiornati; non è un IPA firmato o una versione dichiarata completa. I test locali passano, mentre compilazione con SDK Apple, test UI delle modifiche recenti e prova fisica restano aperti per il blocco CI e l’assenza di un dispositivo collegato. [Evidenze e limiti](ROADMAP_VALIDATION.md), [audit di entrambi i piani e parti mancanti](CLAUDE_PLAN_AUDIT.md).

## Comandi aggiunti

| Funzione | Accesso e comportamento |
| --- | --- |
| Sposta selezione | Seleziona inchiostro/oggetti → barra della selezione o pressione prolungata su Selezione → Sposta in un’altra pagina. Conserva livelli/fonti/anchor audio; riduce il gruppo se serve; uno stesso undo ripristina entrambe le pagine. |
| Taglia protetto | Taglia elimina soltanto se la copia è riuscita. Una selezione oltre il budget complessivo di 32 MB resta nel foglio, con un errore visibile. Le immagini copiate hanno file temporanei indipendenti dal quaderno sorgente. Gli appunti interni non sono un backup persistente dopo il riavvio. |
| Ricerca sul foglio | Apri un risultato della ricerca: posizione centrata e regioni evidenziate, chiudibili senza modificare gli appunti. Testo formattato tramite layout; PDF/grafia tramite OCR della pagina. |
| Laser | Azioni → Puntatore laser. Traccia rossa temporanea; non entra nel file o nella cronologia. Scegli uno strumento o disattiva per tornare alla scrittura. Uscita esterna dedicata ancora assente. |
| Quiz/esame | Flashcard e ripasso → Quiz e simulazione. Quiz locale da almeno quattro risposte diverse o generazione tramite backend `/v1/quiz`. Risposte salvate, risultato e ultime dieci sessioni; il timer continua fuori dal pannello. |
| Mappa modificabile | Studio → Schema → genera/apri elaborazione salvata → Crea pagina mappa modificabile. Nuova pagina con titolo, fino a otto punti e connettori nativi; testo completo conservato nell’elaborazione. |
| Fonti di lezioni grandi | Studio e quiz remoto distribuiscono gli estratti lungo l’indice quando manca una domanda specifica. Limiti e campionamento sono dichiarati; non viene promessa una lettura integrale. |
| Nota rapida da Comandi | App Intent Crea una nota rapida, con titolo/testo facoltativo; quaderno nella Inbox. Disponibilità in Comandi/Siri da verificare nella build Apple. |
| Spotlight facoltativo | Cerca negli appunti → Quaderni in Spotlight. Soltanto titoli e tag; spegnendo rimuove l’indice. L’apertura attende la chiusura dell’editor già aperto. |
| Guida iniziale | Sidebar → Guida rapida; appare alla prima apertura di una libreria vuota. |
| Controlli incorporati | Sidebar → Verifica sul dispositivo. Aggiunti quattro controlli su documenti temporanei per transazione pagine, quiz, fonti/mappe e taglia/spostamento/laser/ricerca; 31 totali. Non sono già stati eseguiti sul tuo iPad. |

Drop PDF separato dall’import dei backup, controllo della pagina dopo caricamenti asincroni, prefetch serializzato e cache con limite stimato completano questo lotto. I nuovi controlli di dimensione impediscono di salvare cataloghi, immagini o vettori che l’importatore rifiuterebbe, mantenendo l’ultima copia leggibile.

## File e quaderni esistenti

Generazione con `python tools/package_ipad.py`: `.verification/NeuralNotes-iPad-0.11.0.zip`, contenente `NeuralNotes.swiftpm`. Progetto completo con `python tools/package_project.py`: `.verification/NeuralNotes-Sorgenti-0.11.0.zip`. Checksum, elenco esatto e byte dei sorgenti verificati; non sono prove di compilazione Swift.

Conservare il vecchio Playground e i suoi backup. Una copia aperta come app nuova può avere un contenitore dati distinto; non trasferisce automaticamente la libreria precedente. Importare dalla vecchia copia i `.nnbackup`/`.nnbook` e verificare la riapertura prima di abbandonare l’originale. Non cancellare i dati dell’app per risolvere un errore di progetto.

Il formato `.nnbook` resta v1 con campi facoltativi e nessuna migrazione SwiftData. Le vecchie versioni non conoscono quiz, mappe e altri metadati aggiunti: evitare di modificare avanti e indietro lo stesso documento con versioni diverse, conservando il backup originale.

Il test UI intermittente del testo resta aperto. Nessuna prova recente su fotocamera/scanner/Pencil/standby, provider File, CloudKit a due dispositivi o qualità AI live viene dichiarata completata. Le voci ancora da sviluppare sono nel piano aggiornato.
