---
type: decision
title: Ammissione del lavoro con stime calibrate e banda di ritenzione
description: Code specializzate per tipo sotto budget comune, con stime al p95 per cella calibrate dal cancello n°1, riserva fissa per tipo di lavoro, limite per singolo elemento e banda di ritenzione 0,5/1,0 schermate
decision_status: accepted
status: generated
sources:
  - path: Spikes/01-scale-memory/RESULT.md
    role: verification
  - path: Spikes/01-scale-memory/measurements/item-cost-20261114T015242Z-d4448e56.json
    role: verification
  - path: Spikes/01-scale-memory/Sources/BenchKit/RetentionBand.swift
    role: implementation
---
# Ammissione del lavoro con stime calibrate e banda di ritenzione

Questa pagina registra la politica di ammissione del lavoro asincrono di iMAGE Surfer come chiusa dal cancello tecnico n°1. La fonte dei valori è `Spikes/01-scale-memory/RESULT.md`. Ogni cifra qui riportata vale per l'hardware dichiarato in quel documento: Apple M1 Pro, 32 GB, macOS 27.2.0, build 26B123.

<!-- archetipo:wiki section=context -->

## Contesto

Le forze che la decisione deve tenere insieme:

- **L'ammissione precede l'esecuzione.** Il costo di un lavoro va quindi **stimato** prima di eseguirlo, non misurato al momento dell'ammissione. La misura serve a calibrare la stima, non a sostituirla.
- **Le soglie del PRD erano dichiarate, non misurate.** ADR-009 ed NFR-P10 chiedevano stime «conservative e calibrate su misure reali» senza alcuna misura alle spalle. ADR-009 era fra i cinque ADR provvisori subordinati ai cancelli tecnici (vedi [Mappa dei contesti](/architecture/context-map.md)).
- **Una media non protegge dalla coda.** Un singolo elemento può costare molte volte il normale. Lo protegge solo una stima sulla coda della distribuzione, insieme a un limite per elemento che interrompe l'elemento invece del processo.
- **La memoria è il rischio di esaurimento silenzioso** che il PRD identifica su cartelle da decine di migliaia di immagini. Per questo NFR-P9 chiede un tetto dichiarato e verificato da un test.

Il cancello n°1 ha registrato ADR-009 come **emendato**. La politica descritta qui **sostituisce** la formulazione di ADR-009 nel PRD 1.3 (`docs/PRD.md`, riga 532). Il testo di sostituzione completo è in `RESULT.md` § *Esito*, e il PRD non è stato modificato. Le differenze rispetto al PRD sono quattro:

- il percorso di anteprima è fissato;
- le allocazioni una tantum dei framework diventano una riserva fissa per tipo di lavoro;
- l'elemento anomalo è definito dal costo misurato e non dai pixel;
- banda di ritenzione e soglie del test di lunga durata hanno valori numerici.

<!-- archetipo:wiki section=decision -->

## Decisione

Il lavoro asincrono passa da **code separate per tipo** sotto un **budget di memoria comune**: ingresso/uscita, decodifica, visione artificiale e modelli, archivio. I parametri del budget sono quelli misurati.

| Parametro | Valore | Misura |
|---|---|---|
| Percorso delle anteprime della griglia | Decodifica ridimensionata ImageIO (`CGImageSourceCreateThumbnailAtIndex`) a 480 pixel di lato su schermo a scala 2 | Prima schermata su 3.000 immagini: p95 441,8 ms con ImageIO, 1771,9 ms con Quick Look |
| Stima per elemento | p95 del picco transitorio della cella (tipo di lavoro × formato × classe di risoluzione), arrotondato per eccesso al decimo di MB; 65 celle calibrate | Decodifica da 0,71 a 3,91 MB mediani; visione da 1,74 a 4,33 MB mediani |
| Margine di sicurezza | 1,5 sulla stima | Copre il massimo osservato in 63 celle su 65 |
| Riserva fissa per tipo di lavoro | Almeno 17 MB per la visione, contata una volta per processo | Allocazione una tantum trattenuta di 16,88 MB in `vision:jpeg:L` |
| Fattore di scarto hardware | 1,5 su ogni grandezza per elemento, su ogni configurazione diversa da quella di misura | Ipotesi dichiarata, da sostituire con la misura a posteriori |
| Limite per singolo elemento | `max(1 MiB, max(4 × p95, 1,5 × massimo osservato))` per cella, da 1 a 60 MiB | Registrato con la sua formula nel JSON di `item-cost` |
| Elemento anomalo | Definito dal costo, non dai pixel; oltre la classe più grande ha una cella propria solo dove il costo cresce con i pixel (visione: stima 15,8 MB, limite 60 MiB) | TIFF da 192 MP: decodifica 2,36 MB contro 2,33 MB di un TIFF da 48 MP; visione 13,48 MB contro 3,60 MB |
| Banda di ritenzione | Entrata **0,5** schermate, uscita **1,0** schermate | 0 anteprime rigenerate su un'oscillazione di ±0,25 schermate, contro 228 senza isteresi |
| Memoria della banda | 48 anteprime a regime (33,2 MB), al massimo 66 in movimento (45,6 MB) | 691.200 byte per anteprima |
| Tetto di picco (NFR-P9) | 560 MB su 50.000 file con scorrimento continuo | Massimo misurato 372,8 MB × 1,5 |
| Pendenza ammessa in sessione lunga (NFR-P9) | 16 MB/h su 60 minuti | Misurata 6,75 MB/h, IC95 da 3,19 a 10,32 MB/h |

Ogni elemento è avvolto in un blocco di rilascio esplicito, la decodifica è sempre a dimensione dichiarata e il budget si riduce sotto pressione di memoria. Questi tre punti restano invariati rispetto al PRD.

<!-- archetipo:wiki section=alternatives -->

## Alternative valutate

- **Punto unico di ammissione con stima per pixel.** È scartato per due ragioni. Concentra in un componente la conoscenza di ogni tipo di lavoro e ne fa un collo di bottiglia. E i pixel non stimano il costo: non quello di un modello di visione o di un contenitore multipagina, e nemmeno quello della decodifica. Il cancello ha misurato che un JPEG da 1,9 MP costa in decodifica più di uno da 12,2 MP (3,18 contro 1,47 MB), e che un TIFF da 192 MP costa quanto uno da 48 MP.
- **Rilascio immediato di ciò che esce dalla porta di vista, senza banda.** È scartato con il costo di ricalcolo misurato. Senza isteresi un'oscillazione di ±0,25 schermate rigenera da 129 a 228 anteprime in 10 cicli, secondo la soglia di entrata. Con un divario di 0,25 schermate ne rigenera ancora da 75 a 108. Con il divario dichiarato di 0,5 non ne rigenera nessuna. Ogni anteprima rigenerata è lavoro appena svolto e buttato via.
- **Stima come media anziché p95.** È scartata con la coda misurata. Nella cella `vision:jpeg:L` il massimo osservato (20,15 MB) vale 3,42 volte la stima al p95 (5,9 MB) e più di cinque volte la mediana (3,60 MB): una stima sulla media sarebbe stata superata di un ordine di grandezza. Gli elementi anomali per pixel (192 MP) costano invece quanto la classe più grande nella decodifica. È la prova che la coda va calibrata sul costo osservato, non dedotta dalle dimensioni.

<!-- archetipo:wiki section=consequences -->

## Conseguenze

**Vantaggi.**

- Ogni tipo di lavoro ha stime proprie, quindi l'ammissione non dipende da un modello di costo unico.
- La banda dichiarata costa 33,2 MB a regime e protegge dal ricalcolo sul movimento piccolo.
- La navigazione resta reattiva con le code sature: lo spostamento della selezione costa al massimo 2,80 ms fino al fotogramma.

**Svantaggi.**

- La banda è **memoria occupata di proposito**: ogni mezza schermata in più di soglia di entrata costa 24 anteprime (16,6 MB). Va calibrata insieme al budget (NFR-P12), non scelta come costante dell'interfaccia.
- La coppia scelta non protegge da un'oscillazione di ±1 schermata, che rigenera 678 anteprime. Per azzerarla serve un divario di 2 schermate.
- Quick Look resta fuori dal budget, perché il suo costo vive nel servizio di sistema e non è osservabile nel processo.

**Implicazioni operative.**

- Le stime sono **rivedibili con la misura a posteriori**, e la prima occasione è il primo Mac da 8 GB disponibile.
- Il **test di lunga durata è parte del contratto**: con le soglie di 560 MB di picco e 16 MB/h di pendenza deve far fallire la build. Il riferimento è `bench scroll-memory --long-session 60`.
- Restano aperte tre indagini: la crescita di 6,75 MB/h in sessione lunga, i circa 0,7 MB trattenuti per elemento dalla scrittura in cache delle anteprime, e le allocazioni una tantum della visione.

**Vincolo di attribuzione.** Le cifre valgono per l'hardware dichiarato in `RESULT.md`: 32 GB di memoria, cioè **non** il Mac con meno memoria in target. Il PRD prescrive macOS 15 su Apple Silicon, quindi il minimo è un M1 con 8 GB. Il margine di sicurezza copre questo scarto con il fattore dichiarato di 1,5, che è un'ipotesi e non una misura. Va rivisto quando si misurerà su una configurazione più piccola.

<!-- archetipo:wiki section=verification -->

## Verifica

- `Spikes/01-scale-memory/RESULT.md` contiene le misure, le stime per cella, la banda, i limiti della misura, l'esito con i testi di sostituzione e le conseguenze per la costruzione.
- `Spikes/01-scale-memory/measurements/` versiona i sei JSON citati, con hardware completo e campioni:
  - `item-cost-20261114T015242Z-d4448e56.json`: le 65 celle e la cella di controllo;
  - `retention-band-20261113T224643Z-75091c70.json`: lo spazzolamento della banda;
  - `scroll-memory-20261113T225526Z-804a05bc.json`: picco e sessione lunga;
  - `first-screen-20261113T224511Z-24b45870.json` e `first-screen-20261113T224528Z-791e26a7.json`: la prima schermata, Quick Look e ImageIO;
  - `selection-latency-20261113T224606Z-cdf28c91.json`: la latenza della selezione.
- I sottocomandi che producono l'evidenza sono `bench item-cost --all`, `bench retention-band`, `bench scroll-memory --long-session 60`, `bench first-screen` e `bench selection-latency`, eseguiti con la procedura di `Spikes/01-scale-memory/PROCEDURE.md`.
- `Spikes/01-scale-memory/Sources/BenchKit/RetentionBand.swift` è la forma minima della banda con isteresi usata per la misura. È materiale usa-e-getta, non implementazione di prodotto.
- La suite `ResultTraceabilityTests` (`swift test --package-path Spikes/01-scale-memory`) verifica che ogni cifra delle tabelle di `RESULT.md` coincida con il proprio JSON, che l'esito abbia quattro voci con un solo marcatore ciascuna, e che ogni soglia mancata sia registrata come non supportabile.

Il codice di prodotto che adotterà questa politica non esiste ancora. Quando esisterà, la verifica di adozione passerà dal test di lunga durata del prodotto.

## Concetti collegati

- [Mappa dei contesti](/architecture/context-map.md) — l'area *Ammissione del lavoro*
- [Sviluppo e operatività](/operations/development.md) — l'esito dei cancelli tecnici
- [PRD di iMAGE Surfer](/references/prd.md) — ADR-009, NFR-P1, NFR-P9, NFR-P10, NFR-P12
