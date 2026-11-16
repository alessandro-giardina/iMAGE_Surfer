---
type: overview
title: iMAGE Surfer
description: Applicazione macOS nativa per browsing, triage e riorganizzazione di immagini in cartelle; stato attuale del repository e ambito della mappa
status: generated
sources:
  - path: Spikes/01-scale-memory
    role: implementation
  - path: docs/PRD.md
    role: product-intent
---
# iMAGE Surfer

<!-- archetipo:wiki section=purpose -->

## Scopo del sistema

iMAGE Surfer è un'applicazione **nativa macOS** che tratta una cartella del filesystem come un insieme di immagini da lavorare, non come un elenco di file: visualizzazione a griglia con anteprime grandi, navigazione integralmente da tastiera, metadati sempre visibili, rilevamento di duplicati esatti e quasi-duplicati, rinomina e smistamento massivi guidati da regole, e selezione assistita da analisi visiva eseguita interamente in locale.

Il principio portante è che **la cartella è la fonte di verità**, e il PRD lo estende al lavoro dell'utente: i giudizi (stelle e marcature) non vivono in una cache ma in sidecar XMP affiancati alle immagini, leggibili anche fuori dall'app.

Il PRD distingue **tre nature di dato** e le tiene in sedi diverse — dato derivato in una cache eliminabile, dato autorale nel sidecar, stato durevole di processo (registro delle operazioni, lotti aperti, scritture in attesa) in un archivio separato, non cancellabile e con contratto di durabilità proprio — tenute insieme da un **invariante direzionale**: stato durevole e sidecar sono autorevoli, la cache può restare indietro ed essere riallineata.

Il documento dichiara un vocabolario di contratti che la Wiki deve rispettare quando descriverà il codice: **ricostruibile** per la cache, **recuperabile** — non atomico e non sempre concludibile — per un lotto di operazioni su file, **best-effort** per il recupero dell'associazione tra giudizio e immagine e per la protezione verso applicazioni che non si coordinano. Nessuno è *garantito*, ed è una regola esplicita del PRD che un meccanismo cooperativo non venga mai descritto come impositivo.

Questo scopo è **intento di prodotto documentato**, non comportamento osservato: al momento della compilazione di questa mappa il repository non contiene codice applicativo. La fonte dell'intento è il PRD, rappresentato come concetto di riferimento: [PRD di iMAGE Surfer](/references/prd.md).

<!-- archetipo:wiki section=actors -->

## Attori

Dichiarati nel PRD, non verificabili su codice:

- **Curatore di cartelle** — proprietario del Mac, utente unico e amministratore dell'app; scarica materiale fotografico in cartelle e lo screma, rinomina e riorganizza.
- **Selezionatore sotto scadenza** — riceve cartelle di materiale altrui e deve consegnare pochi scatti selezionati e nominati secondo convenzione.
- **Il sistema operativo** come attore tecnico: i servizi macOS (anteprime, lettura metadati, visione artificiale, Cestino, eventi del filesystem) sono la dipendenza portante del prodotto.
- **Altre applicazioni sugli stessi file** come attore non controllato: strumenti fotografici che leggono e scrivono i sidecar, alcuni coordinandosi con il sistema e altri no. Il PRD 1.3 li tratta esplicitamente, perché il coordinamento vincola solo chi vi partecipa.
- **Il contenuto dei file** come sorgente non fidata: le immagini arrivano da apparecchi e persone che l'utente non controlla, e vengono interpretate da un processo con pieni privilegi (ADR-016).

<!-- archetipo:wiki section=stack -->

## Stack

Lo stack è **prescritto dal PRD**, e il **codice di prodotto continua a non esistere**. Nel repository esiste però codice Swift: il **banco di misura del cancello tecnico n°1**, sotto `Spikes/01-scale-memory/`. È un pacchetto SwiftPM con un manifest (`Package.swift`), la libreria `BenchKit`, gli eseguibili `gen-dataset` e `bench` e la suite `BenchKitTests`.

È il primo codice del repository. È **dichiaratamente usa-e-getta** e non anticipa la struttura di pacchetti prevista dal PRD. Code, cache di anteprime e banda di ritenzione vi esistono nella forma minima che serve a misurarle.

La colonna «Stato nel repository» distingue questo **materiale di misura sotto `Spikes/`** dal codice di prodotto. Una riga cambia solo dove il cancello dimostra l'uso della tecnologia.

| Livello | Tecnologia prescritta | Stato nel repository |
|---|---|---|
| Linguaggio | Swift 6.x | presente nel solo materiale di misura: Swift 6.4.2 dei Command Line Tools, modalità di linguaggio Swift 6 a concorrenza stretta. Nessun codice di prodotto |
| Piattaforma | macOS 15+, Apple Silicon | dichiarata dal banco (`platforms: .macOS(.v15)`), che ha misurato su Apple M1 Pro. Nessun target di prodotto |
| Interfaccia | SwiftUI con ponte AppKit (`NSCollectionView`) per la griglia | `NSCollectionView` in una finestra AppKit usata come **strumentazione di misura** del banco, non come interfaccia. SwiftUI assente |
| Anteprime e immagini | QuickLook Thumbnailing, ImageIO, Core Image | QuickLook Thumbnailing e ImageIO usati dal banco come carichi di misura. Prima schermata su 3.000 immagini: p95 441,8 ms con la decodifica ridimensionata ImageIO e 1771,9 ms con Quick Look (`Spikes/01-scale-memory/RESULT.md`). Core Image assente |
| Visione artificiale | Vision (feature print, volti, **landmark**; lo stato aperto/chiuso degli occhi è euristica dell'app, non API), Core ML | Vision usata dal banco come carico di misura (feature print più landmark dei volti), con un costo mediano da 1,74 a 4,33 MB per elemento. Core ML assente |
| Osservazione filesystem | File System Events, eventi a granularità di file, identificatore d'evento persistito e legato al volume | assente |
| Identità dei file | Chiavi di risorsa di Foundation + bookmark persistenti; combinazione da stabilire in Tappa 0 | assente |
| Coordinamento tra processi | `NSFileCoordinator` per gli accessi concorrenti al sidecar — **cooperativo**, non impositivo | assente |
| Isolamento di processo | XPC — **non usato nell'MVP**, registrato come innesto previsto per isolare la decodifica di dati non fidati (ADR-016) | assente |
| Persistenza | SQLite tramite GRDB.swift 7.x, in **due file distinti** con impostazioni di durabilità diverse (cache derivata, stato durevole); sidecar XMP (schema Basic) per i giudizi | assente |
| Test | Swift Testing, XCUITest, lunga durata su memoria ed eventi, iniezione di arresti sui lotti, corpus di file malformati | Swift Testing presente nella sola suite del banco (`BenchKitTests`). La sessione di memoria di lunga durata esiste come sottocomando del banco, eseguito a mano. Tutto il resto assente |

<!-- archetipo:wiki section=scope -->

## Ambito della mappa ed esclusioni

**Ambito.** Questa mappa copre lo stato corrente del repository e l'intento di prodotto. Poiché l'ispezione non ha rilevato confini fisici né candidati di capacità, non esistono pagine di dominio: nessun dominio è stato creato per non trasformare affermazioni del PRD in osservazioni di codice.

**Stato dell'intento.** Il PRD 1.2 subordina la costruzione completa a quattro **cancelli tecnici**:

1. scala e memoria su 50.000 file;
2. matrice eventi e identità su APFS, volume esterno, cartella sincronizzata e volume di rete;
3. round-trip XMP con strumenti reali;
4. iniezione di arresti su un lotto di operazioni.

Il PRD dichiara **provvisori** gli ADR-007, 009, 011, 012 e 013 fino all'esito dei cancelli. Il **cancello n°1 ha ora un esito scritto**, in `Spikes/01-scale-memory/RESULT.md`:

- ADR-009 è **emendato** con valori misurati: [Ammissione del lavoro con stime calibrate e banda di ritenzione](/decisions/work-admission-budget.md);
- NFR-P1 è confermato con il percorso ImageIO;
- NFR-P9 ed NFR-P10 sono emendati.

Gli altri tre cancelli restano aperti, e con loro gli ADR-007, 011, 012 e 013. La parte dell'intento che ne dipende è ancora un'ipotesi in attesa di verifica, non una decisione chiusa.

**Esclusioni riportate dall'ispezione:** metadati del repository, directory di dipendenze e build, radice della Wiki configurata.

**Aree non ispezionate:** l'inventario Git non era disponibile e l'ispezione ha usato la ricalibrazione da filesystem. Il progetto non è un repository Git al momento della compilazione.

**Nota sull'ancoraggio delle evidenze.** Le pagine core citavano la radice del progetto (`.`) come sorgente tracciata perché la loro affermazione centrale era *non esiste ancora codice implementato*, e quell'affermazione sarebbe decaduta alla comparsa di codice in qualunque punto dell'albero. La condizione prevista si è verificata: esiste la directory sorgente reale `Spikes/01-scale-memory`. L'ancoraggio di questa pagina è quindi **ristretto** a quella directory, con ruolo di implementazione, e al PRD, con ruolo di intento. Quando comparirà il codice di prodotto, le sue directory si aggiungeranno come sorgenti.

## Concetti collegati

- [Mappa dei contesti](/architecture/context-map.md) — confini logici, oggi tutti non risolti
- [Mappa del codice](/engineering/code-map.md) — crosswalk fisico, oggi vuoto
- [Sviluppo e operatività](/operations/development.md) — build, test, distribuzione previsti
- [PRD di iMAGE Surfer](/references/prd.md) — la fonte dell'intento
- [Ammissione del lavoro con stime calibrate e banda di ritenzione](/decisions/work-admission-budget.md) — la decisione chiusa dal cancello n°1
