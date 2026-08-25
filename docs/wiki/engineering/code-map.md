---
type: code-map
title: Mappa del codice
description: Crosswalk fisico da domini a codice; il repository non contiene codice applicativo, quindi la mappa è vuota per constatazione
status: generated
sources:
  - path: .
    role: repository-inventory
  - path: docs
    role: documentation-inventory
---
# Mappa del codice

<!-- archetipo:wiki section=domain-code -->

## Da dominio a codice

**La tabella è vuota per constatazione, non per omissione.** L'ispezione ha rilevato un solo file nel repository (`docs/PRD.md`) e nessun linguaggio, manifest, radice sorgente, punto di ingresso, contratto pubblico, rotta, schema, test, automazione o infrastruttura.

| Dominio | UI | Punti di ingresso | Logica applicativa/dominio | Dati posseduti | Integrazioni | Test | Pagina Wiki |
|---|---|---|---|---|---|---|---|
| — nessun dominio mappato — | — | — | — | — | — | — | — |

La struttura di directory prevista dal PRD (target applicativo Xcode sopra pacchetti SPM locali: `Catalog`, `Metadata`, `Thumbnails`, `Duplicates`, `Quality`, `FileOps`, `IndexStore`, `DesignSystem`) è **intento di progettazione documentato** e non esiste su disco. Attribuzione: [PRD di iMAGE Surfer](/references/prd.md).

<!-- archetipo:wiki section=shared -->

## Codice condiviso

Nessuno. Non esiste codice, quindi non esiste codice condiviso.

<!-- archetipo:wiki section=unmapped -->

## Codice non mappato

Nessun codice non mappato. L'unico contenuto del repository è documentazione di prodotto e configurazione di processo:

- `docs/PRD.md` — documento di prodotto, rappresentato come concetto di riferimento [PRD di iMAGE Surfer](/references/prd.md);
- `docs/wiki/` — radice della Wiki, esclusa dall'ispezione per contratto;
- `.archetipo/` e `.claude/` — configurazione di processo e definizioni delle capacità di lavoro, non codice di prodotto.

<!-- archetipo:wiki section=coverage -->

## Copertura

L'ispezione ha restituito **zero confini fisici e zero candidati di capacità**: non esiste alcun elemento da rappresentare in copertura, e la sezione `coverage` in frontmatter è di conseguenza assente anziché popolata con voci inventate.

Aree dichiarate come non ispezionate dallo strumento: inventario Git non disponibile, con ricalibrazione da filesystem. Esclusioni riportate: metadati del repository, directory di dipendenze e build, radice della Wiki configurata.

Questa pagina è ancorata alla radice del progetto perché la sua affermazione centrale è l'assenza di codice: qualunque file sorgente aggiunto in qualunque punto la rende obsoleta. Va restretta alle directory sorgente reali appena esistono.

## Concetti collegati

- [Panoramica](/overview.md)
- [Mappa dei contesti](/architecture/context-map.md)
- [Sviluppo e operatività](/operations/development.md)
