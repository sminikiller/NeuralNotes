# NeuralNotes 0.15.0 / build 27 — recupero ed editor

22 ottobre 2026. Questa consegna interviene sui problemi segnalati; non dichiara completata tutta la roadmap né una build Apple verificata.

## Quaderni e backup

- Corretto il confronto dei percorsi nel controllo «Backup: limite di spazio e due copie protette»: gli alias Darwin `/var` e `/private/var` vengono normalizzati. Anche l’URL restituito dal backup è coerente con quello elencato.
- Le nuove copie hanno un ordine temporale persistente nel nome. Le date arrotondate da un provider File non fanno più scegliere casualmente le due copie protette. Le copie precedenti restano leggibili; budget e protezione delle ultime due non sono stati rimossi.
- Se l’indice della libreria è vuoto, all’avvio vengono cercati i pacchetti non indicizzati nel contenitore corrente. Un journal audio pendente non impedisce più di registrare nuovamente il quaderno locale per riprenderne il recupero.
- **Libreria → Recupero quaderni → Importa quaderni da una cartella** cerca cartelle contenenti `manifest.json` fino a quattro livelli. Importa copie con nuove identità; non sposta né sovrascrive gli originali. Limiti: 200 pacchetti, 50.000 elementi; non segue collegamenti simbolici interni.
- Import nativo e PDF usano lettura coordinata del provider File, fuori dal thread UI, mantenendo l’accesso alla risorsa durante l’operazione. ZIP, PDF e versione nativa sconosciuta hanno ora messaggi distinti; controlli CRC e percorsi restano attivi.
- Dichiarata l’esposizione dei documenti in File per l’app autonoma. Il comportamento del contenitore ospitato da Swift Playground resta da verificare.

**Limite del recupero:** nessun export fallito dell’utente è disponibile nella cartella di lavoro. È stato provato un archivio fisso nel formato nativo precedente `NNBOOK01`, non il suo file. Non posso confermare la causa del suo errore d’importazione o il recupero dei suoi quaderni. Copie diverse del Playground possono usare contenitori separati: il nuovo pacchetto non può leggere automaticamente quello vecchio. Conservare la vecchia copia e i dati; per trasferire usare il `.nnbackup`, la cartella `.nnbook` oppure il nuovo import da cartella. Non usare «Elimina i dati dell’app».

Il difetto degli alias spiega un possibile falso fallimento della diagnostica, ma non dimostra che ogni errore di backup avesse questa causa. Un archivio davvero troncato o con media mancanti viene ancora rifiutato senza modificare l’originale.

## Comandi dell’editor

| Richiesta | Cambiamento e accesso |
| --- | --- |
| Cestino pagine | Anteprime → Seleziona → selezione multipla / Tutte → Elimina. Cestino → seleziona → Ripristina. Le pagine ripristinate sono aggiunte in fondo; un solo undo per l’operazione. I media delle pagine nel cestino restano protetti dalla pulizia. |
| Cestino nel trasferimento | Backup/import e duplicazione conservano anche le pagine rimosse, rimappando identità e ancore audio. La cancellazione definitiva resta in Spazio e recupero. |
| Mini toolbar | Workspace → **Strumenti per Solo foglio**, etichetta esplicita. Da uno a cinque strumenti per attività; i vecchi preset da tre restano validi. |
| Righello | Attivalo dalla toolbar, spostalo e ruotalo con due dita. Penna/evidenziatore restano vincolati al bordo scelto all’inizio del tratto, anche spostando la punta fuori dalla guida. Rotazione agganciata ogni 45° entro ±6°. Tratti vettoriali con undo e annullamento del gesto. La guida visiva non intercetta la Pencil. |
| Foto in movimento | Ritagli in cache e un aggiornamento del modello per campione; il trascinamento conserva l’anteprima ma registra salvataggio e undo al rilascio. Il gesto annullato ripristina gli oggetti. Nessuna misura FPS hardware disponibile. |
| Testo | Il pulsante testo apre il campo trasparente direttamente sul foglio. Barra compatta B/I/U, menu Aa per stili/colori/elenchi e Fine; stesso campo per modifica dal menu oggetti. Interazione Scribble e segnaposto per Pencil o tastiera. Il riconoscimento effettivo dipende da iPadOS, lingua e impostazioni. |

## Verifiche effettive

- Swift 6.1.2 Linux, `.verification/core-work-0.15.log`: **182 XCTest eseguiti, 180 passati, due skip Darwin preesistenti, zero errori; 98 FSRS passati**.
- Otto nuovi test Core: ordine/rotazione dei backup con mtime riscritti e restauro; alias del percorso; eliminazione/ripristino multipli atomici; guida del righello e clipping; cinque strumenti persistenti; ricerca delle cartelle in sola lettura; import fixture nativa precedente e messaggio ZIP; trasferimento del cestino con media e ancore. Estesa la prova del journal audio locale pendente.
- Quattro nuovi metodi Apple predisposti: righello vincolato/undo/cancel e tocco Pencil non intercettato, cestino multiplo/undo, ricostruzione dell’indice locale, recupero da cartella esterna come copia. Aggiornato il test UI del testo al campo sul foglio e al pulsante Fine. **Non eseguiti con Apple**.
- Controlli progetto: **406 oggetti, 257 file Swift, 313 metodi XCTest presenti**; grammatica e parsing del compilatore Swift in modalità 5 riusciti. Sono controlli di sintassi e appartenenza ai target, non compilazione con UIKit/SDK Apple.
- I 23 test backend a fixture appartengono alla lavorazione precedente: codice server invariato, non rieseguiti qui. Nessuna API live o nuova prova audio di ore su hardware.
- Restano 35 controlli diagnostici integrati, non eseguiti su iPad dalla sessione di sviluppo. La CI Apple è ancora bloccata dalla fatturazione già documentata; nessuna modifica all’account o nuovo tentativo per aggirarla.

Comandi riproducibili: `python tools/generate_project.py`, `python tools/check_project.py --swift-syntax`, `bash tools/verify_linux.sh` nell’immagine ufficiale `swift:6.1.2`, `swiftc -frontend -parse -swift-version 5` sui sorgenti nativi. Pacchetti generati con `tools/package_ipad.py` e `tools/package_project.py`: checksum ZIP e confronto byte per byte con i sorgenti, un solo punto d’ingresso e Core separato.

Pacchetto iPad: `NeuralNotes-iPad-0.15.0.zip`. Progetto/test/report: `NeuralNotes-Sorgenti-0.15.0.zip`. Non sono IPA firmati. Le funzioni AI e le dipendenze esterne mantengono lo stato descritto nel [piano AI](AI_FUNCTIONAL_PLAN.md).

Verifica del pacchetto iPad: 196 sorgenti/risorse invariati più manifest (197 file ZIP); SHA-256 `1d47542aa39d088655b66f3081b90717f3829121b8856437d47812f72ca722d5`. Archivio sorgenti: 325 file confrontati byte per byte.
