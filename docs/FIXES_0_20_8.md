# NeuralNotes 0.20.8 / build 44 — verifica reale dello ZIP App Playground

23 ottobre 2026. L'utente segnala che Playgrounds continua a fermarsi durante la compilazione. Non è disponibile un nuovo log fisico dell'iPad: non si attribuisce il problema a memoria, cache o lentezza del dispositivo senza evidenze.

## Errore riprodotto

Il nuovo job `playground` del workflow `verify.yml`, avviabile con `scope=playground`, genera lo ZIP, lo estrae in una cartella nuova `.swiftpm` e invoca `xcodebuild` su quel pacchetto. Non usa `NeuralNotes.xcodeproj` e non riscrive i sorgenti o il manifest per adattarli alla prova.

La prima esecuzione [39940980908](https://github.com/sminikiller/NeuralNotes/actions/runs/39940980908), commit `2d622f6`, riproduce un errore nel pacchetto della 0.20.7:

```
None of the input catalogs contained a matching stickers icon set or app icon set named "__PlaceholderAppIcon".
```

La soluzione dell'icona libro nelle 0.20.6/0.20.7 era quindi insufficiente. Il compilatore richiede l'icona generata ma non la trova. Il risultato del progetto Xcode separato non copriva questo percorso.

## Correzione

Il prodotto torna a `appIcon: .asset("AppIcon")`, con il catalogo personalizzato già alla radice del target App Playground. Non dipende più dalla generazione di `__PlaceholderAppIcon`. I file dell'icona RGB opaca restano invariati. Versione 0.20.8/build 44 per distinguere l'archivio dalle consegne precedenti.

Il test CI conserva il log, l'elenco degli schemi e lo ZIP che ha effettivamente compilato; abilita anche avvisi sulle espressioni/funzioni Swift lente da verificare. La modalità mirata non ripete la suite generale, rimasta con sei test falliti: non ne nasconde o cambia i risultati. Il job App Playground è incluso anche nelle future verifiche complete.

## Espressioni lente misurate

La prima build riuscita del pacchetto mostra due espressioni geometriche da circa sei secondi e un corpo SwiftUI della ricerca globale da circa sei secondi sul Mac runner. Non è una misura dei tempi sull'iPad e non prova da sola la causa del blocco fisico. Per contenere il lavoro del type checker:

- `PreciseStrokeGeometry.path`: minimi, dimensioni e rettangolo sono calcolati in passi con tipi Double espliciti; la funzione completa richiedeva circa 12 secondi.
- `SearchHighlightOverlay.update`: la catena match/flatMap/map/CGRect diventa cicli con conversioni esplicite CGFloat/Double e accumulatore tipizzato; ordine e coordinate restano gli stessi.
- `GlobalSearchPanel`: preferenze, indice, filtri, risultati e righe separati in viste opache; il comportamento della ricerca non cambia.

Non sono state aggiunte o rimosse funzionalità per ridurre il pacchetto. La compilazione dei tre refactor viene verificata di nuovo nello stesso job App Playground.

## Stato della verifica

Seconda esecuzione [39941386458](https://github.com/sminikiller/NeuralNotes/actions/runs/39941386458), commit `c1cbb55`: **success**, `BUILD SUCCEEDED`. Il manifest AppleProductTypes e i target dello ZIP con icona personalizzata compilano con Xcode 16.4 per simulatore iOS, arm64 e x86_64. Non è la build del progetto Xcode separato.

Terza esecuzione [39942124235](https://github.com/sminikiller/NeuralNotes/actions/runs/39942124235), commit `516f45d`: **success**, `BUILD SUCCEEDED`, con le semplificazioni del type checker, per arm64 e x86_64 del simulatore iOS. I tre punti modificati non compaiono più fra gli avvisi oltre 500 ms per espressione / 1.000 ms per funzione. Questo confronto non è un benchmark completo né un tempo misurato sull'iPad; restano altri avvisi fra circa 0,5 e 1,5 secondi.

Lo ZIP consegnato viene scaricato dall'artefatto `playground-validation-39942124235`, anziché sostituito da una rigenerazione Windows. Controllati hash contro il log, integrità ZIP, insieme dei file e contenuti rispetto ai sorgenti locali (normalizzando soltanto CRLF/LF dei file di testo tra Windows e macOS):

- `NeuralNotes-iPad-0.20.8.zip`, 500.143 byte, 225 sorgenti/risorse più manifest.
- SHA-256: `f00a3fb9d6216dad5febe233bdecf4d3fa0c64edcbc1a54b450d723b5afc8eba`.

Sono passati anche controlli locali di grafo, membership, grammatica Swift e sintassi dello script Bash. Nessuna modifica Core, backend o schema dati in questo intervento; non ripetute le suite generali già eseguite nel commit `5efb2b3`.

Una build del manifest App Playground con Xcode è una verifica aggiuntiva concreta, non una prova del compilatore fisico di Swift Playgrounds sull'iPad 10. I sei fallimenti unit/UI della run generale `39879092836` restano aperti; nessuna registrazione fisica di ore o chiamata AI reale viene dichiarata verificata da questa correzione.
