# Verifica della versione 0.2 sull’iPad

> Usare ora il pacchetto **0.2.1**. I controlli incorporati sono nove, con regressioni per colori chiaro/scuro e percorsi validi/vietati. Prima completare [FIXES_0_2_1.md](FIXES_0_2_1.md), poi ripetere il percorso seguente.

Dispositivo dell’utente: iPad di decima generazione, iPadOS 18.7.8. La 0.1 ha ricevuto conferma manuale positiva; questa nuova versione deve ancora essere verificata. Eseguire il progetto, oltre alla sola anteprima.

## Prima verifica

- [ ] Conservare il vecchio progetto, estrarre la 0.2 in una cartella separata, aprire `.swiftpm` e compilare in Swift Playground.
- [ ] Sidebar → **Verifica sul dispositivo** → **Esegui controlli sul mio iPad**.
- [ ] Registrare gli otto risultati e condividere eventuali FAIL. Il pannello usa solo dati temporanei e non registra il microfono.

I controlli incorporati verificano round trip PencilKit, copia pagina, rifiuto percorsi esterni, PDF ruotato/import/export, OCR di un’immagine generata, fonti della sintesi, modello della timeline e persistenza SwiftData/cestino. Non sostituiscono misure di latenza, audio reale o XCTest.

## Scrittura e salvataggio

1. Creare un quaderno, aprirlo e premere **Scrivi e studia**.
2. Con Pencil scrivere su pagina 1; provare colori, spessori, evidenziatore, gomma, lazo, undo e redo.
3. Verificare che il dito navighi senza scrivere; attivare Dito e provare disegno con touch.
4. Aggiungere una pagina, scegliere un altro sfondo e scrivere. Tornare alla prima: i tratti devono esserci.
5. Duplicare pagina, riordinarla, rimuovere una pagina e controllare le altre.
6. Attendere **Salvato sul dispositivo**, uscire in libreria, chiudere Swift Playground e rilanciare lo stesso progetto.
7. Riaprire il quaderno: ordine, sfondi, tratti e oggetti devono restare.

- [ ] Scrittura/zoom/pan regolari, nessuno spostamento degli appunti durante rotazione.
- [ ] Salvataggio e riavvio superati.
- [ ] Sessione lunga e memoria/latency controllate; nessuna soglia dichiarata senza misura.

## PDF, immagini, testo e file

- [ ] Importare un PDF da File, scrivere marker su angoli e righe note, zoomare e ruotare l’iPad.
- [ ] Ripetere con PDF a 0/90/180/270 gradi e crop box non standard; marker sempre allineati.
- [ ] Importare un’immagine; dal pannello **Testi e immagini** cambiarne posizione/dimensioni.
- [ ] Aggiungere testo, modificarlo e riaprire dopo salvataggio.
- [ ] Allegare un file e recuperarlo da **Ricerca e allegati**.
- [ ] Esportare PDF, aprirlo in un’altra app e verificare tutte le pagine/annotazioni.
- [ ] Esportare il quaderno nativo in File e verificarne la cartella completa. L’import nativo non è ancora implementato.
- [ ] Duplicare un quaderno con contenuti: copia indipendente. Eliminare la copia, riavviare e ripristinarla dal Cestino.

## Audio e timestamp

1. Aprire Audio → Nuova registrazione, autorizzare il microfono e parlare per almeno 20 secondi.
2. Chiudere il pannello e scrivere tre note a intervalli distinti durante la registrazione.
3. Mettere in pausa, attendere dieci secondi senza registrare, riprendere e scrivere ancora.
4. Terminare, riprodurre, usare il cursore e i **Momenti collegati a questa pagina**.
5. I dieci secondi di pausa non devono comparire come audio; i riferimenti devono andare ai momenti giusti.
6. Chiudere/riaprire il quaderno e ripetere playback. Provare un’interruzione e scollegamento cuffie in una sessione di test.

- [ ] Audio ascoltabile dopo riavvio, durata e segmenti coerenti.
- [ ] Anchor collegati ai tratti nuovi; nessun timestamp retroattivo sui vecchi tratti.
- [ ] Interruzioni esplicite e ripresa solo su comando dell’utente.
- [ ] Drift misurato con una sorgente nota. Non usare la sola UI del timer come prova di precisione.

La mappatura attuale è un elenco di momenti della pagina; non è implementato un hit test diretto affidabile di ogni tratto copiato/trasformato.

## OCR, Speech e studio

- [ ] **Riconosci testo pagina** su grafia e testo stampato, poi cercare una parola nel documento.
- [ ] **Riconosci un’area**: selezionare un rettangolo e verificare il testo ottenuto.
- [ ] Aggiungere la capability **Riconoscimento vocale** al progetto Swift Playground; trascrivere una registrazione conclusa in italiano.
- [ ] Se la lingua/modello offline manca, errore esplicito; nessun fallback remoto implicito.
- [ ] Cercare testo trascritto e riprodurre il minuto associato.
- [ ] Attivare ricerca per significato e provare parafrasi in italiano. Se il modello del sistema manca, errore esplicito e possibilità di tornare alla ricerca testuale.
- [ ] Pannello **Studia**: modalità locale, sintesi, schema, completamenti e riferimenti. Frasi provenienti dalle fonti, senza contenuti inventati.
- [ ] Ripetere per una cartella con sottocartelle; chiudere/riaprire e ritrovare l’ultimo artefatto.
- [ ] AI remota da provare solo con backend reale e consenso: non configurata nella consegna.

## Robustezza e accessibilità

- [ ] Portrait/landscape, Split View, dark mode, Dynamic Type e VoiceOver.
- [ ] Operazioni ripetute senza crescita incontrollata di memoria; documenti grandi, disco quasi pieno, permessi negati.
- [ ] Test di interruzione in un quaderno di prova: il recupero conserva l’ultima revisione valida e segnala eventuali errori, senza reset.
- [ ] Prima di dati importanti: backup dell’intero container e prove di ripristino, che non sono ancora automatizzate dalla UI.

## Verbale

```text
Versione progetto / Swift Playground:
iPadOS:
Esito compilazione:
Otto controlli incorporati:
Scrittura e riavvio:
PDF e rotazioni:
Audio e tempi:
OCR / Speech / studio:
Errori con nome file e messaggio completo:
```
