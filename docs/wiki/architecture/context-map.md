---
type: context-map
title: Mappa dei contesti
description: Confini logici di iMAGE Surfer; nessun contesto è evidenziato da codice, le capacità previste sono registrate come non risolte
status: generated
sources:
  - path: .
    role: repository-inventory
  - path: docs/PRD.md
    role: product-intent
---
# Mappa dei contesti

<!-- archetipo:wiki section=contexts -->

## Contesti

**Nessun contesto delimitato e nessun candidato di capacità è oggi supportato da evidenza di codice.** L'ispezione del repository ha restituito zero confini fisici e zero candidati: non esistono file sorgente, manifest, punti di ingresso, schemi o test.

Le aree di capacità **previste** dal PRD sono elencate qui sotto come attese di progettazione, non come contesti. Non hanno una pagina di dominio propria, e non ne avranno una fino a quando esisterà codice che ne dimostri il comportamento.

| Area prevista | Responsabilità attesa | Evidenza attuale |
|---|---|---|
| Catalogo cartella | enumerazione, filtro per tipo immagine, identità dei file, eventi del filesystem, ordinamenti | nessuna |
| Metadati | lettura e normalizzazione di EXIF/IPTC/GPS e proprietà immagine | nessuna |
| Anteprime | generazione, cache su disco, pianificazione con cancellazione | nessuna |
| Duplicati | duplicati esatti per contenuto e gruppi di quasi-duplicati | nessuna |
| Qualità e selezione | soggetto, qualità tecnica, punteggio estetico, punteggio scomponibile | nessuna |
| Operazioni su file | rinomina e smistamento massivi, dry-run, journal, Cestino | nessuna |
| Indice locale | schema di persistenza e validità della cache | nessuna |
| Interfaccia | griglia, anteprima grande, pannello metadati, mappa dei tasti | nessuna |

<!-- archetipo:wiki section=relationships -->

## Relazioni

Nessuna relazione tra contesti è osservabile: non esistendo codice, non esistono collaborazioni, contratti o dipendenze da classificare. **Nessun nome di relazione DDD viene assegnato**, in nessun caso, perché nessuno sarebbe supportato da evidenza.

La sola dipendenza direzionale documentata nel PRD, e da verificare quando il codice esisterà, è che le aree previste consumano servizi del sistema operativo (anteprime, lettura immagini, visione artificiale, Cestino, eventi del filesystem) e non li incapsulano in un livello proprio, tranne che per l'accesso in scrittura al filesystem, che il PRD prescrive concentrato in un unico punto.

<!-- archetipo:wiki section=shared -->

## Infrastruttura condivisa

Nessuna infrastruttura condivisa è presente nel repository. Il PRD prescrive due elementi trasversali che, quando esisteranno, andranno mappati qui: l'**indice locale** (cache buttabile di metadati, hash, dati di similarità, rating) e il **livello unico di accesso in scrittura al filesystem**, punto d'innesto dichiarato per una futura sandbox.

<!-- archetipo:wiki section=uncertainties -->

## Incertezze

- **Tutti i confini sono non risolti.** Le otto aree previste derivano dalla struttura di pacchetti proposta nel PRD, che è una proposta architetturale e non una constatazione. La loro effettiva granularità, e quali di esse siano davvero capacità autonome anziché infrastruttura, si deciderà su codice.
- Il progetto non è sotto controllo di versione Git al momento della compilazione, quindi la scoperta delle pagine impattate dal cambiamento (`wiki affected --base/--head`) non è utilizzabile finché non lo diventa.
- Il PRD contiene assunti espressamente dichiarati da validare — soglia di similarità, utilità del punteggio estetico, provenienza e peso del modello estetico, rinvio del supporto RAW, ricorsività delle operazioni massive — che possono modificare i confini prima che il codice esista. Sono attribuiti al PRD e non sono conoscenza verificata: vedi [PRD di iMAGE Surfer](/references/prd.md).

## Concetti collegati

- [Panoramica](/overview.md)
- [Mappa del codice](/engineering/code-map.md)
