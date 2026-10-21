# Contratto del backend AI — non ancora distribuito

Il progetto contiene il client e un [server Node con adapter Responses](../backend/README.md). Il server ha 19 test locali superati; nessuna chiave, account, modello o endpoint di produzione è stato configurato. Nessuna chiamata provider è stata eseguita per la consegna. La sintesi estrattiva locale funziona senza questo servizio.

## Endpoint e autenticazione

L’utente configura un endpoint **HTTPS completo**, ad esempio `https://backend.example/v1/study`, e un token di sessione emesso dal proprio backend. Il token in app è salvato in Keychain; le API key del provider devono rimanere esclusivamente sul server. Il client usa POST JSON, timeout di 90 secondi, sessione effimera senza cookie/cache e rifiuta redirect. Invio solo dopo consenso esplicito nel pannello.

Esempio di richiesta strutturale, non una chiamata eseguita:

```json
{
  "task": "summarize",
  "question": "Riassumi gli argomenti principali",
  "sources": [{
    "text": "Testo estratto da una pagina selezionata.",
    "reference": {
      "documentID": "FD239531-F333-4729-AB61-AE54E4BA1A11",
      "pageID": "06BEBEC2-7615-4666-A313-C285EE1E3AF0",
      "pageRevision": 4
    }
  }]
}
```

Task supportati dal contratto: `summarize`, `outline`, `flashcards`, `quiz`, `chat`, `compare`. Gli attuali chunk possono riferirsi a pagina/revisione oppure a `audioSessionID`/`seconds`. Il pannello Studio seleziona fino a 40 estratti tramite retrieval lessicale o, se abilitato e disponibile, embedding locale; senza domanda li distribuisce lungo l’intero indice. Il budget è di 80.000 unità UTF-16, fino a 8.000 per estratto, senza spezzare i caratteri Unicode. Non equivale a leggere integralmente un documento grande. Non invia PDF, immagini o audio binari a questo endpoint: OCR/trascrizione devono essere eseguiti prima.

Le risposte strutturate per definizioni e quiz hanno endpoint separati `/v1/lookup` e `/v1/quiz`, descritti nel README del backend. Il quiz interattivo usa `QuizBank`; il vecchio task `quiz` di study produce invece un’elaborazione testuale.

Risposta HTTP 200 conforme a `AIArtifact`:

```json
{
  "id": "A2121C11-53C6-4F17-B103-A5E30E0E433A",
  "text": "Testo prodotto dal provider con riferimenti alle fonti.",
  "references": [{
    "documentID": "FD239531-F333-4729-AB61-AE54E4BA1A11",
    "pageID": "06BEBEC2-7615-4666-A313-C285EE1E3AF0",
    "pageRevision": 4
  }],
  "provider": "identificativo-provider-e-modello-reale",
  "createdAt": "2026-10-19T19:00:00Z",
  "task": "summarize"
}
```

Date ISO8601, UUID validi. I riferimenti devono essere copie esatte di quelli ricevuti: il client rifiuta fonti inventate. Questo vincolo non valuta da solo se ogni frase sia sostenuta dalla fonte. Dimensione massima accettata della risposta: 2 MB. Errori HTTP diversi da 200 mostrano un errore senza simulare un risultato.

## Requisiti per un’implementazione reale

- Autenticazione, token a scadenza/revoca, isolamento utenti e controllo accesso ai job.
- Adapter di provider intercambiabili; nomi/versioni reali in output, cancellazione e gestione esplicita di timeout/errori/quote.
- Credenziali da secret manager server; nessun provider secret nell’app o nei log.
- Limiti richieste/byte/costi e rate limiting per utente; cifratura TLS verificata.
- Fonti trattate come dati non attendibili, separate dalle istruzioni al modello; validazione delle citazioni lato server e client.
- Consenso, retention, cancellazione dati e policy sui log definiti prima dell’uso reale.
- Valutazioni su grounding, qualità delle sintesi, retrieval, ragionamento e citazioni pagina/minuto. Test su errori, cancellazione e provider indisponibile.

Il server fornito non risponde con testo fisso: il percorso normale richiede un provider Responses e ne valida l’output. I transport di prova esistono solo nei test. Generazione live, hosting HTTPS e credenziali rimangono da configurare e verificare. Limiti del backend personale, quote in memoria e token HMAC documentati nel suo README.
