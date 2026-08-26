---
type: overview
title: iMAGE Surfer
description: Applicazione macOS nativa per browsing, triage e riorganizzazione di immagini in cartelle; stato attuale del repository e ambito della mappa
status: generated
sources:
  - path: .
    role: repository-inventory
  - path: docs/PRD.md
    role: product-intent
---
# iMAGE Surfer

<!-- archetipo:wiki section=purpose -->

## Scopo del sistema

iMAGE Surfer è un'applicazione **nativa macOS** che tratta una cartella del filesystem come un insieme di immagini da lavorare, non come un elenco di file: visualizzazione a griglia con anteprime grandi, navigazione integralmente da tastiera, metadati sempre visibili, rilevamento di duplicati esatti e quasi-duplicati, rinomina e smistamento massivi guidati da regole, e selezione assistita da analisi visiva eseguita interamente in locale.

Il principio portante è che **la cartella è la fonte di verità**, e il PRD lo estende al lavoro dell'utente: i giudizi (stelle e marcature) non vivono in una cache ma in sidecar XMP affiancati alle immagini, leggibili anche fuori dall'app.

Il PRD 1.2 distingue **tre nature di dato** e le tiene in sedi diverse — dato derivato in una cache eliminabile, dato autorale nel sidecar, stato durevole di processo (registro delle operazioni, lotti aperti, scritture in attesa) in un archivio separato e non cancellabile — e dichiara un vocabolario di contratti che la Wiki deve rispettare quando descriverà il codice: **ricostruibile** per la cache, **recuperabile** e non atomico per un lotto di operazioni su file, **best-effort** per il recupero dell'associazione tra giudizio e immagine nei casi elencati come tali.

Questo scopo è **intento di prodotto documentato**, non comportamento osservato: al momento della compilazione di questa mappa il repository non contiene codice applicativo. La fonte dell'intento è il PRD, rappresentato come concetto di riferimento: [PRD di iMAGE Surfer](/references/prd.md).

<!-- archetipo:wiki section=actors -->

## Attori

Dichiarati nel PRD, non verificabili su codice:

- **Curatore di cartelle** — proprietario del Mac, utente unico e amministratore dell'app; scarica materiale fotografico in cartelle e lo screma, rinomina e riorganizza.
- **Selezionatore sotto scadenza** — riceve cartelle di materiale altrui e deve consegnare pochi scatti selezionati e nominati secondo convenzione.
- **Il sistema operativo** come attore tecnico: i servizi macOS (anteprime, lettura metadati, visione artificiale, Cestino, eventi del filesystem) sono la dipendenza portante del prodotto.

<!-- archetipo:wiki section=stack -->

## Stack

Lo stack è **prescritto dal PRD e non ancora presente nel repository**. Nessun manifest di build, nessuna configurazione di progetto e nessun file sorgente sono stati rilevati dall'ispezione.

| Livello | Tecnologia prescritta | Stato nel repository |
|---|---|---|
| Linguaggio | Swift 6.x | assente |
| Piattaforma | macOS 15+, Apple Silicon | assente |
| Interfaccia | SwiftUI con ponte AppKit (`NSCollectionView`) per la griglia | assente |
| Anteprime e immagini | QuickLook Thumbnailing, ImageIO, Core Image | assente |
| Visione artificiale | Vision (feature print, volti, **landmark**; lo stato aperto/chiuso degli occhi è euristica dell'app, non API), Core ML | assente |
| Osservazione filesystem | File System Events, eventi a granularità di file, identificatore d'evento persistito e legato al volume | assente |
| Identità dei file | Chiavi di risorsa di Foundation + bookmark persistenti; combinazione da stabilire in Tappa 0 | assente |
| Coordinamento tra processi | `NSFileCoordinator` per gli accessi concorrenti al sidecar | assente |
| Persistenza | SQLite tramite GRDB.swift 7.x, in **due file distinti** (cache derivata, stato durevole); sidecar XMP (schema Basic) per i giudizi | assente |
| Test | Swift Testing, XCUITest, lunga durata su memoria ed eventi, iniezione di arresti sui lotti | assente |

<!-- archetipo:wiki section=scope -->

## Ambito della mappa ed esclusioni

**Ambito.** Questa mappa copre lo stato corrente del repository e l'intento di prodotto. Poiché l'ispezione non ha rilevato confini fisici né candidati di capacità, non esistono pagine di dominio: nessun dominio è stato creato per non trasformare affermazioni del PRD in osservazioni di codice.

**Stato dell'intento.** Il PRD 1.2 subordina la costruzione completa a quattro **cancelli tecnici** (scala e memoria su 50.000 file; matrice eventi e identità su APFS, volume esterno, cartella sincronizzata e volume di rete; round-trip XMP con strumenti reali; iniezione di arresti su un lotto di operazioni) e dichiara **provvisori** gli ADR-007, 009, 011, 012 e 013 fino al loro esito. Parte dell'intento qui rappresentato è quindi un'ipotesi in attesa di verifica, non una decisione chiusa.

**Esclusioni riportate dall'ispezione:** metadati del repository, directory di dipendenze e build, radice della Wiki configurata.

**Aree non ispezionate:** l'inventario Git non era disponibile e l'ispezione ha usato la ricalibrazione da filesystem. Il progetto non è un repository Git al momento della compilazione.

**Nota sull'ancoraggio delle evidenze.** Le pagine core citano la radice del progetto (`.`) come sorgente tracciata perché la loro affermazione centrale — *non esiste ancora codice implementato* — decade nel momento in cui compare codice in qualunque punto dell'albero. Appena esistono directory sorgente reali, l'ancoraggio va restretto a quelle directory.

## Concetti collegati

- [Mappa dei contesti](/architecture/context-map.md) — confini logici, oggi tutti non risolti
- [Mappa del codice](/engineering/code-map.md) — crosswalk fisico, oggi vuoto
- [Sviluppo e operatività](/operations/development.md) — build, test, distribuzione previsti
- [PRD di iMAGE Surfer](/references/prd.md) — la fonte dell'intento
