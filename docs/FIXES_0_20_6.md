# NeuralNotes 0.20.6 / build 42 — errore AppIcon nel pacchetto iPad

23 ottobre 2026. La schermata mostra `None of the input catalogs contained a matching stickers icon set, app icon set, or icon stack named "AppIcon"`. È un errore del compilatore degli asset. La riduzione delle espressioni SwiftUI della 0.20.5 non interviene su questo errore; il timeout era soltanto un'ipotesi.

## Diagnosi e correzione

Lo ZIP precedente contiene realmente `Resources/Assets.xcassets/AppIcon.appiconset` e il PNG RGB da 1024 pixel. La sola presenza dei file non dimostra che il catalogo venga passato correttamente al compilatore dell'app in Playgrounds. Non disponiamo del comando actool completo per stabilire perché il catalogo non viene riconosciuto in quell'ambiente.

- Il prodotto App Playground usa ora `appIcon: .placeholder(icon: .openBook)`. È una scelta intenzionale: Playgrounds genera l'icona libro e non deve risolvere il nome AppIcon nel nostro catalogo. L'icona personalizzata resta disponibile nel progetto Xcode.
- Il catalogo originale viene copiato, senza cambiare i suoi byte, in `NeuralNotes.swiftpm/Assets.xcassets` alla radice del target AppModule e dichiarato con una regola `.process("Assets.xcassets")` dedicata.
- Privacy manifest, avvisi delle dipendenze e risorsa entitlements hanno regole distinte. Non si applica più la regola generica ricorsiva all'intera cartella Resources. Questa separazione rende espliciti gli input; non costituisce la prova che le cartelle annidate siano sempre invalide.
- Nessun cambiamento ai file Swift, all'identità del prodotto, ai modelli dei quaderni, ai permessi o alle richieste AI. La risorsa entitlements rimane una risorsa come nelle versioni precedenti: copiarla non firma l'app né attiva servizi Apple aggiuntivi.

Apple documenta l'elaborazione dei cataloghi e le regole delle risorse in [Bundling resources with a Swift package](https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package); il formato dell'icona personalizzata rimane quello illustrato in [Configuring your app icon using an asset catalog](https://developer.apple.com/documentation/xcode/configuring-your-app-icon). La dichiarazione AppleProductTypes del libro è illustrata anche nel [progetto sorgente App Playground](https://github.com/alemohamad/swift-playground-app-structure).

## Verifiche e limiti

Il controllo del pacchetto verifica l'icona generata nel manifest, l'assenza del riferimento `.asset` nel prodotto, la regola dedicata al catalogo, la presenza dei file immagine referenziati, AccentColor, l'unico punto di ingresso e la corrispondenza byte per byte dei file dello ZIP con i sorgenti. Il controllo del progetto verifica anche grafo, membership, PNG e plist.

Questi sono controlli di configurazione e integrità, non l'esecuzione di actool. Mancano SDK Apple e accesso a Playgrounds su iPad: nessuna build Apple o prova sul dispositivo dichiarata. Core e backend sono invariati e non sono stati rieseguiti. La CI resta bloccata per fatturazione come già documentato; non è il motivo dell'errore AppIcon mostrato nella foto.

## Uso del pacchetto

Decomprimere `NeuralNotes-iPad-0.20.6.zip` in una nuova cartella e aprire l'intero `NeuralNotes.swiftpm`. Non sovrapporre il pacchetto a una vecchia cartella aperta in Playgrounds. Conservare il vecchio progetto e gli export: non serve eliminare i dati dell'app per correggere questa configurazione.
