# Patch 0.17.1/build 32 — spazio del foglio

La foto dell’utente del 22 ottobre 2026 documenta una regressione visiva reale nella 0.17.0: la barra con i numeri delle pagine occupa quasi metà dell’editor e comprime il foglio. I controlli sintattici precedenti non verificavano il layout SwiftUI; non avevano rilevato questo difetto.

## Causa e correzione

Nel commit 86ea5e7 il contenitore dei numeri è passato da HStack a LazyHStack per evitare di costruire subito centinaia di pulsanti. La ScrollView orizzontale non aveva un limite di altezza. Con la pila lazy, la barra poteva accettare una grande parte dell’altezza proposta dalla VStack principale.

La ScrollView ora ha **altezza esplicita di 56 punti**, compresi i margini verticali di 6 punti per lato; i pulsanti conservano un’area di almeno 44 punti. Il foglio dispone dell’altezza restante dell’editor. I pulsanti continuano a essere creati in modo lazy e la barra scorre orizzontalmente. I controlli della toolbar rimangono in overlay sul foglio. Nessuna modifica a zoom, file, quaderni o codice backend in questa patch.

## Verifiche

- Predisposto `testPageStripStaysCompactAndLeavesTheRemainingHeightToTheCanvas`: apre l’editor, crea sei pagine, passa da orizzontale a verticale e verifica barra a 56 punti, contiguità con il canvas e altezza del canvas superiore al 65% dello schermo. Verifica anche l’altezza minima dei pulsanti. **Non eseguito con Apple.**
- Generatore e controllo strutturale: 410 oggetti, 259 sorgenti Swift, 322 metodi XCTest presenti; grammatica Swift verificata.
- Parsing del compilatore Swift 6.1.2 in modalità Swift 5 sui sorgenti nativi: riuscito. È parsing, non type checking UIKit, rendering o una build Apple.
- ZIP Playground e sorgenti controllati per integrità, insieme esatto dei file e corrispondenza byte per byte con i sorgenti.
- Core e backend non modificati: non rieseguiti. Restano le evidenze della 0.17.0: 183 Core passati e due skip Darwin, 98 FSRS e 39 backend passati, più controlli PostgreSQL. Non sono prove della correzione del layout.

Il comportamento grafico sull’iPad non è dichiarato verificato da remoto: manca accesso al dispositivo/SDK Apple e l’ultimo tentativo CI documentato resta bloccato dalla fatturazione. La patch rimuove il vincolo mancante identificato nei sorgenti; le prove UI sono pronte per un’esecuzione Apple.

## Pacchetto

Aprire il progetto completo da `NeuralNotes-iPad-0.17.1.zip`. Conservare la copia precedente del Playground e i relativi dati: copie differenti possono usare contenitori differenti. Non eliminare i dati dell’app per aggiornare. [Istruzioni](IPAD.md).

Le correzioni precedenti di cestino, righello, prima presentazione della foto e testo sono mantenute. Il backend e il [piano AI/community](AI_COMMUNITY_PLAN_0_17.md) sono invariati; questa patch riguarda solo la regressione della barra delle pagine e il suo test UI.
