# Project Wiki

## Architecture

* [Mappa dei contesti](architecture/context-map.md) - Confini logici di iMAGE Surfer; nessun contesto è evidenziato da codice di prodotto, le dodici aree previste dal PRD sono registrate come non risolte, ADR-009 e ADR-007 sono chiusi dai cancelli n°1 e n°4 e tre ADR restano provvisori. _State: reviewed._

## Decisions

* [Lotti di operazioni su file recuperabili con esiti dichiarati](decisions/recoverable-file-batches.md) - ADR-007 emendato dal cancello n°4; lotti recuperabili e non atomici con sei esiti dichiarati, i cinque del PRD con «compensato» ridefinito più «interrotto prima di agire», ed errori classificati per ambito, con tre classi sistemiche che sospendono il lotto e cinque locali che fanno saltare il file. _State: reviewed._
* [Ammissione del lavoro con stime calibrate e banda di ritenzione](decisions/work-admission-budget.md) - Code specializzate per tipo sotto budget comune, con stime al p95 per cella calibrate dal cancello n°1, riserva fissa per tipo di lavoro, limite per singolo elemento e banda di ritenzione 0,5/1,0 schermate. _State: reviewed._

## Engineering

* [Mappa del codice](engineering/code-map.md) - Crosswalk fisico da domini a codice; tutto il codice del repository sta nei due banchi di verifica usa-e-getta dei cancelli n°1 e n°4, fuori da ogni dominio di prodotto, quindi la mappa dei domini è vuota. _State: reviewed._

## Operations

* [Sviluppo e operatività](operations/development.md) - Build, test, esecuzione e distribuzione previsti per iMAGE Surfer; esistono solo le toolchain SwiftPM dei banchi dei cancelli tecnici sotto Spikes/, nessuna toolchain di prodotto né integrazione continua. _State: reviewed._

## Project

* [iMAGE Surfer](overview.md) - Applicazione macOS nativa per browsing, triage e riorganizzazione di immagini in cartelle; stato attuale del repository e ambito della mappa. _State: reviewed._

## References

* [PRD di iMAGE Surfer](references/prd.md) - Documento di requisiti di prodotto di iMAGE Surfer, dalla sessione di inception del 2026-08-24 e dalle tre revisioni architetturali esterne; unica fonte dell'intento in assenza di codice. _State: generated._
