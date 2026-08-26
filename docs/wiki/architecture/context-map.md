---
type: context-map
title: Mappa dei contesti
description: Confini logici di iMAGE Surfer; nessun contesto è evidenziato da codice, le dodici aree previste dal PRD 1.2 sono registrate come non risolte e cinque ADR sono ancora provvisori
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
| Catalogo cartella | enumerazione, filtro per tipo immagine, identità dalle primitive di sistema e validità come chiavi distinte, osservazione con riconciliazione per differenza e tempo massimo, ordinamenti | nessuna |
| Metadati | lettura e normalizzazione di EXIF/IPTC/GPS e proprietà immagine | nessuna |
| Sidecar | lettura e scrittura atomica del singolo file XMP affiancato, coordinamento tra processi, controllo sulla versione osservata, conflitto esplicito, conservazione dei campi di terzi | nessuna |
| Anteprime | generazione, cache su disco, decodifica sempre ridimensionata | nessuna |
| Ammissione del lavoro | code specializzate per tipo sotto budget di memoria comune misurato, banda di ritenzione con isteresi | nessuna |
| Duplicati | duplicati esatti per contenuto a stadi di costo crescente e gruppi di quasi-duplicati | nessuna |
| Qualità e selezione | soggetto, qualità tecnica, punteggio estetico, punteggio scomposto con sovrapposizioni dichiarate e versionamento semantico | nessuna |
| Accesso al filesystem | punto unico di scrittura, bookmark delle cartelle, richiesta contestuale dei permessi | nessuna |
| Operazioni su file | macchina a stati con log di intenti, ricontrollo delle precondizioni, passi idempotenti, ripresa o compensazione, Cestino | nessuna |
| Cache derivata | archivio eliminabile dei soli dati ricalcolabili | nessuna |
| Stato durevole | archivio non eliminabile: registro delle operazioni, lotti aperti, scritture in attesa o fallite, stato di sincronizzazione | nessuna |
| Interfaccia | griglia, anteprima grande, pannello metadati, mappa dei tasti | nessuna |

<!-- archetipo:wiki section=relationships -->

## Relazioni

Nessuna relazione tra contesti è osservabile: non esistendo codice, non esistono collaborazioni, contratti o dipendenze da classificare. **Nessun nome di relazione DDD viene assegnato**, in nessun caso, perché nessuno sarebbe supportato da evidenza.

La sola dipendenza direzionale documentata nel PRD, e da verificare quando il codice esisterà, è che le aree previste consumano servizi del sistema operativo (anteprime, lettura immagini, visione artificiale, Cestino, eventi del filesystem) e non li incapsulano in un livello proprio, tranne che per l'accesso in scrittura al filesystem, che il PRD prescrive concentrato in un unico punto.

<!-- archetipo:wiki section=shared -->

## Infrastruttura condivisa

Nessuna infrastruttura condivisa è presente nel repository. Il PRD 1.2 distingue **tre nature di dato** con garanzie diverse e prescrive quattro elementi trasversali che, quando esisteranno, andranno mappati qui:

- la **cache derivata**, archivio eliminabile dei soli dati **ricalcolabili** (metadati, hash già calcolati, dati di similarità, anteprime, punteggi), più una copia dei giudizi per filtrare e ordinare;
- lo **stato durevole**, archivio **fisicamente separato e non eliminabile dall'interfaccia**: registro delle operazioni, lotti non completati, giudizi non ancora scritti nei sidecar o con scrittura fallita, stato di sincronizzazione. La separazione fisica, e non solo logica, è deliberata: il comando di svuotamento agisce su un file, quindi un archivio unico renderebbe impossibile offrirlo senza distruggere il registro;
- il **sidecar XMP affiancato**, sede portabile dei giudizi, che il PRD distingue dalla cache perché non è ricostruibile da nessuna sorgente;
- il **livello unico di accesso in scrittura al filesystem**, punto d'innesto dichiarato per una futura sandbox e sede della richiesta contestuale dei permessi;
- l'**ammissione del lavoro**, che il PRD 1.2 non modella più come coda unica ma come code specializzate per tipo sotto una politica di budget comune con costi misurati.

Il vocabolario dei contratti è dichiarato e va rispettato quando la Wiki descriverà il codice: **ricostruibile** per la cache derivata, **recuperabile** (non atomico) per un lotto di operazioni su file, **best-effort** per il recupero dell'associazione tra giudizio e immagine nei casi dichiarati tali.

<!-- archetipo:wiki section=uncertainties -->

## Incertezze

- **Tutti i confini sono non risolti.** Le aree previste derivano dalla struttura di pacchetti proposta nel PRD, che è una proposta architetturale e non una constatazione. La loro effettiva granularità si deciderà su codice. Due revisioni successive hanno modificato l'elenco — la 1.1 ha estratto sidecar, pianificazione del lavoro e accesso al filesystem; la 1.2 ha scisso l'indice in due archivi — segno che la granularità proposta è ancora instabile.
- **Cinque ADR sono dichiarati provvisori dal PRD stesso.** ADR-007 (recuperabilità dei lotti), 009 (code e budget), 011 (identità e matrice dei casi), 012 (eventi del filesystem) e 013 (sidecar XMP) sono subordinati all'esito di quattro cancelli tecnici che precedono la costruzione. Finché quei cancelli non producono un esito scritto, le aree che ne dipendono non sono solo prive di codice: sono prive di una decisione chiusa. Questa è la principale incertezza della mappa.
- **Il confine più incerto è quello tra sidecar, cache e stato durevole.** Il PRD 1.2 descrive tre sedi dello stesso giudizio con garanzie diverse, uno stato di sincronizzazione esplicito e conflitti non risolvibili in silenzio. Se sul codice quella macchina a stati risultasse sostanziale, la sincronizzazione dei giudizi diventerebbe una capacità a sé e non un dettaglio di tre componenti.
- Il PRD contiene assunti espressamente dichiarati da validare — combinazione di primitive di identità, convenzione di nome del sidecar, rappresentazione dello scarto, politica di conflitto in interfaccia, finestra di quiete e tempo massimo di riconciliazione, comportamento su volumi di rete e cartelle sincronizzate, costo in memoria per tipo di lavoro, ampiezza della banda di ritenzione, affidabilità dell'euristica sugli occhi, sovrapposizione tra qualità del volto e qualità tecnica, utilità del punteggio estetico, rinvio del supporto RAW, ricorsività delle operazioni massive — che possono modificare i confini prima che il codice esista. Sono attribuiti al PRD e non sono conoscenza verificata: vedi [PRD di iMAGE Surfer](/references/prd.md).

## Concetti collegati

- [Panoramica](/overview.md)
- [Mappa del codice](/engineering/code-map.md)
