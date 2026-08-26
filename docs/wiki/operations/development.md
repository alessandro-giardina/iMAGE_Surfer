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

**Precedenza dichiarata dal PRD.** La costruzione completa è subordinata a quattro **cancelli tecnici** (Tappa 0), che vivranno sotto `Spikes/` insieme al proprio dataset, alla procedura di generazione e all'esito scritto:

| # | Cancello | ADR che può invalidare |
|---|---|---|
| 1 | Prestazioni e memoria su 50.000 file, su dataset e hardware dichiarati | ADR-009, e con esso NFR-P1, P9, P10 |
| 2 | Eventi e identità su APFS, volume esterno, cartella sincronizzata, volume di rete — con mandato di concludere quali classi richiedono un meccanismo diverso, fino al supporto dichiarato come limitato | ADR-011, ADR-012 |
| 3 | Round-trip XMP con Bridge, Lightroom, darktable, digiKam, **incluso uno scrittore che ignora il coordinamento di sistema** | ADR-013 |
| 4 | Iniezione di arresti in ogni punto di un lotto, per stabilire quale dei **cinque esiti** si raggiunge e quali punti finiscono legittimamente in "bloccato in attesa dell'utente" | ADR-007 |

Ogni cancello ha mandato esplicito di poter concludere che **qualcosa non è supportabile**: è un esito legittimo e non un fallimento. Con la revisione 1.3 il PRD dichiara chiuse le revisioni dell'architettura sulla carta — le domande rimaste si chiudono misurando.

Il materiale dei cancelli 1 e 2 non è versionabile (50.000 file, volumi di prova esterni e di rete): il repository ne versiona la procedura di generazione e configurazione, non i dati.

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
- **Test di iniezione di arresti** sui lotti di operazioni su file, eseguiti a ogni push: interrompono il lotto in ogni punto e verificano quale dei cinque esiti dichiarati viene raggiunto. Sono la verifica del contratto di ADR-007, che promette **recuperabilità e non atomicità**, e nemmeno la conclusione garantita: la proprietà da testare è che l'app riconosca sempre lo stato raggiunto e sappia nominare ciò che richiede intervento umano.
- **Corpus di file malformati** (troncati, corrotti, con intestazioni incoerenti) nei test a ogni push: verifica che nessun file non fidato interrompa il caricamento della cartella. È una delle condizioni a cui ADR-016 subordina l'accettazione del rischio di decodifica in un processo non isolato.

<!-- archetipo:wiki section=runtime -->

## Esecuzione e vincoli operativi

- Applicazione monoprocesso, interamente locale: nessun server, nessun database esterno, nessuna variabile d'ambiente obbligatoria, nessun account.
- **Nessuna rete a tempo di esecuzione.** L'unica connessione ammessa dal PRD è l'eventuale download iniziale del modello estetico, se non incluso nel bundle; la scelta tra bundle e download è un punto aperto dichiarato nel PRD.
- L'app è prevista **senza App Sandbox** ma **senza richiedere l'Accesso completo al disco**: il PRD si affida al consenso contestuale che macOS chiede per le categorie protette e all'accesso concesso aprendo o trascinando una cartella; il FDA resta un'opzione per chi lavora su percorsi insoliti. In sviluppo, compilazioni successive possono invalidare il consenso già concesso — fastidio noto della fase di sviluppo, non dell'app distribuita.
- **Correzione registrata nella 1.3:** le versioni precedenti affermavano che l'assenza di sandbox mettesse "la distribuzione a terzi fuori portata". È falso, ed era un errore propagato per tre versioni. Un `.dmg` notarizzato **è** distribuzione a terzi; la sandbox è il presupposto del **Mac App Store** e dell'isolamento del filesystem. La conseguenza operativa è opposta a quella scritta finora: il canale di distribuzione diretta è utilizzabile dall'MVP e la sua esperienza di installazione va curata.
- **Perimetro di sicurezza.** Il processo è unico, non in sandbox, e interpreta immagini non fidate. ADR-016 accetta e dichiara il rischio per l'MVP a condizioni precise (nessun percorso esegue contenuto, errori di decodifica contenuti al singolo file, corpus di file malformati in CI, hardened runtime e validazione delle librerie) e registra l'isolamento XPC di decodifica e analisi come evoluzione.
- Vincoli di prestazione trattati dal PRD come vincoli e non come obiettivi: prima schermata di anteprime entro 1 secondo su 3.000 immagini, risposta alla navigazione entro 100 ms, nessuna scansione bloccante all'apertura di una cartella, uso di CPU indistinguibile da zero a cartella ferma, un tetto dichiarato all'occupazione di memoria di picco, e una latenza massima dell'aggiornamento della vista anche sotto raffica continua di eventi. Il lavoro non più visibile viene liberato solo **oltre una banda di ritenzione con isteresi**: la cancellazione immediata prescritta dalla revisione precedente è stata rimossa perché su uno scorrimento reale butta via il lavoro appena svolto.
- I valori numerici dei vincoli sono **soglie dichiarate, non misure ottenute**: il PRD li subordina all'esito del cancello n°1.

<!-- archetipo:wiki section=deployment -->

## Distribuzione prevista

- CI su runner macOS di GitHub Actions: lint, build dei pacchetti, test unitari, build dell'applicazione, test di interfaccia sui percorsi a tastiera; su ramo principale e prima di ogni rilascio anche i test di lunga durata; su tag di versione build Release con hardened runtime, firma, notarizzazione e pubblicazione del `.dmg`.
- Distribuzione **manuale** come `.dmg` notarizzato. Nessun canale di aggiornamento automatico previsto nella prima versione.
- Infrastruttura di destinazione: il Mac dell'utente. Nessuna infrastruttura server, nessun servizio remoto, nessuna telemetria.
- Il repository è oggi sotto controllo di versione Git, ma non contiene ancora né la pipeline descritta né codice applicativo: entrambe restano prescrizioni del PRD da verificare quando esisteranno.

## Concetti collegati

- [Panoramica](/overview.md)
- [Mappa del codice](/engineering/code-map.md)
