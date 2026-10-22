# Primo lotto AI gestita — 0.18.0/build 34

Questa versione comprende la correzione della linea della [0.17.2](FIXES_0_17_2.md) e la barra pagine compatta della 0.17.1. Il pacchetto separato 0.17.2 resta disponibile per provare la sola correzione geometrica.

## Implementato

- **Accesso email nell’app:** pagina Account NeuralNotes dentro Connessione AI, invio del codice, verifica, selezione dell’account e uscita da questo dispositivo. Nessuna password o chiave del provider richiesta. Il rinvio mostra un conto alla rovescia di 60 secondi.
- **Configurazione gestita:** l’app legge `/v1/config` dal gateway e accetta soltanto configurazione HTTPS, versione riconosciuta, chiave pubblica publishable/anon e origine Auth senza credenziali o query. Rifiuta una service role. L’indirizzo può essere incorporato dallo sviluppatore nella build.
- **Sessione nel portachiavi:** access e refresh token sono salvati insieme, con accessibilità AfterFirstUnlockThisDeviceOnly. Un solo rinnovo per richieste simultanee. Le credenziali ruotate vengono conservate anche se il richiedente smette di attendere; uscita o cambio servizio invalidano i lavori sospesi. Un errore temporaneo non distrugge la sessione, un rinnovo revocato la rimuove.
- **Azioni collegate:** chat/spiegazioni progressive, elaborazioni di studio, definizioni, quiz e ricerca web usano la medesima autorizzazione rinnovabile. Non c’è più necessità di incollare un token manuale con un account gestito. Restano le connessioni API personali preesistenti, facoltative.
- **Consenso e cache per account:** la scelta di invio viene ricordata per account e destinazione. La cache di chat/ricerca include l’identità dell’account; una risposta finale non viene accettata se l’account è cambiato nel frattempo. La cronologia del quaderno resta contenuto locale: il login non la cancella e non trasforma questa build in un sistema di librerie locali separate per utente.
- **Lente rapida:** un gesto intenzionale con lo strumento Lente può avviare la spiegazione nel popup dopo lettura/OCR della selezione, se account e consenso sono già attivi. Le sottolineature fatte con la penna normale non avviano chiamate. Le azioni web restano esplicite e mostrano fonti. Stop, cambio selezione, pagina o configurazione impediscono di mostrare/salvare un risultato appartenente alla selezione precedente. L’inserimento della risposta nel foglio resta annullabile.

Il flusso email usa OTP e verifica di tipo email; il servizio deve configurare il template per mostrare il codice. Il contratto è verificato sulla [guida Supabase per email OTP](https://supabase.com/docs/guides/auth/auth-email-passwordless) e sul [contratto REST Auth per il rinnovo](https://supabase.github.io/auth/). Non sono state inviate email reali durante lo sviluppo.

## Stato del pacchetto e attivazione server

**Nessun servizio online è stato pubblicato, nessuna chiave provider è disponibile nella build e nessuna chiamata AI a pagamento è stata eseguita.** Senza indirizzo il pannello lo dichiara e non abilita l’invio del codice. Non viene presentata una risposta locale come se provenisse da DeepSeek.

Per una build distribuita, lo sviluppatore imposta `NeuralNotesServiceURL` con l’origine HTTPS del gateway (eventuale prefisso compreso) in `NeuralNotes/Resources/Info.plist` per Xcode e `NeuralNotes/App/PlaygroundInfo.plist` per Playground. Il client aggiunge `/v1/study` e scopre `/v1/config`. Non inserire chiavi provider nei plist. In sviluppo è disponibile una sezione avanzata con l’endpoint completo `/v1/study`; non è necessaria nella build con indirizzo incorporato.

Il gateway 0.4 deve avere Supabase Auth configurato, email OTP/SMTP e template del codice operativi, limiti/CAPTCHA valutati per l’ambiente reale, schema/RLS applicati e provider DeepSeek attivo con budget. La gestione CAPTCHA non è implementata nel client di questo lotto: se obbligatoria, il flusso va completato prima del rilascio pubblico. [Variabili e configurazione server](../backend/ENVIRONMENT.md). In nessun caso usare la service role come chiave pubblica.

Flusso utente previsto: Lente → Connessione AI → Accedi o gestisci account → email e codice → Usa questo account → consenso e Salva. Dopo il primo collegamento, le azioni AI non richiedono una configurazione del modello o token personali. Il primo collegamento deve ancora essere provato contro il servizio ospitato e sull’iPad.

## Test eseguiti e limiti

**199 XCTest Core: 197 passati, due skip Darwin preesistenti, zero fallimenti; 98 FSRS passati** su Swift 6.1.2 Linux. Dieci nuovi test gestiti coprono:

- configurazione/prefisso URL e rifiuto di destinazioni o chiavi non ammesse;
- contratti OTP/rinnovo/uscita e validazione locale di email/codice;
- salvataggio, ripristino al riavvio e vincolo al servizio;
- dodici richieste concorrenti con un solo rinnovo;
- uscita durante rinnovo o verifica del codice, senza ricomparsa delle credenziali;
- revoca rispetto a indisponibilità temporanea, identità inattesa e output non valido;
- errore di persistenza e cache separata per account.

I trasporti e il contenitore delle credenziali sono fixture dichiarate. Non sono prove di invio email, Keychain reale, qualità/latenza DeepSeek o servizio Supabase ospitato. Il backend è invariato e non viene dichiarata una nuova esecuzione delle sue 39 prove precedenti.

Grafo 418 oggetti / 264 Swift / 337 metodi XCTest presenti; grammatica e parsing Swift 5 verificati. Nuovo test UI della schermata account senza servizio, predisposto ma **non eseguito**. Compilazione SDK Apple, UI fisica e portachiavi del dispositivo restano da verificare; il blocco CI già documentato non è stato aggirato.

## Prossimi lotti

Questo è l’inizio dell’integrazione, non il completamento di tutte le funzioni AI: restano attivazione HTTPS e prova end-to-end, accesso Apple, indicazione consumi/quote, abbonamenti verificati, migliori risposte su intere lezioni lunghe e valutazioni di qualità su materiali reali. Community, coda cloud e conflitti su due dispositivi restano i lotti separati descritti nel [piano](AI_COMMUNITY_PLAN_0_17.md). Nessun documento viene sincronizzato o pubblicato automaticamente da questo accesso.
