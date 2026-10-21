# Funzioni AI — piano operativo e stato effettivo, 0.14.0

La struttura è già presente; attivazione remota e validazione della qualità non sono completate. Il backend non ha un endpoint live o credenziali configurati in questa sessione. Il PDF affiancato aggiunge un ingresso rapido alla ricerca del termine; non dimostra che un provider remoto sia raggiungibile.

## Un solo flusso comprensibile

1. Seleziona testo, oggetti/lazo, area, parola toccata o sottolineatura con lo strumento Lente. Per PDF esterni usa selezione nativa o l’interruttore esplicito per cerchio/sottolineatura.
2. Mostra testo/fonti effettivamente letti. Una selezione vuota non riutilizza il contesto precedente; le scansioni esterne senza testo richiedono ancora import/OCR.
3. Azioni: Spiega, Definisci, Esempio, Confronta, Scheda/Quiz, Cerca sul web. Il pannello distingue fonte del quaderno, dizionario e risultati internet.
4. Risposta nel popup, espansione nel pannello, citazioni verso pagina/minuto o URL. Inserimento modificabile nel foglio con annulla. Salvataggio fallito segnalato separatamente dalla risposta già ricevuta.
5. Connessione AI apre destinazione, modello, credenziale nel portachiavi e consenso. Nessuna richiesta viene inviata solo scegliendo un modello o aprendo il pannello.

## Matrice delle funzionalità

| Funzione | Implementazione | Cosa manca per considerarla collaudata |
| --- | --- | --- |
| Dizionario | UIKit locale, nessun invio ai modelli | Verifica dei dizionari installati sul dispositivo |
| Ricerca browser | Link esplicito con query del solo termine, anche per PDF esterni | Prova di apertura sul dispositivo |
| Spiegazioni e chat delle fonti | Lente, streaming, conversazioni salvate, backend e adapter API personali | Endpoint/chiave reale e prova italiana con citazioni corrette |
| Scheda concetto | `/v1/lookup`: definizione, spiegazione, esempi, termini correlati; glossario e inserimento | Solo backend strutturato; non ancora risposta progressiva della scheda |
| Ricerca web con risposta nel popup | `/v1/research`, tool effettivo e URL validati, cache di un’ora e testo con link | Backend HTTPS, funzione abilitata, token, modello compatibile e consenso; nessuna esecuzione live |
| Quiz, esame, flashcard e mappa | Quiz da carte locali e generativo, revisione FSRS, mappe modificabili con fonti | Qualità delle generazioni e UI Apple delle ultime aggiunte |
| Contesto di tutta la lezione | Selezione bilanciata di estratti e riferimenti fino alla fine | Non è ancora una riscrittura integrale senza omissioni |
| Sbobina semantica, parlanti, formule | Non completati | Job a blocchi riprendibile, riconciliazione con tempi originali, motore diarizzazione reale, validazione matematica |

## Backend e accesso

Mantengo gli endpoint esistenti: `/v1/study`, `/v1/lookup`, `/v1/quiz`, `/v1/research`. Per una distribuzione con chiave del gestore, la chiave resta sul backend; i client usano token utente, limiti di richieste e budget. Le connessioni personali rimangono facoltative nel portachiavi dell’iPad. Le quote del backend attuale sono in memoria: un servizio pubblico richiede persistenza e un limite di spesa lato provider. Non viene scelto o acquistato automaticamente un servizio.

Per la ricerca OpenAI la documentazione ufficiale conferma Responses con `web_search`, output del tool separato dal messaggio e annotazioni delle fonti. I risultati mostrati devono avere citazioni visibili e cliccabili: il percorso implementato conserva proprio quelle annotazioni e rifiuta risultati incompleti/non citati. [OpenAI Docs: web search](https://developers.openai.com/api/docs/guides/tools-web-search).

Il login ChatGPT non è un pulsante da aggiungere con un client ID preso da un’altra app. La disponibilità ufficiale distingue integrazioni commerciali selezionate, partner open source e alcuni client privati. Questo progetto privato non ha una registrazione/abilitazione confermata; per ora rimangono le API personali o il backend. [OpenAI Docs: disponibilità e integrazioni](https://developers.openai.com/siwc/quickstart). [Analisi API/login e configurazione già verificata](AI_API_AND_LOGIN.md).

## Ordine di completamento

1. **Collaudo Apple della 0.14:** compilazione e interazione Pencil/PDF/RTF; risolvere prima qualunque regressione dei dati. Il blocco CI attuale impedisce la conferma.
2. **Attivazione remota:** verificare autenticazione e quota del backend reale, modello/configurazione, timeout e cancellazione. La disponibilità di endpoint e credenziali è una dipendenza esterna non presente; non viene dichiarata risolta.
3. **Qualità sulle fonti:** trenta casi italiani con testo, grafia, PDF e lezioni lunghe; per ogni risposta controllare affermazioni e riferimenti. Fixture JSON e citazioni sintatticamente valide non bastano.
4. **Lezione intera:** elaborazione gerarchica con checkpoint per blocco, copertura di tutti gli intervalli, tempi originali e ripresa; indice dei punti non elaborati. Non sostituire la trascrizione fedele con il riassunto campionato attuale.
5. **Funzioni avanzate:** parlanti reali, formule/LaTeX verificabili, suggerimenti di titoli/tag e orario lezioni. Ogni inserimento finale resta un’azione esplicita annullabile.

I punti 4 e 5 restano aperti e non sono etichettati come implementati. Il rilascio corrente consegna la base locale e i collegamenti descritti, con test portabili e prove Apple predisposte. Non attiva servizi esterni né certifica l’intera roadmap.
