# NeuralNotes 0.9.1 — build 19: trascrizione delle registrazioni lunghe

## Cosa è cambiato

**Il problema.** Con una registrazione di 2 ore la trascrizione si fermava al blocco 1 e terminava senza testo. Per le registrazioni più lunghe di 45 secondi, ogni blocco veniva prima convertito in un file m4a e poi riconosciuto. Il primo errore fermava tutto: per esempio il silenzio iniziale della lezione, che Apple Speech segnala come errore "No speech detected" invece che come testo vuoto. Le registrazioni brevi di prova saltavano la conversione, per questo sembravano funzionare.

**Ora:**

- **Lettura diretta.** Ogni blocco viene letto dal file della registrazione in buffer audio, senza conversione né file temporanei. La conversione m4a resta come secondo tentativo indipendente.
- **Silenzio.** Il silenzio diventa un blocco vuoto, non un errore.
- **Errori.** Un blocco che fallisce viene saltato e resta da riprovare: a fine lavoro compare "conclusa con N blocchi da riprovare", e "Riprendi trascrizione" rifà solo quelli. La trascrizione si ferma solo dopo tre blocchi falliti di fila, oppure per problemi che riguardano tutti i blocchi (permesso negato, modello italiano assente).
- **Spazio.** Le parole vengono salvate raggruppate in frasi brevi, mai oltre il minuto. Il catalogo del quaderno resta piccolo anche con ore di audio, e lettore, correzioni ed export restano per minuto come prima.
- **Punteggiatura** automatica nel testo riconosciuto.
- **Schermo acceso** durante la trascrizione, ripristinato alla fine.
- **Diagnosi.** In Audio, sotto ogni registrazione, "Diagnosi trascrizione" contiene "Prova il primo blocco" e il registro dei blocchi (metodo, secondi, caratteri, memoria libera, errore). Il registro è anche in "Verifica sul dispositivo". Non contiene il testo trascritto.

## Prova sull'iPad

1. **Prima di aprire la nuova copia:** conserva il vecchio Playground ed esporta i quaderni importanti (Azioni › Esporta › Quaderno nativo e backup). Apri `NeuralNotes-iPad-0.9.1.zip` in una cartella separata e importa il quaderno con la registrazione lunga.
2. **Verifica sul dispositivo:** 27 controlli, compreso "Audio: lettura diretta dei blocchi, senza conversione".
3. **Prova rapida:** Audio › registrazione lunga › Diagnosi trascrizione › **Prova il primo blocco**. Risultati attesi:
   - "Prova riuscita (lettura diretta…)" con un estratto del testo;
   - oppure "nessuna voce nei primi 45 secondi".

   Se compare "Prova non riuscita", mandami il messaggio completo.
4. **Trascrizione completa:** premi Trascrivi. La barra deve superare il blocco 1; 2 ore sono 160 blocchi. Annota quanto dura sull'iPad 10. Tieni l'app in primo piano: lo schermo resta acceso da solo.
5. **Blocchi mancati:** se a fine lavoro alcuni blocchi risultano da riprovare, premi Riprendi. Devono essere rifatti solo quelli.
6. **Risultato:** Visualizza trascrizione, Rinomina / correggi ed Esporta testo devono funzionare come prima, ora con la punteggiatura.
7. **Se qualcosa non va:** Diagnosi trascrizione › Condividi registro, e mandamelo.

## Limiti

- Il riconoscimento resta Apple Speech sul dispositivo: qualità e velocità sull'iPad 10 vanno misurate.
- La trascrizione lunga nativa (`SpeechAnalyzer`) arriverà con l'SDK nuovo (lotto 8).
- I test automatici simulano 160 blocchi con un riconoscitore di prova e verificano la lettura dei frame da file CAF reali. Non provano Apple Speech, che il simulatore non esegue.
- Il registro conserva gli ultimi 200 blocchi nella cache dell'app, che il sistema può svuotare.
