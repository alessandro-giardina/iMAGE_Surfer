---
type: operations
title: Sviluppo e operatività
description: Build, test, esecuzione e distribuzione previsti per iMAGE Surfer; nessuna toolchain è oggi presente nel repository
status: generated
sources:
  - path: .
    role: repository-inventory
  - path: docs/PRD.md
    role: product-intent
---
# Sviluppo e operatività

<!-- archetipo:wiki section=state -->

## Stato attuale

**Nel repository non esiste alcuna toolchain.** L'ispezione ha rilevato zero manifest, zero configurazioni, zero automazioni e zero test. Non esiste un comando di build, non esiste un comando di test, e non esiste nulla da eseguire. Tutto ciò che segue è **prescritto dal PRD** e va verificato contro il repository nel momento in cui la prima riga di codice esiste: [PRD di iMAGE Surfer](/references/prd.md).

<!-- archetipo:wiki section=build -->

## Build previsto

- Progetto Xcode con target applicativo sottile sopra pacchetti SPM locali; SPM risolve le dipendenze dei pacchetti locali e l'unica dipendenza esterna prevista a tempo di esecuzione (GRDB.swift).
- `xcodebuild` come strumento di build da riga di comando.
- Requisiti dell'ambiente: macOS 15 o successivo su Apple Silicon, Xcode 16 o successivo con Swift 6 in modalità di concorrenza stretta.
- `swift-format` e SwiftLint per lo stile.
- `coremltools` (Python) richiesto **solo** in fase di conversione del modello estetico, mai a tempo di esecuzione.

<!-- archetipo:wiki section=test -->

## Test previsti

- Swift Testing per unità e integrazione, con ogni pacchetto SPM testabile senza avviare l'interfaccia.
- XCUITest sui percorsi critici di navigazione da tastiera, che il PRD identifica come contratto d'uso primario e quindi come superficie da coprire con test di interfaccia.
- Fixture versionate nel repository come difesa sui casi limite: raffiche reali, duplicati byte-identici, immagini senza EXIF, HEIC, orientamenti EXIF non standard, sidecar XMP prodotti da strumenti di terze parti.
- **Test di lunga durata** su cartella generata di grandi dimensioni, eseguiti in CI su ramo principale e prima di ogni rilascio, con soglie di fallimento dichiarate su: occupazione di memoria di picco, crescita dell'occupazione nel tempo, e numero di riconciliazioni prodotte da una raffica sintetica di eventi del filesystem. Il PRD li tratta come parte del contratto architetturale (ADR-009, ADR-012) e non come test facoltativi.

<!-- archetipo:wiki section=runtime -->

## Esecuzione e vincoli operativi

- Applicazione monoprocesso, interamente locale: nessun server, nessun database esterno, nessuna variabile d'ambiente obbligatoria, nessun account.
- **Nessuna rete a tempo di esecuzione.** L'unica connessione ammessa dal PRD è l'eventuale download iniziale del modello estetico, se non incluso nel bundle; la scelta tra bundle e download è un punto aperto dichiarato nel PRD.
- L'app è prevista **senza App Sandbox** ma **senza richiedere l'Accesso completo al disco**: il PRD 1.1 si affida al consenso contestuale che macOS chiede per le categorie protette e all'accesso concesso aprendo o trascinando una cartella; il FDA resta un'opzione per chi lavora su percorsi insoliti. Conseguenza operativa dichiarata: la distribuzione a terzi e il Mac App Store restano comunque fuori portata fino all'introduzione della sandbox. In sviluppo, compilazioni successive possono invalidare il consenso già concesso — fastidio noto della fase di sviluppo, non dell'app distribuita.
- Vincoli di prestazione trattati dal PRD come vincoli e non come obiettivi: prima schermata di anteprime entro 1 secondo su 3.000 immagini, risposta alla navigazione entro 100 ms, nessuna scansione bloccante all'apertura di una cartella, cancellazione immediata del lavoro non più visibile, uso di CPU indistinguibile da zero a cartella ferma, e un tetto dichiarato all'occupazione di memoria di picco.

<!-- archetipo:wiki section=deployment -->

## Distribuzione prevista

- CI su runner macOS di GitHub Actions: lint, build dei pacchetti, test unitari, build dell'applicazione, test di interfaccia sui percorsi a tastiera; su ramo principale e prima di ogni rilascio anche i test di lunga durata; su tag di versione build Release con hardened runtime, firma, notarizzazione e pubblicazione del `.dmg`.
- Distribuzione **manuale** come `.dmg` notarizzato. Nessun canale di aggiornamento automatico previsto nella prima versione.
- Infrastruttura di destinazione: il Mac dell'utente. Nessuna infrastruttura server, nessun servizio remoto, nessuna telemetria.
- Il repository è oggi sotto controllo di versione Git, ma non contiene ancora né la pipeline descritta né codice applicativo: entrambe restano prescrizioni del PRD da verificare quando esisteranno.

## Concetti collegati

- [Panoramica](/overview.md)
- [Mappa del codice](/engineering/code-map.md)
