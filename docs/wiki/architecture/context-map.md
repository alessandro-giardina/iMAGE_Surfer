---
type: context-map
title: Mappa dei contesti
description: Confini logici di iMAGE Surfer; nessun contesto è evidenziato da codice di prodotto, le dodici aree previste dal PRD sono registrate come non risolte, ADR-009 è chiuso dal cancello n°1 e quattro ADR restano provvisori
status: reviewed
sources:
    - path: .
      role: repository-inventory
    - path: docs/PRD.md
      role: product-intent
review:
    content_hash: sha256:f90557d3528c79d5882c1ea6b937a4105ca6c2ad9207f0dc12174e8cb0123e81
    evidence_revision: c3e7f7d9925451c8cee411c629402c840b557f5f
    evidence_hash: sha256:32c58789514ce568179732b636bd941db0b8ced2a0a33ab0e95d659268f13bec
    reviewed_at: "2026-11-16T10:03:25Z"
---
# Mappa dei contesti

<!-- archetipo:wiki section=contexts -->

## Contesti

**Nessun contesto delimitato e nessun candidato di capacità è oggi supportato da evidenza di codice di prodotto.** Non esistono sorgenti di prodotto, punti di ingresso dell'applicazione o schemi. L'unico codice del repository è il banco di misura usa-e-getta del cancello n°1 (`Spikes/01-scale-memory/`), deliberatamente fuori dalla mappa dei domini: vedi [Mappa del codice](/engineering/code-map.md).

Le aree di capacità **previste** dal PRD sono elencate qui sotto come attese di progettazione, non come contesti. Non hanno una pagina di dominio propria, e non ne avranno una fino a quando esisterà codice che ne dimostri il comportamento.

| Area prevista | Responsabilità attesa | Evidenza attuale |
|---|---|---|
| Catalogo cartella | enumerazione, filtro per tipo immagine, identità dalle primitive di sistema e validità come chiavi distinte, osservazione con riconciliazione per differenza e tempo massimo, ordinamenti | nessuna |
| Metadati | lettura e normalizzazione di EXIF/IPTC/GPS e proprietà immagine | nessuna |
| Sidecar | scrittura atomica del singolo file XMP affiancato, coordinamento **cooperativo** con controllo della versione dentro l'accesso coordinato, verifica dopo la sostituzione, recupero da scritture non coordinate, conservazione dei campi di terzi | nessuna |
| Anteprime | generazione, cache su disco, decodifica sempre ridimensionata | nessuna |
| Ammissione del lavoro | code specializzate per tipo sotto budget comune; **stime al p95 misurato per tipo di lavoro, formato e classe**, con margine 1,5, riserva fissa per tipo di lavoro e limite per singolo elemento; banda di ritenzione con isteresi a soglie dichiarate, entrata 0,5 e uscita 1,0 schermate | nessun codice di prodotto, ma una **politica misurata e chiusa** dal cancello n°1: [Ammissione del lavoro con stime calibrate e banda di ritenzione](/decisions/work-admission-budget.md) |
| Duplicati | duplicati esatti per contenuto a stadi di costo crescente e gruppi di quasi-duplicati | nessuna |
| Qualità e selezione | soggetto, qualità tecnica, punteggio estetico, punteggio scomposto con sovrapposizioni dichiarate e versionamento semantico | nessuna |
| Accesso al filesystem | punto unico di scrittura, bookmark delle cartelle, richiesta contestuale dei permessi. Confine **di codice**, non di sicurezza | nessuna |
| Operazioni su file | macchina a stati con log di intenti, ricontrollo delle precondizioni, passi idempotenti, **cinque esiti**, distinzione errore locale/sistemico, Cestino | nessuna |
| Cache derivata | archivio eliminabile dei soli dati ricalcolabili; **non autorevole**, può restare indietro ed essere riallineata | nessuna |
| Stato durevole | archivio non eliminabile **con contratto operativo proprio** (integrità, recupero da corruzione, retention limitata, disco pieno definito): registro, lotti aperti, scritture in attesa o fallite, stato di sincronizzazione | nessuna |
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
- l'**ammissione del lavoro**, che il PRD 1.2 non modella più come coda unica ma come code specializzate per tipo sotto una politica di budget comune. Il cancello n°1 ha **emendato** ADR-009: i costi sono ora **stime calibrate su misura**, non costi misurati al momento dell'ammissione. Ogni stima è il p95 della propria cella, con margine 1,5 e riserva fissa per le allocazioni una tantum dei framework. Un limite per singolo elemento ferma l'elemento anomalo, definito dal costo e non dai pixel. Attorno alla parte visibile resta una banda di ritenzione 0,5/1,0 schermate. I valori sono in `Spikes/01-scale-memory/RESULT.md` e valgono per l'hardware lì dichiarato.

Le tre sedi non sono tenute insieme da transazioni — il filesystem non ne offre — ma da un **invariante direzionale**: stato durevole e sidecar sono autorevoli, la cache può restare indietro ed essere riallineata, con ordine di scrittura dichiarato e riconciliazione delle righe non allineate al riavvio. Il PRD 1.2 affermava che i due archivi non condividessero invarianti; la 1.3 corregge: l'invariante esiste ed è direzionale.

Il vocabolario dei contratti è dichiarato e va rispettato quando la Wiki descriverà il codice: **ricostruibile** per la cache derivata, **recuperabile** (non atomico e non sempre concludibile) per un lotto di operazioni su file, **best-effort** per il recupero dell'associazione tra giudizio e immagine e per la protezione della scrittura del sidecar verso applicazioni che non si coordinano. Nessuno dei tre è *garantito*, e il PRD dichiara come regola che **un meccanismo cooperativo o best-effort non venga mai descritto come se fosse impositivo**.

<!-- archetipo:wiki section=uncertainties -->

## Incertezze

- **Tutti i confini sono non risolti.** Le aree previste derivano dalla struttura di pacchetti proposta nel PRD, che è una proposta architetturale e non una constatazione. La loro effettiva granularità si deciderà su codice. Due revisioni successive hanno modificato l'elenco — la 1.1 ha estratto sidecar, pianificazione del lavoro e accesso al filesystem; la 1.2 ha scisso l'indice in due archivi — segno che la granularità proposta è ancora instabile.
- **Quattro ADR restano provvisori.** Il PRD ne dichiarava provvisori cinque, subordinati all'esito di quattro cancelli tecnici che precedono la costruzione. Uno è ora chiuso: **ADR-009** (code e budget) ha un esito scritto dal cancello n°1, ed è **emendato** con valori misurati (`Spikes/01-scale-memory/RESULT.md`, [Ammissione del lavoro con stime calibrate e banda di ritenzione](/decisions/work-admission-budget.md)). Restano subordinati ai tre cancelli ancora aperti ADR-007 (recuperabilità dei lotti), 011 (identità e matrice dei casi), 012 (eventi del filesystem) e 013 (sidecar XMP). Finché quei cancelli non producono un esito scritto, le aree che ne dipendono non sono solo prive di codice: sono prive di una decisione chiusa. Resta la principale incertezza della mappa, ridotta di un ADR.
- **Una soglia del PRD è risultata non supportabile.** Su questa configurazione la sessione di lunga durata **cresce**: 6,75 MB/h, con intervallo di confidenza al 95% da 3,19 a 10,32 MB/h, distinguibile da zero. La parte di NFR-P9 «una sessione di lunga durata non mostra crescita monotona» è quindi registrata come non supportabile. La modifica proposta è una pendenza massima dichiarata di 16 MB/h su 60 minuti, sotto un tetto di picco di 560 MB. L'origine della crescita non è stata isolata. È un vincolo nuovo per l'area *Ammissione del lavoro* e per il test di lunga durata, non un'incertezza risolta.
- **Il confine più incerto è quello tra sidecar, cache e stato durevole.** Il PRD descrive tre sedi dello stesso giudizio con garanzie diverse, un invariante direzionale di autorità, uno stato di sincronizzazione esplicito e conflitti non risolvibili in silenzio nemmeno verso applicazioni che non si coordinano. Se sul codice quella macchina a stati risultasse sostanziale, la sincronizzazione dei giudizi diventerebbe una capacità a sé e non un dettaglio di tre componenti.
- **Il perimetro di sicurezza non coincide con nessun confine di questa mappa.** `Access` è un confine di codice; il processo resta unico, non in sandbox, e interpreta dati non fidati. ADR-016 registra il rischio come accettato per l'MVP e prevede l'isolamento futuro di decodifica e analisi in un processo separato: quando arriverà, sarà il primo confine **di sicurezza** del sistema e taglierà la mappa in modo trasversale alle aree qui elencate.
- Il PRD contiene assunti espressamente dichiarati da validare — combinazione di primitive di identità, convenzione di nome del sidecar, rappresentazione dello scarto, politica di conflitto in interfaccia, finestra di quiete e tempo massimo di riconciliazione, comportamento su volumi di rete e cartelle sincronizzate, affidabilità dell'euristica sugli occhi, sovrapposizione tra qualità del volto e qualità tecnica, utilità del punteggio estetico, rinvio del supporto RAW, ricorsività delle operazioni massive — che possono modificare i confini prima che il codice esista. Sono attribuiti al PRD e non sono conoscenza verificata: vedi [PRD di iMAGE Surfer](/references/prd.md).

## Concetti collegati

- [Panoramica](/overview.md)
- [Mappa del codice](/engineering/code-map.md)
- [Ammissione del lavoro con stime calibrate e banda di ritenzione](/decisions/work-admission-budget.md) — ADR-009 chiuso dal cancello n°1
