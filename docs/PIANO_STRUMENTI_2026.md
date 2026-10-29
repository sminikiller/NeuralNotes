# Prompt per Codex — NeuralNotes: strumenti di scrittura "livello Goodnotes 2026" e schermata Crediti

> **Come usarlo:** copia tutto questo testo e incollalo a Codex. È un piano completo e va eseguito **una fase alla volta**: ogni fase è una versione, da verificare e consegnare prima di passare alla successiva.

---

Ciao Codex. Ti chiedo di implementare in NeuralNotes (repository `sminikiller/NeuralNotes`, ramo `codex/photo-perspective-sync-center`) gli strumenti di scrittura e di disegno che oggi mancano rispetto alle app migliori, più una schermata **Crediti**.

Il piano nasce da una ricerca su Goodnotes, Notability, OneNote, Apple Notes, Samsung Notes, MyScript e altre app. Copre:
- le novità di Goodnotes da gennaio a settembre 2026;
- le richieste più votate sul forum di Goodnotes;
- un confronto con il codice attuale (0.24.1).

Lavora per fasi, nell'ordine indicato. **Ogni fase diventa una versione** (0.25, 0.26, …), con verifica e consegna come fai di solito.

## 0. Regole valide per tutte le fasi

### 0.1 Prima di iniziare
1. Aggiorna il ramo: `git pull --ff-only origin codex/photo-perspective-sync-center`.
2. Se non l'hai già fatto, completa i punti del messaggio precedente:
   - il test UI dello zoom con doppio tocco è instabile nella suite completa;
   - in `backend/platform/verify.ps1` c'è una gara all'avvio di PostgreSQL.
3. Salva **questo documento così com'è** in `docs/PIANO_STRUMENTI_2026.md`. Tienilo aggiornato con lo stato di ogni punto (✅ fatto, 🟡 in parte, ❌ da fare) e i link alle verifiche.

### 0.2 Da non toccare
- Bundle ID `com.lorenzominichilli.neuralnotes`, container iCloud, team `64R668842U`.
- I segreti `NN_*`, la corsia `testflight` di `verify.yml`, `tools/distribute_macos.sh`, `tools/validate_distribution_profile.py`.
- Non creare né chiedere certificati, profili o chiavi.

### 0.3 Compatibilità dei dati (obbligatoria)
- Ogni campo nuovo nei modelli (`PageSnapshot`, `ShapeElement`, `TextElement`, `ImageElement` …) è **opzionale**. I quaderni e i backup `.nnbackup` creati con le versioni precedenti si aprono identici.
- **Decodifica tollerante:** un valore sconosciuto (per esempio un nuovo `ShapeKind` letto da una versione più vecchia, o da una futura durante la sincronizzazione tra dispositivi) **non deve mai** impedire di aprire la pagina. Saltalo o ripiega su un valore sicuro, con un test dedicato.
- Aggiorna `PageValidation.swift` per ogni campo nuovo:
  - numeri finiti;
  - limiti di dimensione e quantità;
  - ID unici;
  - riferimenti validi (un connettore che punta a un oggetto inesistente diventa "libero", non un errore).
- Per ogni fase aggiungi test con un quaderno di esempio della versione precedente (*fixture*). Il test controlla che apertura, salvataggio, export PDF e backup nativo funzionino.

### 0.4 Annulla e ripristina
Ogni azione nuova (crea, modifica, sposta, cambia stile, aggancia, livelli, riconoscimento, operazioni sulla grafia, eliminazioni) si annulla e si ripristina in **un solo passo**, con la cronologia esistente (`EditHistory` / `EditorHistory.swift`). Per le azioni su più pagine usa il meccanismo già presente per le operazioni tra pagine.

### 0.5 Prestazioni e leggerezza
- Riconoscimento delle forme al rilascio della penna: **meno di 16 ms** sul thread principale, oppure in un'attività in sottofondo con risultato annullabile.
- Aggancio durante il trascinamento: 60 fps con almeno 200 oggetti sulla pagina. Calcola i candidati all'inizio del trascinamento e usa una suddivisione spaziale oltre i 200 oggetti.
- Nessuna dipendenza nuova.
- **Compilazione leggera:** Swift Playgrounds sull'iPad 10 soffre con le build pesanti, e "Build failed" senza errori è già successo.
  - File piccoli, con un compito ciascuno.
  - Niente viste SwiftUI enormi, niente espressioni lunghe con molti operatori (inferenza di tipo costosa).
  - Geometria e logica nel modulo Core, con funzioni pure testabili.
- Le API nuove di iOS 26 vanno protette con `#available` e, se serve, `#if compiler(>=6.2)`, come già fa il progetto.

### 0.6 Interfaccia
- Tutto in italiano, con tema scuro, Dynamic Type e VoiceOver (etichette su ogni controllo nuovo).
- Funziona con Apple Pencil e con le dita, quando le dita disegnano.
- Funziona nello scorrimento continuo, a qualsiasi zoom e in "Solo foglio".
- Le preferenze nuove stanno nel **Workspace**, per profilo (`EditorWorkspaces.swift`, `WorkspacePanel.swift`, `WorkspaceSettings.swift`), con valori predefiniti sensati.
- Per ogni funzione aggiorna **Guida e Novità**: `FeatureGuide.swift` (catalogo e tutorial) e `docs/GUIDA_FUNZIONI.md`, con i passi in parole semplici.

### 0.7 Verifica e consegna di ogni fase
1. Versione e build nuove in `tools/generate_project.py`, poi rigenera il progetto.
2. Scrivi `docs/DELIVERY_0_xx.md`: cosa è stato fatto, cosa no, prove eseguite.
3. Test unitari per tutta la geometria (riconoscimento, aggancio, connettori, poligoni, stelle, archi, livelli, trasformazioni della grafia) e test UI dei flussi principali. Nei test UI aspetta **lo stato**, non tempi fissi.
4. Commit con `[skip ci]`, poi verifica completa:
   `gh workflow run verify.yml --ref codex/photo-perspective-sync-center -f scope=delivery -f delivery_upload=false`
5. Se è verde, build TestFlight:
   `gh workflow run verify.yml --ref codex/photo-perspective-sync-center -f scope=testflight -f verified_sha=<commit verificato>`
   Avvia un'esecuzione alla volta: sullo stesso ramo si annullano a vicenda.
6. Alla fine di ogni fase scrivimi un riepilogo in italiano semplice:
   - cosa posso provare sull'iPad, e come;
   - cosa manca;
   - i link alle esecuzioni.

## 1. Ordine delle fasi

| Versione | Contenuto | Sezione |
|---|---|---|
| 0.25 | Schermata Crediti; forme nuove, stili e riconoscimento automatico | §2, §3 |
| 0.26 | Aggancio agli oggetti e alla griglia, guide di allineamento, allinea e distribuisci | §4 |
| 0.27 | Diagrammi rapidi con connettori agganciati alle forme, testo dentro le forme, mappe AI modificabili | §5 |
| 0.28 | Selezione tra pagine (miglioramenti), gomma selettiva per tipo, "Elimina elementi di un tipo", copia come immagine; goniometro e misure | §6 |
| 0.29 | Testo e richieste più votate: pedice e apice, colori per materia, penna calligrafica, evidenziatore rettangolare, finestra di zoom, riproduzione dei tratti, indice comprimibile, strumento testo fisso, scorciatoie e incolla | §7 |
| 0.30 | Livelli veri: mostra e nascondi, blocca, riordina, esporta | §8 |
| 0.31 | Grafia: raddrizza, uniforma, ripulisci, riadatta alla larghezza, spazio tra le righe | §9 |

**Funzioni già presenti** (non rifarle, verifica solo che funzionino):
- tipi di penna (penna, matita, monoline, stilografica, acquerello, pastello);
- gomma parziale, solo evidenziatore, ritorno alla penna, scarabocchio;
- forme da punto a punto (linea, freccia, cerchio, rettangolo, triangolo);
- riconoscimento tenendo ferma la punta (linea, freccia, triangolo, rettangolo, ellisse) e aggancio angolare delle linee (`PreciseLine.swift`);
- righello con aggancio (`RulerGuide.swift`);
- lazo libero e rettangolare con sposta, ruota, ridimensiona e ricolora;
- ordine avanti/indietro e blocco degli oggetti (`PageObjects.swift`);
- converti in testo; testo ricco con elenchi, checklist ed evidenziazione; link automatici (`NSDataDetector`);
- post-it, timbri, nastro di ripasso, puntatore laser;
- gesti con 2 e 3 dita; doppio tocco, squeeze e hover di Pencil; scorciatoie da tastiera (`EditorKeyboard.swift`);
- sposta la selezione in un'altra pagina (`MoveSelection.swift`);
- modelli di pagina, PDF come modello, sezioni annidate, schede;
- riproduzione dell'inchiostro con l'audio (`InkReplayOverlay.swift`).

---

## 2. Schermata Crediti — "Informazioni su NeuralNotes" (0.25)

**Dove si apre:**
- nella libreria, accanto a **Guida e Novità** (`QuickGuidePanel.swift`), con la voce **"Informazioni su NeuralNotes"**;
- dal pannello Account e servizi (`AccountServicesPanel.swift`), con la stessa voce.

**Contenuto, dall'alto in basso:**
1. **Intestazione:**
   - logo (icona dell'app), nome **NeuralNotes** e il motto **"Scrivi, studia, collega e riorganizza le tue idee."**;
   - il logo deve essere l'immagine dell'icona. `AppIcon` non si carica in modo affidabile con `UIImage(named:)`, quindi aggiungi in `tools/generate_project.py` un image set **`AppLogo`** generato dalla **stessa funzione** che produce `AppIcon.png`.
2. **Versione e build** lette in automatico dall'app:
   - `CFBundleShortVersionString` e `CFBundleVersion` dal bundle, per esempio "Versione 1.0.0 (build 121)". Mai scritte a mano;
   - pulsante **"Copia informazioni"**: copia versione, build, versione di iPadOS e modello di iPad, utili per le segnalazioni. Nessun dato personale e nessun contenuto dei quaderni;
   - se possibile mostra un'etichetta "Beta TestFlight" quando l'app arriva da TestFlight. Usa `AppTransaction` di StoreKit dove disponibile e non mostrare niente se non è determinabile. Nel runner di Swift Playgrounds mostra "Swift Playgrounds".
3. **Sviluppo:** "Sviluppata da **Lorenzo Minichilli**".
4. **Ringraziamenti:**
   - testo fisso: "Grazie agli amici e ai compagni che hanno provato le versioni di prova e segnalato problemi e idee.";
   - sotto, un elenco di nomi letto da una risorsa `Credits.json` nel bundle, così i nomi si aggiungono senza toccare il codice;
   - con l'elenco vuoto mostra solo la frase. Crea il file vuoto, con un commento nel DELIVERY su come compilarlo.
5. **Contatti e feedback:**
   - **"Invia un feedback"** e **"Segnala un problema"**: email con oggetto e corpo precompilati (versione, build, iPadOS, modello; niente contenuti dei quaderni), tramite composer di sistema o `mailto:`;
   - l'indirizzo viene da una nuova chiave dell'Info.plist, **`NeuralNotesFeedbackEmail`**, impostata da `tools/configure_service.py` con una nuova opzione `--feedback-email`. Se manca, nascondi le due righe. **Non scrivere indirizzi email nel codice**;
   - in TestFlight aggiungi una riga: "In TestFlight puoi anche fare uno screenshot e toccare Condividi feedback".
6. **Collegamenti:**
   - Assistenza (`NeuralNotesSupportURL`) e Informativa privacy (`NeuralNotesPrivacyURL`), con la stessa funzione `publicLink` di `AccountServicesPanel.swift`. Se non sono configurati, scrivi "Non ancora pubblicata in questa versione", come già fa quel pannello;
   - Guida e Novità.
7. **Privacy in breve.** Poche righe **coerenti con il comportamento reale** e con `PrivacyInfo.xcprivacy`:
   - cosa resta sul dispositivo;
   - cosa viene inviato e quando (motore AI scelto, account e sincronizzazione);
   - link all'informativa completa.

   Non inventare garanzie che il codice non dà.
8. **Licenze:**
   - mostra `NeuralNotes/Resources/ThirdPartyNotices.txt` in una vista scorrevole (per esempio swift-fsrs, licenza MIT);
   - controlla quali componenti di terze parti finiscono davvero nell'app iOS e completa il file se manca qualcosa. Per esempio swift-crypto è nel `Package.swift`: verifica se viene incluso su iOS;
   - i framework Apple non vanno elencati.
9. **Piè di pagina**, in piccolo:
   - "© 2026 Lorenzo Minichilli";
   - "Sviluppata anche grazie al supporto di ChatGPT e Claude.";
   - "I marchi citati appartengono ai rispettivi proprietari."

**Criteri di accettazione:**
- versione e build corrispondono a quelle del bundle, sia nella build TestFlight sia nel runner Playgrounds;
- con link ed email non configurati non compaiono righe rotte;
- VoiceOver legge tutto in ordine;
- la schermata funziona in verticale e orizzontale, chiara e scura.

**Test:**
- formattazione della versione;
- lettura di `Credits.json` (vuoto, con nomi, malformato senza crash);
- righe nascoste senza URL;
- test UI che apre la schermata.

---

## 3. Forme nuove, stili e riconoscimento (0.25)

### 3.1 Nuovi tipi di forma
Aggiungi a `ShapeKind` (`Core/Domain/EditorTools.swift`), con decodifica tollerante:
- **Rombo**.
- **Poligono regolare** da 3 a 12 lati (campo `sides: Int?`).
- **Poligono libero**: vertici liberi, campo `vertices: [ShapeEndpoint]?` normalizzati sul riquadro.
- **Stella** da 4 a 12 punte (`sides`) con rapporto tra raggio interno ed esterno regolabile (`innerRatio: Double?`, da 0,2 a 0,8; predefinito 0,5).
- **Arco** di cerchio: `arcStart: Double?` e `arcSweep: Double?` in radianti, ampiezza da 10° a 350°.

Il quadrato e il cerchio perfetto restano rettangolo ed ellisse, con l'aggancio delle proporzioni (§3.4).

**Strumento Forme** (tieni premuta l'icona, `ToolOptionsPopover.swift` e `EditorQuickToolbar.swift`):
- una griglia con tutte le forme: linea, freccia, rettangolo, rombo, ellisse, triangolo, poligono (stepper dei lati), stella (stepper delle punte e cursore del rapporto), arco;
- **creazione:** trascina da un angolo all'angolo opposto; per linea e freccia, dalla coda alla punta;
- **arco:** trascinando si definisce la corda e nasce un semicerchio; la maniglia centrale regola la curvatura, da quasi piatto a 350°.

**Maniglie di modifica** (`SelectionTransforms.swift`, `ElementEditor.swift`), quando la forma è selezionata con Oggetti o con il lazo:
- angoli per il ridimensionamento e maniglia di rotazione;
- poligono: numero di lati nel menu;
- stella: una maniglia per il raggio interno;
- arco: maniglie per inizio e fine;
- poligono libero: una maniglia per ogni vertice (tieni premuto un lato per aggiungere un vertice, tieni premuto un vertice per toglierlo);
- linea e freccia: maniglie agli estremi.

**Geometria in un solo punto:** una funzione pura (per esempio `ShapeGeometry.path(for:)` in Core) produce il tracciato di ogni forma. La usano:
- il disegno sulla pagina (`ElementRendering.swift`, `PageRenderer.swift`, `VectorInkRenderer.swift`);
- le miniature;
- l'export PDF (`EditorExports.swift`, `DocumentServices.swift`);
- la selezione (tocco sul contorno, con tolleranza di 8 pt a schermo, o dentro la forma se è riempita);
- il riquadro di selezione ruotato.

### 3.2 Stili delle forme
Campi opzionali nuovi su `ShapeElement`:
- `fill: InkColor?` e `fillOpacity: Double?` (da 0 a 1; predefinito 0,25 quando si attiva il riempimento);
- `dash: ShapeDash?` (continuo, tratteggiato, puntinato), con schemi proporzionali allo spessore: tratteggiato [3s, 2s], puntinato [0, 2s] con estremi arrotondati;
- `cornerRadius: Double?` per rettangolo e rombo, da 0 al 50% del lato minore;
- `arrowHeads: ArrowHeads?` (nessuna, fine, inizio, entrambe) e `arrowStyle: ArrowStyle?` (piena o aperta), per freccia, linea, arco e connettori;
- `strokeOpacity: Double?`.

**Pannello "Stile"** nel menu della selezione:
- colore del contorno, riempimento (nessuno, palette, opacità), spessore, tratto, angoli (squadrati o arrotondati, con cursore), punte delle frecce;
- **"Usa come predefinito"**: applica lo stile alle forme nuove, salvato nel Workspace;
- con più forme selezionate, lo stile si applica a tutte.

Le forme nuove nascono con angoli leggermente arrotondati, come le forme dei diagrammi in Goodnotes, se il predefinito non è stato cambiato.

### 3.3 Riconoscimento delle forme: due modalità
Nel Workspace, voce **"Riconoscimento forme"**, con un comando rapido anche nelle opzioni della penna:
- **Spento.**
- **"Tieni ferma la punta"** (esiste già, va estesa): disegni la forma, fermi la punta per circa 0,5 s, compare l'anteprima corretta con una vibrazione leggera, al rilascio la forma viene sostituita. Se la figura è troppo irregolare, resta il tratto.
- **"Automatico al rilascio"** (nuovo): quando sollevi la penna, se il tratto è riconosciuto con alta sicurezza, viene corretto subito senza fermarsi. Compare per 3 secondi un piccolo avviso, **"Corretto in Rettangolo · Annulla"**, che non blocca la scrittura. Un tocco su Annulla, o il gesto di annullare, ripristina il tratto originale.
- **Forme da riconoscere**, attivabili una per una: linee e frecce, cerchi ed ellissi, triangoli, rettangoli e rombi, poligoni, stelle, archi.
- **"Converti in"**: *Forma modificabile* (un `ShapeElement` con colore e spessore della penna e lo stile predefinito, modificabile con le maniglie del §3.1) oppure *Tratto di penna* (un tratto perfetto con lo stesso inchiostro, come oggi con `PreciseStrokeGeometry`).
  - Predefinito: forma modificabile con la penna.
  - Con l'evidenziatore resta sempre tratto, ma diritto.

**Riconoscitore** (`HeldShapeRecognition.swift`, da estendere o affiancare con un `ShapeRecognizer` in Core):
1. **Preparazione:** ricampiona il tratto in 64 punti equidistanti e misura la chiusura (distanza tra inizio e fine diviso il perimetro: sotto 0,12 è chiuso).
2. **Tratti aperti:**
   - **linea** se lo scarto massimo dalla corda è sotto il 4% della lunghezza;
   - **freccia** come oggi;
   - **arco** se un cerchio stimato con i minimi quadrati (metodo di Kasa) ha uno scarto medio sotto il 6% del raggio e un'ampiezza tra 30° e 330°.
3. **Tratti chiusi:**
   - **ellisse o cerchio** con lo stimatore attuale;
   - altrimenti cerca gli angoli: semplificazione Ramer–Douglas–Peucker con tolleranza dal 4 al 6% della dimensione, più una soglia sull'angolo;
   - 3 vertici: **triangolo**;
   - 4 vertici: **rettangolo** (lati entro 8° dagli assi) oppure **rombo** (diagonali entro 8° dagli assi); se no, rettangolo ruotato;
   - da 5 a 12 vertici con lati e angoli simili (coefficiente di variazione sotto 0,18): **poligono regolare**; altrimenti **poligono libero**, solo con la voce "poligoni" attiva;
   - 2n vertici con raggi che alternano interno ed esterno (rapporto tra 0,3 e 0,7): **stella**.
4. **Abbellimento:**
   - quadrato se il rapporto tra i lati è entro il 10%;
   - cerchio se gli assi sono entro il 10%;
   - triangolo equilatero o rettangolo se gli angoli sono entro 8°;
   - rotazione agganciata a 0°, 15°, 30°, 45° e 90° se entro 4°.
5. **Sicurezza:** il riconoscitore restituisce un punteggio da 0 a 1. "Tieni ferma la punta" accetta da 0,6 in su; "Automatico" solo da 0,85 in su, e solo se:
   - la forma misura almeno 24 pt;
   - il tratto non sembra scrittura: tratti brevi e veloci, molti cambi di direzione, vicinanza a righe di testo appena scritte.

   **Meglio non correggere che correggere la scrittura.**
6. **Annulla:** un solo passo riporta il tratto originale. L'ancoraggio audio del tratto (`StrokeAnchor`) passa alla forma o al tratto corretto, così la riproduzione con l'audio resta giusta.

### 3.4 Aggancio durante il disegno delle forme
- Linee, frecce e lato iniziale dei poligoni si agganciano a multipli di 15°, con la vibrazione leggera già usata.
- Rapporto 1:1 (quadrato o cerchio) quando ci si avvicina, con un indicatore visivo.
- Con la griglia attiva (§4) le dimensioni si agganciano alla griglia.
- Gli estremi di linee e frecce si agganciano ai punti di collegamento delle altre forme: base per i connettori del §5.

**Criteri di accettazione 0.25:**
- disegnando a mano libera rettangoli, cerchi, triangoli, rombi, pentagoni, esagoni, stelle a 5 punte e archi, il riconoscimento funziona in entrambe le modalità;
- scrivendo normalmente in modalità automatica, su almeno una pagina di prova scritta a mano, nessuna lettera viene trasformata in forma;
- le forme si modificano con le maniglie e con il pannello Stile; sono identiche a schermo, nelle miniature e nel PDF esportato;
- un quaderno 0.24.1 si apre senza differenze.

**Test:**
- riconoscitore con tratti sintetici (anche rumorosi e ruotati) per ogni tipo, più esempi negativi di scrittura;
- tracciati di poligono, stella, arco e angoli arrotondati;
- decodifica tollerante di `ShapeKind`;
- stile applicato a più forme.

---

## 4. Aggancio agli oggetti e alla griglia, con linee guida (0.26)

Come l'aggancio degli oggetti di Goodnotes (luglio–settembre 2026) e di Notability.

**Cosa fa per l'utente.** Quando sposti, ridimensioni o ruoti qualcosa, l'oggetto si "calamita" agli oggetti vicini e alla griglia, e compaiono **linee guida** sottili che mostrano l'allineamento. Vale per:
- forme, caselle di testo, post-it, immagini e connettori (dalla 0.27);
- selezioni del lazo, compreso l'inchiostro, trattate come un riquadro.

**Riferimenti di aggancio:**
- **Oggetti:** bordi sinistro, centrale e destro; alto, centro e basso. Si considerano gli oggetti visibili, non bloccati, della stessa pagina e dello stesso livello dalla 0.30.
- **Pagina:** bordi, centro e margini (i margini del modello di carta, se ci sono).
- **Spaziatura uguale:** se l'oggetto sta tra due oggetti e le distanze diventano uguali, aggancia e mostra due piccoli segni "=" con la misura.
- **Griglia:**
  - sulle carte a quadretti, puntini, millimetrata e isometrica si usa il loro passo (`PaperStyle`, `PaperPatternRenderer.swift`);
  - sull'isometrica, il reticolo a 60°;
  - sulle altre carte una griglia invisibile da 8 pt, solo se "Aggancio alla griglia" è attivo.
- **Rotazione:** scatti di 15°, più forti a 0°, 90°, 180° e 270° (entro 3°), con la vibrazione leggera.
- **Ridimensionamento:** i bordi si agganciano ai bordi degli altri oggetti. Le proporzioni si bloccano quando sono vicine all'1:1 o se si attiva "Mantieni proporzioni".

**Soglia e disattivazione:**
- la soglia è di 6 pt **a schermo**, convertita in punti pagina in base allo zoom;
- l'aggancio si sospende tenendo un secondo dito appoggiato mentre trascini, o tenendo premuto ⌥ sulla tastiera fisica.

**Linee guida:** 1 px a schermo, colore di sistema in tinta con la selezione, estese per tutta la pagina o tra gli oggetti allineati. Spariscono al rilascio.

**Allinea e distribuisci**, nel menu della selezione con almeno 2 oggetti (3 per distribuire):
- allinea a sinistra, al centro o a destra; in alto, a metà o in basso;
- distribuisci in orizzontale o in verticale;
- uguaglia larghezza o altezza.

**Impostazioni** nel Workspace, voce "Aggancio":
- Agli oggetti (attivo);
- Alla griglia (attivo sulle carte con griglia, spento sulle altre);
- Mostra linee guida (attivo).

**Architettura:**
- un motore puro in Core (per esempio `SnapEngine`): riceve i riquadri ruotati degli altri oggetti, il riquadro in movimento, il tipo di gesto, lo zoom e la griglia; restituisce lo spostamento corretto e le guide da disegnare;
- l'interfaccia (`CanvasInteraction.swift`, `SelectionTransforms.swift`) lo interroga durante il gesto.

**Criteri di accettazione:**
- allineare tre caselle sulla stessa riga e distribuirle si fa in pochi secondi, con le guide visibili;
- con 200 oggetti il trascinamento resta fluido;
- disattivando le opzioni non resta nessun effetto.

**Test** del motore:
- bordi, centri e spaziatura uguale;
- griglia normale e isometrica;
- soglia in base allo zoom;
- oggetti ruotati e bloccati esclusi.

---

## 5. Diagrammi rapidi con connettori (0.27)

Come i Quick Diagramming e i connettori di Goodnotes (aprile–settembre 2026).

### 5.1 Modello
Nuovo `ConnectorElement` in Core, salvato in `PageSnapshot.connectors: [ConnectorElement]?` e incluso in `objectOrder`, `lockedObjects` e, dalla 0.30, nei livelli:
- `from` e `to` (`ConnectorEnd`):
  - `objectID: UUID?`: forma, casella di testo, post-it o immagine;
  - `anchor`: punto normalizzato sul contorno dell'oggetto, prima della rotazione;
  - `x` e `y` assoluti come ripiego quando l'estremo è libero;
- `routing`: dritto, curvo, a gomito;
- `controlPoints` opzionali: la maniglia della curva, i segmenti del gomito;
- colore, spessore, tratto, punte delle frecce (come §3.2);
- `label` opzionale: testo semplice o RTF, come in `TextElement`.

### 5.2 Come si usa
- **Punti di collegamento:** selezionando una sola forma (o casella o post-it) compaiono **4 punti blu** a metà dei lati.
  - **Tocchi un punto:** nasce una **forma uguale** (stesso tipo, stile e dimensione) in quella direzione, a 48 pt di distanza, già collegata. Diventa selezionata, pronta per scriverci dentro.
  - **Trascini da un punto:** disegni un connettore. Rilasciandolo **su un oggetto**, che si evidenzia, si aggancia al **punto più vicino del suo contorno**: qualsiasi punto, con una calamita sui 4 punti centrali entro 10 pt. Rilasciandolo **nel vuoto** nasce una forma nuova collegata; tenendo premuto prima di rilasciare, l'estremo resta libero.
- **Gli estremi seguono gli oggetti:** spostando, ridimensionando o ruotando un oggetto collegato, i connettori si aggiornano dal vivo.
- **Oggetto eliminato:** l'estremo diventa libero e resta dov'era.
- **Modifica:**
  - trascini un estremo per staccarlo e riattaccarlo;
  - la maniglia centrale piega la curva;
  - nel menu, **Dritto / Curvo / A gomito**.
  - Il gomito usa segmenti ortogonali che escono perpendicolari dal lato di partenza e non attraversano gli oggetti collegati (instradamento ortogonale semplice).
- **Etichette:** doppio tocco su un connettore per scrivere un'etichetta al centro.

### 5.3 Testo dentro le forme
- Doppio tocco su una forma per scrivere un'etichetta **centrata e contenuta nella forma**, con a capo automatico e rimpicciolimento opzionale del carattere.
- Campo opzionale sulla forma, per esempio `label: String?` e `labelRTF: Data?`.
- L'etichetta segue la forma ed è evidenziabile come il testo delle caselle.
- Elenchi e rientri funzionano anche qui e nei post-it (Goodnotes aprile–giugno 2026).

### 5.4 Mappe dell'AI modificabili
- `MindMapLayout.swift` ed `EditorMindMap.swift` oggi creano linee semplici.
- Devono creare **rettangoli arrotondati con etichetta**, uniti da **connettori curvi**, con un'impaginazione che eviti sovrapposizioni.
- Il risultato si modifica come un diagramma fatto a mano.

**Disegno ed export:** i connettori compaiono a schermo, nelle miniature, nel PDF e nel backup nativo. Tocchi e selezione lungo il tracciato, con tolleranza.

**Criteri di accettazione:**
- uno schema di 6 blocchi collegati si fa solo con tocchi sui punti blu;
- spostando un blocco i collegamenti lo seguono;
- il PDF esportato è identico allo schermo.

**Test:**
- intersezione con il contorno di rettangolo, ellisse, rombo e poligono, anche ruotati;
- aggiornamento degli estremi;
- instradamento a gomito;
- estremo libero dopo l'eliminazione;
- decodifica senza connettori.

---

## 6. Selezione tra pagine, gomme ed eliminazioni; goniometro (0.28)

### 6.1 Selezione su un'altra pagina (esiste: va completata)
`MoveSelection.swift` sposta già la selezione su un'altra pagina scelta da un elenco. Da completare:
- un foglio con le **miniature** delle pagine invece dell'elenco testuale;
- le voci **"Nuova pagina dopo questa"** e **"Nuova pagina alla fine"**;
- il comando **"Copia in un'altra pagina"**, oltre a "Sposta": gli oggetti copiati ricevono ID nuovi;
- se la pagina di destinazione ha un'altra dimensione, la selezione viene **proporzionata** e tenuta dentro la pagina;
- **trascinamento:** tieni premuta la selezione e trascinala su una miniatura del pannello pagine (`PageBrowser.swift`);
- **coerenza:**
  - gli ancoraggi audio (`StrokeAnchor`) dell'inchiostro spostato lo seguono;
  - lo stesso vale per le note della Lente e i link di pagina;
  - i connettori si spostano se lo sono entrambi gli estremi, altrimenti diventano liberi;
- un solo annulla, per entrambe le pagine.

### 6.2 Copia come immagine
Nel menu della selezione: **"Copia come immagine"** e **"Condividi immagine"**, in PNG con trasparenza a risoluzione doppia.

### 6.3 Gomma selettiva per tipo
Nelle opzioni della gomma, la voce **"Cancella"** offre:
- Tutto;
- Solo evidenziatore (esiste già, `SelectiveInkEraser.swift`);
- Solo penna;
- Solo forme e connettori;
- Solo testo e post-it;
- Solo immagini.

La gomma parziale vale per l'inchiostro. Gli oggetti vengono cancellati interi quando la gomma ci passa sopra.

### 6.4 "Elimina elementi di un tipo"
Come "Delete Specific Items" di Goodnotes. Si apre dal menu della pagina e da quello del quaderno, con un foglio dove scegli:
- **tipi:** inchiostro della penna, evidenziatore, forme, connettori, testo e post-it, immagini, nastro di ripasso, note della Lente, collegamenti audio;
- **ambito:** questa pagina, le pagine selezionate o tutto il quaderno.

Prima di confermare mostra il **conteggio** degli elementi. Sul quaderno intero crea prima un **backup automatico** con il meccanismo esistente, così si può sempre tornare indietro. Sulla singola pagina basta l'annulla.

### 6.5 Goniometro e misure
- Nuovo `ProtractorGuide` in Core, come `RulerGuide`, con la sua vista accanto a `RulerGuideView.swift`. Si attiva dalla toolbar accanto al Righello, in due versioni: **semicerchio (180°)** e **cerchio (360°)**.
- **Spostarlo:** con un dito sul corpo; con due dita per spostarlo e ruotarlo. Le tacche sono a 1°, con numeri ogni 10°.
- **Disegnare:**
  - la penna vicina al bordo curvo (entro 12 pt a schermo) **segue l'arco**;
  - un tratto che parte dal centro diventa un **raggio** agganciato ai gradi, con calamite a 5°, 15°, 30°, 45° e 90°;
  - un'etichetta dal vivo mostra l'angolo, per esempio "37°".
- **"Misura angolo":** tracci due raggi dal centro e leggi l'angolo tra loro.
- **Righello:** aggiungi la lettura dal vivo della **lunghezza in cm** (1 pt = 1/72 di pollice sulla pagina) e dell'**angolo**.
- **Compasso** (facoltativo, se resta tempo): fissi il centro, trascini per il raggio e disegni cerchi o archi perfetti con la penna.

**Test:**
- calcolo della posizione sull'arco e degli angoli;
- spostamento tra pagine con ancoraggi e connettori;
- conteggi di "Elimina elementi";
- gomma per tipo.

---

## 7. Testo e richieste più votate (0.29)

1. **Pedice e apice** (richiesta molto votata), in `RichText.swift` e `CanvasTextInput.swift`:
   - pulsanti nella barra di formattazione;
   - scorciatoie ⌘= per il pedice e ⇧⌘= per l'apice;
   - testo più piccolo e spostato sulla riga;
   - corretti anche nel PDF.
2. **Colori per materia:**
   - **set di colori con nome** (per esempio "Biologia" con 5 colori), creati, rinominati e riordinati nel Workspace;
   - la palette mostra il set scelto, i preferiti e i recenti;
   - il profilo per materia del quaderno può indicare un set predefinito.
3. **Penna calligrafica** (la richiesta più votata):
   - se l'SDK di iOS 26 (Xcode 26.6) espone in PencilKit un tipo di inchiostro calligrafico (verifica `PKInkingTool.InkType.reed` o simile), aggiungi la penna **"Calligrafica"** tra i tipi in `WritingOptions.swift` e `WritingToolsPanel.swift`;
   - proteggila con `#available` e `#if compiler`; dove manca non mostrarla;
   - **non simularla** con un pennello finto. Se non esiste, scrivilo nel DELIVERY.
4. **Evidenziatore rettangolare:**
   - modalità **"Rettangolo"** nelle opzioni dell'evidenziatore: trascini e nasce un rettangolo pieno, trasparente, del colore dell'evidenziatore, con fusione "moltiplica" come l'evidenziatore;
   - è una forma riempita senza contorno, quindi modificabile;
   - sulle pagine PDF, se c'è testo selezionabile, offri anche l'aggancio alle righe di testo (esiste già per il testo del PDF).
5. **Finestra di zoom** (classica di Goodnotes):
   - un pannello nella parte bassa dello schermo, circa il 30%, mostra **ingrandita** (da 2× a 4×) la zona indicata da un riquadro trascinabile sulla pagina;
   - scrivendo nel pannello, i tratti finiscono nel punto corrispondente della pagina, trasformati alla scala giusta;
   - **avanzamento automatico:** arrivato all'ultimo 15% a destra, il riquadro avanza; al margine destro va a capo, con altezza della riga presa dalla rigatura della carta o dall'altezza del riquadro;
   - margini sinistro e destro impostabili; pulsanti ←, →, Nuova riga, Chiudi e cursore dello zoom;
   - funziona con penna, evidenziatore e gomma, con un annulla per ogni tratto;
   - **attenzione:** `ZoomNavigator.swift` è solo una panoramica in lettura, non una finestra di zoom.
6. **Opzioni di riproduzione dei tratti con l'audio**, in `InkReplayOverlay.swift`, come Goodnotes aprile–giugno 2026:
   - **Segui in tempo reale**: come oggi;
   - **Mostra tutto**: tutto l'inchiostro visibile, con evidenziato il tratto del momento;
   - **Salta ai punti chiave**: salta tra i segnalibri audio e le pause lunghe.
7. **Indice multilivello comprimibile**, in `SectionsPanel.swift` ed `EditorSections.swift`. Le sezioni annidate esistono già; mancano:
   - frecce per **comprimere ed espandere**;
   - **riordino trascinando**;
   - **rientro e de-rientro** (sposta sotto o fuori dalla sezione sopra).
8. **Strumento testo fisso:** un'opzione nel menu dello strumento Testo, **"Resta attivo"**, per inserire più caselle di fila senza riselezionarlo.
9. **Incolla:**
   - incollare mantiene la formattazione;
   - **⇧⌘V incolla senza formattazione**.
10. **Scorciatoie da aggiungere** in `EditorKeyboard.swift`:
    - ⌘B, ⌘I e ⌘U nel testo;
    - ⇧⌘F per la ricerca in tutti i quaderni;
    - ⌘T e ⌘W per aprire e chiudere schede;
    - ⇧⌘V;
    - G per il goniometro e R per il righello.

    Aggiornale anche nell'elenco che iPadOS mostra tenendo premuto ⌘.

---

## 8. Livelli veri (0.30)

Come i Layers di Goodnotes (luglio–settembre 2026). È la modifica più delicata del modello: fai prima un piccolo documento di progetto nel DELIVERY.

### 8.1 Modello
- `PageSnapshot.layers: [PageLayer]?`, dove `PageLayer` contiene:
  - `id`, `name`;
  - `isVisible`, `isLocked`;
  - `opacity: Double?`;
  - `drawingFile: String?`: un file PKDrawing per livello.
- **Livello di base:** l'attuale `drawingFile` più gli oggetti senza livello, cioè tutto quello che esiste oggi. **Nessuna migrazione dei file.**
- Gli oggetti ricevono `layerID: UUID?`: testo, immagini, forme, connettori, nastri e, se ha senso, le annotazioni PDF. `nil` significa livello di base.
- Massimo **16 livelli per pagina**. `PageValidation` controlla ID unici, file presenti, riferimenti validi e limiti.

### 8.2 Come si usa
- Un pulsante **Livelli** nell'editor apre il pannello della pagina, con l'elenco dall'alto in basso:
  - miniatura e nome, rinominabile;
  - occhio (mostra o nascondi) e lucchetto (blocca);
  - riordino trascinando;
  - nuovo, duplica, elimina, **unisci al livello sotto**;
  - opacità.
- **Livello attivo:**
  - penna, evidenziatore, gomma, lazo, forme e testo lavorano **solo** lì, e gli oggetti nuovi nascono lì;
  - gli oggetti dei livelli nascosti o bloccati non si selezionano e non si cancellano;
  - la toolbar mostra discretamente il nome del livello attivo quando ce n'è più di uno.
- **Suggerimento:** sulle pagine di un PDF importato, la prima volta che si scrive si può proporre un livello "Annotazioni". Facoltativo, con un'impostazione.

### 8.3 Disegno
- Il livello attivo usa l'unico `PKCanvasView` dal vivo (`EditorViewModel.canvas`, `PencilCanvas.swift`).
- Gli altri livelli sono immagini in cache, disegnate **sotto e sopra** il canvas nel loro ordine (`DocumentRenderCache.swift`, `PageRenderer.swift`).
- I livelli sopra il canvas lasciano passare i tocchi.
- L'ordine degli oggetti rispetto all'inchiostro (`aboveInkObjects`) vale dentro ogni livello.
- Cambiare livello attivo scambia il disegno nel canvas senza perdere l'annulla e senza scatti visibili.

### 8.4 Export, ricerca e sincronizzazione
- Nell'export PDF e immagine: **Livelli: tutti / solo visibili / scegli**. Nel menu del livello: "Esporta solo questo livello".
- Il backup nativo e la sincronizzazione dell'account portano tutti i livelli: controlla il formato del pacchetto e del sincronizzatore.
- Ricerca e OCR indicizzano l'inchiostro di tutti i livelli.
- I collegamenti audio funzionano per tratto, su qualsiasi livello.

**Criteri di accettazione:**
- su un PDF importato si scrive su un livello, lo si nasconde e il PDF torna pulito;
- l'export "solo visibili" lo conferma;
- una pagina della 0.29 si apre identica, con un solo livello di base.

**Test:**
- codifica e decodifica;
- validazione;
- ordine di disegno;
- strumenti limitati al livello attivo;
- unisci;
- export filtrato;
- annulla delle operazioni sui livelli.

---

## 9. Grafia: raddrizza e ripulisci (0.31)

Una versione **geometrica, sul dispositivo e senza AI** di Restyle e Smart Ink di Goodnotes e di Smart Script di Apple. **Non cambia le parole e non inventa grafia**: sposta, ruota, scala e leviga i tratti esistenti. Funziona in qualsiasi lingua.

### 9.1 Dove si trova
Nel menu del lazo, alla voce **"Grafia ▸"**:
- Raddrizza;
- Uniforma dimensione;
- Ripulisci tratto;
- Riadatta alla larghezza;
- Spazio tra le righe.

Ogni comando mostra prima un'**anteprima**: i tratti nuovi sopra quelli originali, sbiaditi, con i pulsanti **Applica** e **Annulla**. Applica crea un solo passo di annulla.

### 9.2 Algoritmi
Funzioni pure in Core, per esempio `HandwritingLayout`, che lavorano sui punti dei `PKStroke` e conservano pressione, larghezza e inchiostro.
- **Righe:** ordina i tratti per centro verticale e raggruppali per sovrapposizione verticale (almeno il 40% dell'altezza media). Se l'OCR esistente fornisce i riquadri delle righe, usali come aiuto.
- **Linea di base** di ogni riga: regressione robusta sui punti bassi dei tratti (il 20° percentile di y per fascia di x) per trovarne l'angolo.
- **Parole:** dentro una riga, raggruppa i tratti separati da spazi orizzontali maggiori di 0,6 volte l'altezza media della x.
- **Raddrizza:**
  - ruota ogni riga attorno al suo inizio fino a renderla orizzontale;
  - opzione **"Allinea a sinistra"**;
  - sulla carta a righe, opzione **"Appoggia sulle righe"**: allinea la base alla rigatura.
- **Uniforma dimensione:** scala ogni parola attorno al suo punto di base sinistro verso l'altezza mediana della x, con fattore limitato tra 0,8 e 1,25.
- **Ripulisci tratto:** semplificazione Ramer–Douglas–Peucker con tolleranza bassa, poi levigatura Chaikin o Catmull-Rom. Intensità **Leggera, Media o Forte**. Le forme rimangono riconoscibili e i punti di pressione restano.
- **Riadatta alla larghezza** (come Smart Ink):
  - compaiono **maniglie laterali** sulla selezione;
  - trascinandole, le parole si **ridistribuiscono** sulla nuova larghezza andando a capo, con spaziatura tra parole e righe uguale a quella originale.
- **Spazio tra le righe:**
  - una maniglia orizzontale spinge in basso, o tira in alto, tutto ciò che sta sotto sulla pagina;
  - oppure un comando uniforma l'interlinea della selezione.

### 9.3 Facoltativo, solo se resta tempo
**Correttore della grafia:**
- l'OCR esistente legge le parole;
- `UITextChecker` in italiano trova quelle sospette e le sottolinea con un'ondina rossa sopra la grafia;
- toccando una parola compaiono i suggerimenti e l'azione "Converti in testo corretto".

Non riscrive mai la grafia.

**Criteri di accettazione:**
- un paragrafo scritto storto, su 5 righe con inclinazioni diverse, diventa diritto e regolare in un passo;
- annulla riporta l'originale esatto;
- il testo riconosciuto dall'OCR non cambia prima e dopo.

**Test:**
- righe sintetiche inclinate;
- raggruppamento di righe e parole;
- limiti delle scale;
- conservazione della pressione;
- riadattamento con a capo;
- annulla.

---

## 10. Escluso da questo piano (non implementare)

- **GIF / GIPHY:** servizio esterno con chiave.
- **Collaborazione in tempo reale e cartelle condivise:** richiedono un backend di condivisione.
- **Sincronizzazione dei calendari nel planner**, **Meeting Assistant**, **collegamenti a Box o Dropbox:** l'app File copre già l'import.
- **Grafia generata dall'AI:** si fanno solo trasformazioni geometriche, §9.
- **Sincronizzazione iCloud:** è già pianificata con la firma iCloud, in una beta successiva.

## 11. Riepilogo finale di ogni fase

Scrivimi alla fine di ogni fase, in italiano semplice:
1. cosa è nuovo e **come provarlo passo passo sull'iPad**, un passo alla volta;
2. cosa è rimasto parziale o escluso, e perché;
3. versione e build, link alla verifica completa e alla build TestFlight;
4. eventuali rischi per i dati, con le prove fatte.


---
## Stato di esecuzione — aggiornamento 29 ottobre 2026

Il testo del piano sopra è conservato integralmente.

- ✅ Prerequisiti verificati nella run 40391428100.
- ✅ 0.25 — §2–3: implementata e verificata. Verifica completa [40815806130](https://github.com/sminikiller/NeuralNotes/actions/runs/40815806130), sei job verdi e tutti i 32 test UI superati. Beta 1.0.0 (128) firmata e caricata su Apple con [40875248301](https://github.com/sminikiller/NeuralNotes/actions/runs/40875248301). Elaborazione/disponibilità TestFlight non ancora confermata. ZIP compilato esatto e prove in docs/DELIVERY_0_25.md.
- 🟡 0.26 — §4 aggancio completo, griglia e allineamenti: in sviluppo.
- ❌ 0.27 — §5 diagrammi e connettori persistenti: successiva.
- ❌ 0.28 — §6 selezioni, gomme e goniometro: successiva.
- ❌ 0.29 — §7 testo e finestra di zoom: successiva.
- ❌ 0.30 — §8 livelli: successiva.
- ❌ 0.31 — §9 trasformazioni della grafia: successiva.

Nessuna modifica a identità, firma, segreti NN_* o corsia TestFlight. Nessuna attivazione iCloud. Ogni fase è verificata e consegnata separatamente. Tempi fisici di fluidità e falsi positivi su grafia reale rimangono distinti dalle prove sintetiche e sul simulatore.
