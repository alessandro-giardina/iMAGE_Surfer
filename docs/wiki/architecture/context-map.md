---
type: context-map
title: Mappa dei contesti
description: Confini logici di iMAGE Surfer; nessun contesto è evidenziato da codice, le undici aree di capacità previste dal PRD 1.1 sono registrate come non risolte
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
| Catalogo cartella | enumerazione, filtro per tipo immagine, identità e validità come chiavi distinte, osservazione del filesystem con riconciliazione per differenza, ordinamenti | nessuna |
| Metadati | lettura e normalizzazione di EXIF/IPTC/GPS e proprietà immagine | nessuna |
| Sidecar | lettura e scrittura atomica dei giudizi in XMP affiancato, conservazione dei campi di terzi, politica di conflitto con l'indice | nessuna |
| Anteprime | generazione, cache su disco, decodifica sempre ridimensionata | nessuna |
| Pianificazione del lavoro | ammissione a budget di memoria, priorità alle celle visibili, cancellazione immediata | nessuna |
| Duplicati | duplicati esatti per contenuto e gruppi di quasi-duplicati | nessuna |
| Qualità e selezione | soggetto, qualità tecnica, punteggio estetico, punteggio scomponibile | nessuna |
| Accesso al filesystem | punto unico di scrittura, bookmark delle cartelle, richiesta contestuale dei permessi | nessuna |
| Operazioni su file | rinomina e smistamento massivi, dry-run, journal, Cestino, file collegati mossi insieme all'immagine | nessuna |
| Indice locale | schema di persistenza, chiavi di identità e validità distinte, copia rapida dei giudizi | nessuna |
| Interfaccia | griglia, anteprima grande, pannello metadati, mappa dei tasti | nessuna |

<!-- archetipo:wiki section=relationships -->

## Relazioni

Nessuna relazione tra contesti è osservabile: non esistendo codice, non esistono collaborazioni, contratti o dipendenze da classificare. **Nessun nome di relazione DDD viene assegnato**, in nessun caso, perché nessuno sarebbe supportato da evidenza.

La sola dipendenza direzionale documentata nel PRD, e da verificare quando il codice esisterà, è che le aree previste consumano servizi del sistema operativo (anteprime, lettura immagini, visione artificiale, Cestino, eventi del filesystem) e non li incapsulano in un livello proprio, tranne che per l'accesso in scrittura al filesystem, che il PRD prescrive concentrato in un unico punto.

<!-- archetipo:wiki section=shared -->

## Infrastruttura condivisa

Nessuna infrastruttura condivisa è presente nel repository. Il PRD prescrive quattro elementi trasversali che, quando esisteranno, andranno mappati qui:

- l'**indice locale**, cache dei soli dati **ricalcolabili** (metadati, hash, dati di similarità, anteprime, punteggi), più una copia rapida dei giudizi per filtrare e ordinare;
- il **sidecar XMP affiancato**, sede durevole dei giudizi dell'utente, che il PRD distingue esplicitamente dalla cache perché non è ricostruibile da nessuna sorgente;
- il **livello unico di accesso in scrittura al filesystem**, punto d'innesto dichiarato per una futura sandbox e sede della richiesta contestuale dei permessi;
- lo **scheduler unico**, che ammette tutto il lavoro asincrono entro un budget di memoria dichiarato.

<!-- archetipo:wiki section=uncertainties -->

## Incertezze

- **Tutti i confini sono non risolti.** Le aree previste derivano dalla struttura di pacchetti proposta nel PRD, che è una proposta architetturale e non una constatazione. La loro effettiva granularità, e quali di esse siano davvero capacità autonome anziché infrastruttura, si deciderà su codice. La revisione 1.1 ne ha aggiunte tre (sidecar, pianificazione del lavoro, accesso al filesystem) estraendole da aree preesistenti: è un indizio che la granularità proposta sia ancora instabile.
- **Il confine più incerto è quello tra sidecar e indice.** Il PRD li descrive come due sedi dello stesso dato con garanzie diverse e una politica di conflitto dichiarata. Se sul codice quella politica risultasse più complessa di una regola sulla data di modifica, la riconciliazione dei giudizi diventerebbe una capacità a sé e non un dettaglio di due componenti.
- Il PRD contiene assunti espressamente dichiarati da validare — soglia di similarità, utilità del punteggio estetico, provenienza e peso del modello estetico, interoperabilità reale del sidecar, politica di conflitto, ampiezza della finestra di quiete degli eventi, valore del budget di memoria, rinvio del supporto RAW, ricorsività delle operazioni massive — che possono modificare i confini prima che il codice esista. Sono attribuiti al PRD e non sono conoscenza verificata: vedi [PRD di iMAGE Surfer](/references/prd.md).

## Concetti collegati

- [Panoramica](/overview.md)
- [Mappa del codice](/engineering/code-map.md)
