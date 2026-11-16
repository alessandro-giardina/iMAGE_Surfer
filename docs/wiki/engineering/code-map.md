---
type: code-map
title: Mappa del codice
description: Crosswalk fisico da domini a codice; l'unico codice del repository è il banco di misura usa-e-getta del cancello n°1, fuori da ogni dominio di prodotto, quindi la mappa dei domini è vuota
status: reviewed
sources:
    - path: Spikes/01-scale-memory
      role: implementation
    - path: docs
      role: documentation-inventory
coverage:
    - kind: boundary
      path: Spikes
      status: excluded
      note: Banco di misura usa-e-getta dei cancelli tecnici (oggi il solo Spikes/01-scale-memory, cancello n°1), deliberatamente fuori dalla mappa dei domini di prodotto e da non riusare; la conoscenza durevole che ne deriva è in decisions/work-admission-budget.
review:
    content_hash: sha256:20c37ff4062878d86135e5bd114abb90e1aff9f722c576c826a0f74a9b687a44
    evidence_revision: c3e7f7d9925451c8cee411c629402c840b557f5f
    evidence_hash: sha256:a8a501a1a9825d59967a9574695350e10c3556128ee83e91a05c75e50786de0c
    reviewed_at: "2026-11-16T10:03:25Z"
---
# Mappa del codice

<!-- archetipo:wiki section=domain-code -->

## Da dominio a codice

**La tabella è vuota perché esiste codice, ma non appartiene a nessun dominio di prodotto.** Il repository contiene la documentazione di prodotto (`docs/PRD.md`) e un solo pacchetto Swift: `Spikes/01-scale-memory/`, il banco di misura del cancello tecnico n°1. Il pacchetto ha un manifest SwiftPM, sorgenti, due eseguibili e una suite di test, ed è materiale di misura, non codice di prodotto. Non esistono punti di ingresso dell'applicazione, contratti pubblici, schemi di persistenza, automazioni o infrastruttura.

| Dominio | UI | Punti di ingresso | Logica applicativa/dominio | Dati posseduti | Integrazioni | Test | Pagina Wiki |
|---|---|---|---|---|---|---|---|
| — nessun dominio mappato — | — | — | — | — | — | — | — |

La struttura di directory prevista dal PRD (target applicativo Xcode sopra pacchetti SPM locali: `Catalog`, `Metadata`, `Thumbnails`, `Duplicates`, `Quality`, `FileOps`, `IndexStore`, `DesignSystem`) è **intento di progettazione documentato** e continua a non esistere su disco. `Spikes/` non la anticipa: il banco ha una struttura propria, libreria `BenchKit` più eseguibili, pensata per misurare e non per essere riusata. Attribuzione: [PRD di iMAGE Surfer](/references/prd.md).

<!-- archetipo:wiki section=shared -->

## Codice condiviso

Nessuno nel prodotto, che non ha ancora codice. Nel banco di misura la libreria `BenchKit` è condivisa dai due eseguibili `gen-dataset` e `bench` e dalla suite di test. È materiale di misura interno a `Spikes/01-scale-memory/` e non va condiviso con il prodotto.

<!-- archetipo:wiki section=unmapped -->

## Codice non mappato

Il solo codice del repository è fuori dalla mappa dei domini, per scelta:

- `Spikes/01-scale-memory/` — banco di misura del cancello tecnico n°1. È un pacchetto SwiftPM senza dipendenze esterne. Ne fanno parte:
  - la libreria `BenchKit`: campionatore `phys_footprint`, statistica delle ripetizioni, impronta hardware, schema dei risultati e banchi;
  - l'eseguibile `gen-dataset`, che genera il dataset sintetico da 50.000 file;
  - l'eseguibile `bench`, con un sottocomando per misura;
  - la suite `BenchKitTests`, eseguita con Swift Testing.

  È **deliberatamente fuori dalla mappa dei domini** e usa-e-getta: code, cache di anteprime e banda di ritenzione vi esistono nella forma minima che serve a misurarle e non vanno riusate. Il codice è scartabile, la decisione che ha prodotto no. La conoscenza durevole che ne deriva è [Ammissione del lavoro con stime calibrate e banda di ritenzione](/decisions/work-admission-budget.md).

Il resto del repository è documentazione di prodotto e configurazione di processo:

- `docs/PRD.md` — documento di prodotto, rappresentato come concetto di riferimento [PRD di iMAGE Surfer](/references/prd.md);
- `docs/wiki/` — radice della Wiki, esclusa dall'ispezione per contratto;
- `.archetipo/` e `.claude/` — configurazione di processo e definizioni delle capacità di lavoro, non codice di prodotto.

<!-- archetipo:wiki section=coverage -->

## Copertura

Esistono file sorgente, ma **nessun confine di capacità di prodotto**. `archetipo wiki inspect` restituisce un solo confine, `Spikes`, e nessun candidato di capacità. Il confine è rappresentato nella voce `coverage` del frontmatter con stato **`excluded`**: contiene il banco di misura usa-e-getta dei cancelli tecnici, oggi il solo `Spikes/01-scale-memory/`, deliberatamente fuori dalla mappa dei domini. La conoscenza durevole che ne deriva è in [Ammissione del lavoro con stime calibrate e banda di ritenzione](/decisions/work-admission-budget.md). Non è registrata nessuna voce di capacità, perché non ce n'è alcuna da rappresentare.

Aree dichiarate come non ispezionate dallo strumento: `Spikes`, di cui viene letto solo un campione rappresentativo dei file. Esclusioni riportate: metadati del repository, directory di dipendenze e build, radice della Wiki configurata.

La pagina era ancorata alla radice del progetto perché la sua affermazione centrale era l'assenza di codice. Comparsa la prima directory sorgente reale, l'ancoraggio è ristretto a `Spikes/01-scale-memory`, più `docs` per la documentazione. Le directory del codice di prodotto si aggiungeranno quando esisteranno.

## Concetti collegati

- [Panoramica](/overview.md)
- [Mappa dei contesti](/architecture/context-map.md)
- [Sviluppo e operatività](/operations/development.md)
- [Ammissione del lavoro con stime calibrate e banda di ritenzione](/decisions/work-admission-budget.md) — la decisione derivata dal banco
