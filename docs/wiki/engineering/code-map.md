---
type: code-map
title: Mappa del codice
description: Crosswalk fisico da domini a codice; tutto il codice del repository sta nei due banchi di verifica usa-e-getta dei cancelli n°1 e n°4, fuori da ogni dominio di prodotto, quindi la mappa dei domini è vuota
status: reviewed
sources:
    - path: Spikes/01-scale-memory
      role: implementation
    - path: Spikes/04-crash-recovery
      role: implementation
    - path: docs
      role: documentation-inventory
coverage:
    - kind: boundary
      path: Spikes
      status: excluded
      note: Banco di verifica usa-e-getta dei cancelli tecnici (oggi Spikes/01-scale-memory, cancello n°1, e Spikes/04-crash-recovery, cancello n°4), deliberatamente fuori dalla mappa dei domini di prodotto e da non riusare; la conoscenza durevole che ne deriva è in decisions/work-admission-budget e in decisions/recoverable-file-batches.
review:
    content_hash: sha256:2c564742997c8348984141f7c9a97b40271f6970753a8f183dc1254e5a3af47c
    evidence_revision: 10ec6ad380b970b8afee728ac05a08f63794c9a4
    evidence_hash: sha256:3c478c580ca0baea08b9c57f826fe8cf9102a3b941495f7dd38c4d7114b0ff1b
    reviewed_at: "2026-11-16T22:17:56Z"
---
# Mappa del codice

<!-- archetipo:wiki section=domain-code -->

## Da dominio a codice

**La tabella è vuota perché esiste codice, ma non appartiene a nessun dominio di prodotto.** Il repository contiene la documentazione di prodotto (`docs/PRD.md`) e due pacchetti Swift di verifica, ciascuno legato al proprio cancello tecnico: `Spikes/01-scale-memory/`, il banco di misura del cancello n°1, e `Spikes/04-crash-recovery/`, il banco di iniezione di arresti del cancello n°4. Ciascun pacchetto ha un manifest SwiftPM, sorgenti, eseguibili propri e una suite di test, ed è materiale di verifica, non codice di prodotto. Non esistono punti di ingresso dell'applicazione, contratti pubblici, schemi di persistenza, automazioni o infrastruttura.

| Dominio | UI | Punti di ingresso | Logica applicativa/dominio | Dati posseduti | Integrazioni | Test | Pagina Wiki |
|---|---|---|---|---|---|---|---|
| — nessun dominio mappato — | — | — | — | — | — | — | — |

La struttura di directory prevista dal PRD (target applicativo Xcode sopra pacchetti SPM locali: `Catalog`, `Metadata`, `Thumbnails`, `Duplicates`, `Quality`, `FileOps`, `IndexStore`, `DesignSystem`) è **intento di progettazione documentato** e continua a non esistere su disco. `Spikes/` non la anticipa: ciascun banco ha una struttura propria, una libreria (`BenchKit` o `CrashKit`) più eseguibili, pensata per verificare un cancello e non per essere riusata. Attribuzione: [PRD di iMAGE Surfer](/references/prd.md).

<!-- archetipo:wiki section=shared -->

## Codice condiviso

Nessuno nel prodotto, che non ha ancora codice. Nessuno nemmeno fra i due banchi: ciascuno ha la propria libreria, `BenchKit` in `Spikes/01-scale-memory/` e `CrashKit` in `Spikes/04-crash-recovery/`, e il banco n°4 non dipende dal n°1. Le poche parti riprese dal banco n°1, come il blocco del manifest per i soli Command Line Tools e due funzioni di supporto dei test, sono copiate, non importate.

Dentro ciascun banco la libreria è condivisa dai suoi eseguibili e dalla sua suite di test: `BenchKit` da `gen-dataset`, `bench` e `BenchKitTests`; `CrashKit` da `crashbench` e `CrashKitTests`. È materiale di verifica interno ai banchi e non va condiviso con il prodotto.

<!-- archetipo:wiki section=unmapped -->

## Codice non mappato

Tutto il codice del repository è fuori dalla mappa dei domini, per scelta. Sono due banchi di verifica, uno per cancello tecnico:

- `Spikes/01-scale-memory/` — banco di misura del cancello tecnico n°1. È un pacchetto SwiftPM senza dipendenze esterne. Ne fanno parte:
  - la libreria `BenchKit`: campionatore `phys_footprint`, statistica delle ripetizioni, impronta hardware, schema dei risultati e banchi;
  - l'eseguibile `gen-dataset`, che genera il dataset sintetico da 50.000 file;
  - l'eseguibile `bench`, con un sottocomando per misura;
  - la suite `BenchKitTests`, eseguita con Swift Testing.

  È **deliberatamente fuori dalla mappa dei domini** e usa-e-getta: code, cache di anteprime e banda di ritenzione vi esistono nella forma minima che serve a misurarle e non vanno riusate. Il codice è scartabile, la decisione che ha prodotto no. La conoscenza durevole che ne deriva è [Ammissione del lavoro con stime calibrate e banda di ritenzione](/decisions/work-admission-budget.md).

- `Spikes/04-crash-recovery/` — banco di iniezione di arresti del cancello tecnico n°4. È un pacchetto SwiftPM senza dipendenze esterne e senza dipendenze da `Spikes/01-scale-memory/`. Ne fanno parte:
  - la libreria `CrashKit`: volume di lavoro APFS su immagine disco, istantanea del disco, log di intenti, passi idempotenti con la loro compensazione, classificatori degli errori e degli esiti, riconoscimento e recupero in un nuovo processo, matrice degli arresti;
  - l'eseguibile `crashbench`, con un sottocomando per azione;
  - la suite `CrashKitTests`, eseguita con Swift Testing, che dipende anche da `crashbench` perché i test di integrazione eseguono il binario reale;
  - le fixture versionate in `fixtures/`: il lotto di prova `batch.json`, cinque coppie di immagine e sidecar e il manifest `MANIFEST.json`, con SHA-256 e dimensione di ogni file.

  È **deliberatamente fuori dalla mappa dei domini** e usa-e-getta: non anticipa la struttura dei pacchetti del prodotto e non va riusato. In particolare il suo log di intenti è un file JSONL e non prova il contratto di durabilità di `DurableState`. La decisione durevole che ne deriva è [Lotti di operazioni su file recuperabili con esiti dichiarati](/decisions/recoverable-file-batches.md).

Il resto del repository è documentazione di prodotto e configurazione di processo:

- `docs/PRD.md` — documento di prodotto, rappresentato come concetto di riferimento [PRD di iMAGE Surfer](/references/prd.md);
- `docs/wiki/` — radice della Wiki, esclusa dall'ispezione per contratto;
- `.archetipo/` e `.claude/` — configurazione di processo e definizioni delle capacità di lavoro, non codice di prodotto.

<!-- archetipo:wiki section=coverage -->

## Copertura

Esistono file sorgente, ma **nessun confine di capacità di prodotto**. `archetipo wiki inspect` restituisce un solo confine, `Spikes`, di tipo `source` con 65 file Swift, e nessun candidato di capacità. Il confine è rappresentato nella voce `coverage` del frontmatter con stato **`excluded`**: contiene i banchi di verifica usa-e-getta dei cancelli tecnici, oggi `Spikes/01-scale-memory/` (cancello n°1) e `Spikes/04-crash-recovery/` (cancello n°4), deliberatamente fuori dalla mappa dei domini. La conoscenza durevole che ne deriva è in [Ammissione del lavoro con stime calibrate e banda di ritenzione](/decisions/work-admission-budget.md) e in [Lotti di operazioni su file recuperabili con esiti dichiarati](/decisions/recoverable-file-batches.md). Non è registrata nessuna voce di capacità, perché non ce n'è alcuna da rappresentare.

Aree dichiarate come non ispezionate dallo strumento: `Spikes`, di cui viene letto solo un campione rappresentativo dei file. Oggi il campione conta 8 file, tutti della suite `BenchKitTests` di `Spikes/01-scale-memory/`. L'inventario dei test elenca invece le suite di entrambi i banchi, `BenchKitTests` e `CrashKitTests`. Esclusioni riportate: metadati del repository, directory di dipendenze e build, radice della Wiki configurata.

La pagina era ancorata alla radice del progetto perché la sua affermazione centrale era l'assenza di codice. Comparsa la prima directory sorgente reale, l'ancoraggio è stato ristretto a `Spikes/01-scale-memory`; con il secondo banco si aggiunge `Spikes/04-crash-recovery`, più `docs` per la documentazione. Le directory del codice di prodotto si aggiungeranno quando esisteranno.

## Concetti collegati

- [Panoramica](/overview.md)
- [Mappa dei contesti](/architecture/context-map.md)
- [Sviluppo e operatività](/operations/development.md)
- [Ammissione del lavoro con stime calibrate e banda di ritenzione](/decisions/work-admission-budget.md) — la decisione derivata dal banco del cancello n°1
- [Lotti di operazioni su file recuperabili con esiti dichiarati](/decisions/recoverable-file-batches.md) — la decisione derivata dal banco del cancello n°4
