# NeuralNotes 0.21.0 / build 45

## Cambiamenti consegnati

- Cambio pagina: pulizia sincronizzata delle bitmap e dei livelli di disegno, replay, ricerca e selezione; rifiuto delle anteprime asincrone obsolete. Una prova verifica il passaggio a un foglio vuoto e il ritorno al contenuto originale. La segnalazione fisica sull’iPad dell’utente non è stata riprodotta direttamente.
- Account nella libreria: accesso email, nome, consumi, esportazione JSON paginata e cancellazione con conferma email. La cancellazione online procede a gruppi di 100 file e riprende dopo interruzione; rimuove gli oggetti tramite Storage API prima di eliminare metadata/Auth. I materiali di altri autori sono protetti. Quaderni locali e copie del separato account Apple restano conservati.
- Backup via account: code, archivi e revisioni isolati per utente e gateway, identità vincolata per tutta l’operazione, controlli dopo gli await. Azioni rimaste aperte dopo un cambio account si fermano. I file nuovi vengono pubblicati nella coda prima di rimuovere quelli sostituiti. Le vecchie code senza proprietario restano conservate e non vengono assegnate al successivo accesso.
- iCloud: checkpoint distinti per account Apple, invalidazione di database/cache/conflitti al cambio utente e controlli prima di salvare o installare una copia scaricata. Configurazione e prova con un account Apple reale ancora aperte.
- Conflitti server: sostituito l’errore SQL `40001`, che causava ritentativi di PostgREST fino al timeout, con un conflitto semantico `PT409` immediato. Aggiunti readiness del contratto SQL e migrazioni versionate.
- Esportazione della trascrizione: sostituito `ShareLink`, che in una ripetizione tornava all’elenco senza aprire Condividi. Un pulsante prepara il file fuori dal thread UI e apre la condivisione tramite l’unico stato dei pannelli audio; cancellazione e chiusura rimuovono il temporaneo. Lettura, rinomina e condivisione restano azioni distinte.

## Verifiche ed evidenze

I risultati si riferiscono alle piattaforme e alle revisioni indicate; non sono una certificazione fisica dell’iPad.

| Verifica | Risultato |
| --- | --- |
| Core macOS | 265 XCTest e 98 FSRS passati nelle esecuzioni complete e mirate. |
| Suite completa simulatore, `90d8e4b` | 389 test nativi: due esclusioni per piattaforma e un errore nella nuova fixture account, poi corretto. 24 UI: un’intermittenza nella condivisione, poi corretta nel prodotto. Gli altri test passati. Build Release riuscita. |
| Verifica mirata `d637cad` | Tutti i 26 test EditorReliability passati, compresi cambio pagina e cambi di account durante un upload. Archiviazione/ripristino, modifica e lettura audio passati; la ripetizione dell’export ha fatto emergere l’intermittenza sopra descritta. |
| Verifica finale `da50c43` | PASS: 265 Core, 98 FSRS, tutti i 26 test di affidabilità e i quattro UI audio, senza fallimenti; `TEST SUCCEEDED` e `BUILD SUCCEEDED` per Release. Le sei verifiche fallite inizialmente hanno ora esiti positivi; l’intermittenza dell’export è stata riprodotta prima della sostituzione di ShareLink. |
| Pacchetto App Playground finale | Compilato realmente dallo ZIP, Xcode 16.4 / SDK simulatore iOS 18.5, architetture arm64/x86_64. |
| Backend | 53 test Node; SQL reale per RLS/quote/CAS/cancellazione/trasferimento gruppi; integrazione locale GoTrue, SMTP Mailpit, PostgreSQL, PostgREST e Storage API reali: PASS. Il provider AI è una fixture esplicita. |
| Aggiornamento del binario | 0.20.8 → `90d8e4b` sul simulatore senza disinstallazione/reset: indice SwiftData, manifest, catalogo e trascrizione di controllo conservati e identici. Le successive modifiche al prodotto riguardano solo l’esportazione audio. |
| Audio di sei ore | File PCM sintetico realmente leggibile a finestre, checkpoint dopo interruzione, ripresa, correzioni ed export con timestamp: PASS sul simulatore. Riconoscimento simulato; non è una registrazione hardware di sei ore. |

[Suite completa, servizi e aggiornamento](https://github.com/sminikiller/NeuralNotes/actions/runs/39973557986), [verifica delle fixture e dei flussi audio](https://github.com/sminikiller/NeuralNotes/actions/runs/39979979036), [pacchetto e correzione finale dell’export](https://github.com/sminikiller/NeuralNotes/actions/runs/39982456433). La verifica mirata ripete le classi interessate: non viene presentata come una nuova esecuzione di tutti i test UI dopo modifiche limitate a quei percorsi.

Archivio consegnato: `NeuralNotes-iPad-0.21.0.zip`, scaricato dalla CI, **505.668 byte / 226 file**. SHA-256:

```text
4c3b78cf8d1c9c6f4d8faa7d3a8e4cb4660e9c78e2094d071791e5cd11401feb
```

Verificati CRC, elenco esatto dei file e corrispondenza con i sorgenti: normalizzazione LF/CRLF solo per i testi, confronto binario esatto delle risorse. Non rigenerare l’archivio e attribuirgli le evidenze di quello compilato.

## Servizi pubblici e prove ancora aperte

Supabase e Render non risultano collegati; non sono presenti endpoint operativi o chiavi del provider nella configurazione del progetto/segreti GitHub. Anche l’inventario delle eventuali sessioni web non è stato accessibile: lo strumento di controllo non inizializza il runtime. Nessun gateway o progetto cloud è stato pubblicato, nessuna chiave generata e nessuna inferenza a pagamento eseguita. Il pannello mostra esplicitamente il servizio non configurato. Le istruzioni pronte per la pubblicazione sono in [backend/ACTIVATION.md](../backend/ACTIVATION.md).

Ricontrollate il 23 ottobre le API ufficiali per il modello [DeepSeek Flash](https://api-docs.deepseek.com/updates/) e la [ricerca `/v1/tools/search`](https://api-docs.deepseek.com/api/search/): la configurazione e il percorso implementati sono coerenti con i riferimenti attuali. Questo controllo documentale non sostituisce una chiamata con chiave reale o la validazione della qualità delle risposte italiane e delle citazioni.

Il cloud via account conserva copie e revisioni con conflitti espliciti, fino a **100 MiB per oggetto**; non è ancora una replica automatica bidirezionale completa della libreria. iCloud usa chunk e una politica a tre vie, ma restano configurazione del contenitore firmato e prova su due dispositivi. Sincronizzazione di cartelle/cestini e garbage collection completa delle vecchie copie restano lavori distinti. I piani economici restano proposte, senza abbonamenti attivati.

Registrazione hardware prolungata, standby, fotocamera/scanner, Keychain fisico e aggiornamento del contenitore Swift Playgrounds non sono stati provati sul suo iPad. La prova di aggiornamento usa un quaderno di controllo con trascrizione; non certifica tutti i documenti reali dell’utente. Nessun documento dell’utente è stato eliminato o migrato in questa sessione. Conservare progetto precedente e backup durante le prove della nuova versione.
