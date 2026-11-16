# Cancello n°1 — Scala e memoria su 50.000 file: risultato

Esito scritto del cancello tecnico n°1 (spec US-001). Il documento pubblica le misure del banco in `Spikes/01-scale-memory/`, ne deriva le stime di costo per elemento e l'ampiezza della banda di ritenzione, e chiude **ADR-009**, **NFR-P1**, **NFR-P9** e **NFR-P10** del PRD.

Come leggerlo:

- Ogni cifra rimanda a un `measurementId`. Il JSON corrispondente è versionato in [`measurements/`](measurements/) e il test `ResultTraceabilityTests` verifica che ogni cifra delle tabelle coincida con il proprio JSON.
- Le tabelle numeriche sono generate dai JSON, non trascritte a mano. I decimali usano la virgola. **MB** vale 10⁶ byte, **MiB** 1.048.576 byte.
- La dispersione segue una sola convenzione. Il p95 interpola linearmente fra i ranghi (Hyndman & Fan, tipo 7, come `numpy.percentile`). La deviazione standard è campionaria, con denominatore n − 1. L'IQR è p75 − p25.
- La memoria è sempre `phys_footprint` del processo (`task_info(TASK_VM_INFO)`), la stessa grandezza che macOS usa per la pressione di memoria e che Xcode mostra come «Memory».
- La procedura per ripetere le misure è in [`PROCEDURE.md`](PROCEDURE.md).

## Hardware di misura

| Campo | Valore |
|---|---|
| Modello | MacBookPro18,3 |
| CPU | Apple M1 Pro |
| Core prestazionali / efficienti | 8 / 2 |
| Processori attivi | 10 |
| Memoria fisica | 34359738368 byte (32 GiB) |
| Filesystem del volume del dataset | apfs |
| Volume a stato solido | sì |
| Spazio libero sul volume (inizio della prima misura) | 344179093504 byte |
| macOS | 27.2.0 (build 26B123) |
| Swift (compilatore) / SDK | 6.4 / 27.2 |
| Alimentazione | rete elettrica |
| Modalità a basso consumo | disattivata |
| Stato termico all'inizio | nominal |

Tipo di disco: unità a stato solido interna, volume APFS. Il dataset e il banco risiedono sullo stesso volume.

**Ogni cifra di questo documento è attribuita a questa configurazione e a nessun'altra.**

Le condizioni sono state verificate prima e dopo ogni sottocomando e sono registrate nel JSON di ogni ripetizione:

- sessione grafica sbloccata;
- alimentazione di rete, modalità a basso consumo disattivata;
- stato termico `nominal` all'inizio e alla fine di **ogni** ripetizione di ogni misura citata;
- finestra del banco visibile e non occlusa;
- un'asserzione `ProcessInfo.beginActivity` attiva per tutta l'esecuzione (`parameters.sleepPrevention`).

Il display integrato (Built-in Retina Display, scala 2) è stato impostato a 1512×982 punti per tutta la durata delle misure, così che la finestra di strumentazione (1512×982 punti, 6 colonne di celle da 240 punti) stesse interamente su uno schermo a scala 2.

### Scarto rispetto al Mac con meno memoria in target

Il PRD prescrive di calibrare le stime «dal Mac con meno memoria in target in su» (`docs/PRD.md`, riga 180). Fissa la piattaforma in «macOS 15 o successivo su Apple Silicon» (riga 510) senza nominare un modello. La configurazione più piccola compatibile con quella frase è un Mac M1 con **8 GB** di memoria unificata e 4 core prestazionali più 4 efficienti.

La macchina di misura ha **32 GB**, 8 core prestazionali e 2 efficienti. Lo scarto è quindi:

- un fattore **4** sulla memoria fisica;
- metà dei core prestazionali;
- la stessa generazione di architettura: famiglia M1, stesso Neural Engine a 16 core, stesso motore multimediale per HEVC.

Nessuna misura è stata eseguita sulla configurazione da 8 GB. Il modo in cui le stime coprono questo scarto, e di quanto, è dichiarato in § *Stime di costo in memoria*.

## Misure grezze

Le quattro misure di AC-3, ciascuna con ripetizioni e dispersione.

### Tempo alla prima schermata su 3.000 immagini (NFR-P1)

Ogni ripetizione apre una cartella diversa da 3.000 file unici, **mai clonati e mai letti prima**. Le cartelle sono dieci (`p1-run-01` … `p1-run-10`): le dispari servono il percorso Quick Look, le pari il percorso ImageIO. Ogni ripetizione parte quindi a cache dei file fredda, senza `sudo purge`.

Prima della prima ripetizione la cache è stata verificata con `mmap` + `mincore` sui 200 file unici scritti subito dopo `p1-run-10`: risultavano residenti **0 pagine su 199.652**.

Le grandezze misurate sono quattro. Tutte partono dall'inizio dell'enumerazione della cartella. La prima schermata comprende le 24 celle della porta di vista iniziale (6 colonne × 4 righe).

| Chiave | Momento misurato |
|---|---|
| `firstUrlsReadyMs` | Gli URL della porta di vista sono disponibili. |
| `thumbnailsReadyMs` | È assegnata l'ultima anteprima della porta di vista. |
| `firstScreenMs` | Si completa la transazione Core Animation in cui quell'anteprima è stata assegnata (`CATransaction.setCompletionBlock`). |
| `compositionMs` | Differenza fra le due righe precedenti: il costo della composizione. |

Il percorso `quicklook` produce le anteprime con `QLThumbnailGenerator`. Il percorso `imageio` usa la decodifica ridimensionata `CGImageSourceCreateThumbnailAtIndex` a 480 pixel di lato. Nessuna ripetizione ha registrato anteprime fallite.

**Percorso `quicklook`** — cartelle p1-run-01, p1-run-03, p1-run-05, p1-run-07, p1-run-09

| Misura | Chiave | Unità | n | Mediana | p95 | Min | Max | Dev. std. | IQR | measurementId |
|---|---|---|---|---|---|---|---|---|---|---|
| Prima schermata visibile | `firstScreenMs` | ms | 5 | 884,4 | 1771,9 | 652,5 | 1776,9 | 542,8 | 932,0 | `24b45870-5d53-4120-9a20-2dff884bad0c` |
| Anteprime pronte | `thumbnailsReadyMs` | ms | 5 | 883,3 | 1770,9 | 651,5 | 1775,8 | 542,8 | 932,0 | `24b45870-5d53-4120-9a20-2dff884bad0c` |
| Primi URL disponibili | `firstUrlsReadyMs` | ms | 5 | 4,2 | 7,5 | 2,5 | 7,8 | 2,1 | 2,5 | `24b45870-5d53-4120-9a20-2dff884bad0c` |
| Composizione (differenza) | `compositionMs` | ms | 5 | 1,0 | 1,1 | 1,0 | 1,1 | 0,0 | 0,0 | `24b45870-5d53-4120-9a20-2dff884bad0c` |

**Percorso `imageio`** — cartelle p1-run-02, p1-run-04, p1-run-06, p1-run-08, p1-run-10

| Misura | Chiave | Unità | n | Mediana | p95 | Min | Max | Dev. std. | IQR | measurementId |
|---|---|---|---|---|---|---|---|---|---|---|
| Prima schermata visibile | `firstScreenMs` | ms | 5 | 392,2 | 441,8 | 280,3 | 447,7 | 67,8 | 87,9 | `791e26a7-0932-4b08-b2af-43e5319a70d1` |
| Anteprime pronte | `thumbnailsReadyMs` | ms | 5 | 391,4 | 441,1 | 279,4 | 446,9 | 68,0 | 88,6 | `791e26a7-0932-4b08-b2af-43e5319a70d1` |
| Primi URL disponibili | `firstUrlsReadyMs` | ms | 5 | 7,8 | 14,8 | 6,0 | 15,8 | 3,9 | 3,0 | `791e26a7-0932-4b08-b2af-43e5319a70d1` |
| Composizione (differenza) | `compositionMs` | ms | 5 | 0,8 | 0,9 | 0,2 | 0,9 | 0,3 | 0,1 | `791e26a7-0932-4b08-b2af-43e5319a70d1` |

La composizione costa circa 1 ms con entrambi i percorsi. La differenza è tutta nella produzione delle anteprime:

- **ImageIO** ha mediana 392,2 ms e p95 441,8 ms.
- **Quick Look** ha mediana 884,4 ms e p95 1771,9 ms. Due ripetizioni su cinque superano 1,7 s.

### Spostamento della selezione sotto lavoro in sottofondo (NFR-P3)

Il banco esegue 200 spostamenti con le frecce, uno ogni 150 ms, sulla cartella da 50.000 file. Il percorso è a serpentina: destra sulle righe pari, sinistra sulle dispari, giù a fine riga, perché `NSCollectionView` non va a capo con la freccia destra. Ogni spostamento è iniettato con `NSApp.postEvent`.

Le code di lavoro sono tenute sature per tutta la misura:

| Coda | Elementi in attesa all'inizio | Elementi in attesa alla fine |
|---|---|---|
| Ingresso/uscita | 47.672 | 0 |
| Decodifica | 2.320 | 48.656 |
| Visione | 32.700 | 31.512 |

`selectionLatencyMs` va dall'iniezione dell'evento al completamento della transazione Core Animation in cui la selezione riflette il nuovo elemento. `selectionHandledMs` va dall'iniezione dell'evento alla notifica di cambio di selezione di `NSCollectionView`.

| Misura | Chiave | Unità | n | Mediana | p95 | Min | Max | Dev. std. | IQR | measurementId |
|---|---|---|---|---|---|---|---|---|---|---|
| Latenza fino al fotogramma | `selectionLatencyMs` | ms | 200 | 0,50 | 1,55 | 0,44 | 2,80 | 0,44 | 0,11 | `cdf28c91-87ea-4691-af7e-23ca51274bed` |
| Gestione dell'evento | `selectionHandledMs` | ms | 200 | 0,29 | 0,35 | 0,24 | 2,51 | 0,18 | 0,04 | `cdf28c91-87ea-4691-af7e-23ca51274bed` |

Spostamenti oltre 100 ms: **0 su 200**.

### Occupazione di picco su 50.000 file con scorrimento continuo (NFR-P9, prima parte)

Ogni ripetizione è una corsa completa sulla cartella `scroll-50k`, dalla prima all'ultima riga e ritorno, a 3 schermate al secondo:

- 50.000 file, di cui 2.800 unici e 47.200 cloni APFS;
- anteprime ImageIO;
- banda di ritenzione 0,5/1,0 schermate, quella raccomandata dal banco in § *Banda di ritenzione*.

Ogni corsa dura 1402 s ed è campionata a 50 ms. Il picco è il massimo campione della corsa. Il regime è la mediana dei campioni dell'ultimo terzo. Il footprint di partenza, dopo la prova a secco dell'host e prima della prima corsa, è 253,2 MB (`derived.baselineFootprintBytes`).

| Misura | Chiave | Unità | n | Mediana | p95 | Min | Max | Dev. std. | IQR | measurementId |
|---|---|---|---|---|---|---|---|---|---|---|
| Picco | `peakFootprintBytes` | MB | 5 | 281,7 | 356,4 | 256,8 | 372,8 | 45,0 | 16,2 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Picco sopra la baseline | `peakAboveBaselineBytes` | MB | 5 | 28,5 | 103,2 | 3,6 | 119,6 | 45,0 | 16,2 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Regime (ultimo terzo della corsa) | `plateauFootprintBytes` | MB | 5 | 249,8 | 270,9 | 225,7 | 275,0 | 17,9 | 11,4 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Crescita per 1000 elementi percorsi | `marginalBytesPer1000Items` | kB/1000 el. | 5 | -4,8 | 66,2 | -3822,3 | 72,7 | 1713,5 | 120,9 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Celle in vista con anteprima (mediana) | `visibleFilledFractionMedian` | % | 5 | 93,3 | 93,3 | 93,3 | 93,3 | 0,0 | 0,0 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Anteprime trattenute (mediana) | `retainedCountMedian` | n. | 5 | 55,0 | 56,0 | 55,0 | 56,0 | 0,5 | 1,0 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Anteprime trattenute (massimo) | `retainedCountMax` | n. | 5 | 66,0 | 66,0 | 66,0 | 66,0 | 0,0 | 0,0 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |

Come leggere i numeri:

- **Picco.** La prima corsa ha il picco più alto, 372,8 MB. Le altre quattro restano fra 256,8 e 290,9 MB. Il massimo, non la mediana, è la cifra che un tetto deve rispettare.
- **Crescita per elemento.** La crescita per 1000 elementi percorsi ha mediana −4,8 kB: l'occupazione non cresce con il numero di elementi attraversati.
- **Anteprime trattenute.** Restano fra 55 e 66, contro 50.000 elementi.
- **Copertura in vista.** A 3 schermate al secondo il 93,3% delle celle in vista ha già la propria anteprima (mediana).
- **Lavoro.** Ogni corsa produce circa 99.500 anteprime, due per elemento: andata e ritorno. Ne annulla circa 400 uscite dalla banda prima di completarle e non ne fallisce nessuna.

### Andamento in sessione di lunga durata (NFR-P9, seconda parte)

La sessione dura 60 minuti nello stesso processo, dopo le cinque corse. Alterna 120 raffiche di scorrimento da 20 s a 3 schermate al secondo, ciascuna seguita da 10 s di quiete. Il footprint è campionato a 50 ms: 72.024 campioni.

La pendenza principale si calcola sulle mediane al minuto (59 intervalli), escluso il primo minuto di apertura. L'intervallo di confidenza al 95% vale errore standard × 1,96.

La pendenza sui campioni a 50 ms è riportata come grandezza secondaria. Quei campioni sono autocorrelati, quindi il suo intervallo è ottimistico.

| Grandezza | Chiave | Unità | Valore | measurementId |
|---|---|---|---|---|
| Durata | `derived.longSession.minutes` | min | 60,0 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Pendenza (mediane al minuto, esclusa l'apertura) | `derived.longSession.longSessionSlopeBytesPerHour` | MB/h | 6,75 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Semiampiezza IC95 della pendenza | `derived.longSession.slopeConfidenceInterval95` | MB/h | 3,56 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Estremo inferiore IC95 | `derived.longSession.slopeConfidenceLow` | MB/h | 3,19 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Estremo superiore IC95 | `derived.longSession.slopeConfidenceHigh` | MB/h | 10,32 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Pendenza distinguibile da zero | `derived.longSession.slopeDistinguishableFromZero` | — | sì | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Pendenza sui campioni a 50 ms (secondaria) | `derived.longSession.raw50msSlopeBytesPerHour` | MB/h | 8,60 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Semiampiezza IC95 a 50 ms (ottimistica) | `derived.longSession.raw50msSlopeConfidenceInterval95` | MB/h | 0,24 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Picco della sessione | `derived.longSession.peakFootprintBytes` | MB | 244,7 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Footprint iniziale (primo minuto analizzato) | `derived.longSession.initialFootprintBytes` | MB | 189,5 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |
| Footprint finale (ultimo minuto) | `derived.longSession.finalFootprintBytes` | MB | 216,5 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |

| Misura | Chiave | Unità | n | Mediana | p95 | Min | Max | Dev. std. | IQR | measurementId |
|---|---|---|---|---|---|---|---|---|---|---|
| Pendenze delle 6 finestre | `derived.longSession.windowSlopesBytesPerHour` | MB/h | 6 | 16,93 | 100,20 | -27,84 | 120,78 | 49,90 | 23,40 | `804a05bc-2849-44e8-bee8-f7aa4ad165f8` |

Come leggere i numeri:

- **Andamento complessivo.** Il footprint passa da 189,5 MB nel primo minuto analizzato a 216,5 MB nell'ultimo: +27,0 MB in 59 minuti. La pendenza è 6,75 MB/h, con IC95 da 3,19 a 10,32 MB/h, **distinguibile da zero**.
- **Andamento per finestre.** Le pendenze delle sei finestre da 10 minuti vanno da −27,84 a +120,78 MB/h. La crescita non è quindi monotona minuto per minuto, ma la tendenza della sessione è positiva e statisticamente separata dallo zero.
- **Apertura.** Nel primo minuto il footprint è sceso di 63,6 MB rispetto all'apertura della sessione (`openingRampBytes`). Per questo il primo minuto è escluso.
- **Origine della crescita, non accertata.** Le anteprime trattenute sono limitate dalla banda, quindi la crescita non viene dal loro numero. Il banco non ne ha isolato l'origine: processo ospite, framework di sistema o frammentazione dell'allocatore.

## Stime di costo in memoria

`bench item-cost --all` misura il costo in memoria di un singolo elemento per ogni cella. Una cella è una combinazione di tipo di lavoro × formato × classe di risoluzione. I tipi di lavoro sono quelli delle code di ADR-009:

| Tipo di lavoro | Operazione misurata |
|---|---|
| `io` | Apertura del file e lettura delle chiavi di risorsa, senza decodifica. |
| `decode` | `CGImageSourceCreateThumbnailAtIndex` a 480 pixel di lato. |
| `quicklook` | `QLThumbnailGenerator`. |
| `vision` | `VNGenerateImageFeaturePrintRequest` più `VNDetectFaceLandmarksRequest`. |
| `store` | Scrittura dell'anteprima in un file di cache JPEG a qualità 0,8 e rilettura. L'anteprima d'ingresso è preparata prima della misura. |

Metodo:

- **Isolamento.** Ogni cella gira in un **sottoprocesso proprio**, così che cache e allocatore di una cella non contaminino la successiva.
- **Elementi.** In ogni sottoprocesso un elemento di riscaldamento, escluso dalla misura, precede 20 elementi distinti del pool: n = 20. Fanno eccezione le celle `anomalous`, che hanno tre elementi (punto 13 di § *Limiti della misura*).
- **Campionamento e baseline.** Per ogni elemento il campionatore a 5 ms parte prima della baseline. La baseline è la mediana di 20 campioni consecutivi entro l'1%.
- **Due grandezze per elemento.** Il **picco transitorio** è il massimo campione durante l'operazione meno la baseline. L'uscita dell'operazione resta viva fino all'ultima lettura, quindi il picco la contiene. Il **trattenuto** è il footprint dopo il drenaggio del pool di rilascio meno la baseline: rivela crescita di cache o perdite.
- **Cella di controllo.** La prima riga della tabella, `noop`, esegue la stessa misura senza alcuna operazione sugli elementi `jpeg`/`S`. È il fondo dello strumento.

Le colonne derivate seguono tre regole, dichiarate prima della misura:

- **Stima adottata.** È il p95 del picco transitorio, arrotondato per eccesso al decimo di MB.
- **Margine (stima/mediana).** È il margine implicito della stima sulla mediana della cella. Per le celle con mediana zero è indicato «—».
- **Limite per elemento.** È `max(1 MiB, arrotondamento per eccesso al MiB di max(p95 × 4, massimo × 1,5))`. La formula è registrata come stringa nel JSON (`perItemLimitFormula`), insieme ai valori che l'hanno prodotta.

### Margine di sicurezza e scarto di hardware

La macchina di misura ha 32 GB e **non** è il Mac con meno memoria in target, che ha 8 GB (§ *Hardware di misura*). Le stime sono quindi usate con due fattori dichiarati e distinti.

1. **Margine di sicurezza: ×1,5 sulla stima adottata.**
   - Sul Mac di misura la stima con margine (stima adottata × 1,5) deve coprire il massimo osservato della cella.
   - La verifica cella per cella decide NFR-P10 in § *Esito*.
2. **Fattore di scarto hardware: ×1,5 su ogni configurazione non misurata.**
   - Su qualunque Mac diverso da quello di misura, e in particolare su quello da 8 GB, ogni grandezza per elemento si moltiplica per 1,5: la stima con margine e il limite per elemento. Sul Mac di misura il fattore vale 1.
   - **Quanto copre:** un costo per elemento fino al 50% più alto di quello misurato qui.
   - **Perché, come ipotesi:** il costo di un elemento è fissato da dimensioni in pixel, formato e buffer dei framework, che sono gli stessi su ogni Mac Apple Silicon con lo stesso sistema. La memoria fisica non entra nel conto. Le differenze reali, cioè GPU a 7-8 core invece di 16 e comportamento sotto pressione di memoria, non sono state misurate.
   - Il fattore è un'**ipotesi dichiarata, non una misura**. Va sostituito con la misura a posteriori prevista da ADR-009 sul primo Mac da 8 GB disponibile. Lo scarto di memoria fisica (×4) non si traduce in un fattore sulle stime per elemento: si traduce in un budget complessivo più piccolo, che la costruzione dimensiona sulla memoria del Mac su cui gira.

| Lavoro | Formato | Classe | n | Picco mediano (MB) | Picco p95 (MB) | Picco max (MB) | Trattenuto mediano (MB) | Stima adottata (MB) | Margine (stima/mediana) | Limite per elemento (MiB) | measurementId |
|---|---|---|---|---|---|---|---|---|---|---|---|
| noop | jpeg | S | 20 | 0,00 | 0,03 | 0,03 | 0,00 | 0,1 | — | 1 | `31aee0e8-b6ea-4801-a515-2c36bc8bcc47` |
| io | jpeg | S | 20 | 0,00 | 0,02 | 0,02 | 0,00 | 0,1 | — | 1 | `5f1d4493-a6c5-43db-a176-9ab2504f2151` |
| io | jpeg | M | 20 | 0,00 | 0,03 | 0,03 | 0,00 | 0,1 | — | 1 | `dda77e4e-6868-473b-8ddf-ab2b0a810206` |
| io | jpeg | L | 20 | 0,00 | 0,02 | 0,02 | 0,00 | 0,1 | — | 1 | `9ee7bafd-b1ff-4452-952e-f303c5f78524` |
| io | heic | S | 20 | 0,00 | 0,03 | 0,03 | 0,00 | 0,1 | — | 1 | `8a7633d5-75db-4f0b-b7ea-94707f85fac3` |
| io | heic | M | 20 | 0,00 | 0,02 | 0,02 | 0,00 | 0,1 | — | 1 | `ac9ed58f-be29-4bab-938e-a35b777c462b` |
| io | heic | L | 20 | 0,00 | 0,02 | 0,03 | 0,00 | 0,1 | — | 1 | `04b2d333-7674-41c4-b085-087541bc4580` |
| io | png | S | 20 | 0,00 | 0,02 | 0,03 | 0,00 | 0,1 | — | 1 | `9bba7fc5-4c32-4af6-96df-1444d518df76` |
| io | png | M | 20 | 0,00 | 0,02 | 0,05 | 0,00 | 0,1 | — | 1 | `88bc9ac7-3b15-40c2-bac1-2faf8c14ae6c` |
| io | png | L | 20 | 0,00 | 0,02 | 0,05 | 0,00 | 0,1 | — | 1 | `cc432b74-6e4a-4073-bf48-c30cdfd76606` |
| io | tiff | S | 20 | 0,00 | 0,02 | 0,03 | 0,00 | 0,1 | — | 1 | `fb8b23d4-38e7-454b-8667-e7172130dd70` |
| io | tiff | M | 20 | 0,00 | 0,03 | 0,05 | 0,00 | 0,1 | — | 1 | `e492fd0c-20a5-4cb8-8f52-f22f0cba9a96` |
| io | tiff | L | 20 | 0,00 | 0,02 | 0,02 | 0,00 | 0,1 | — | 1 | `756b378d-6289-45d9-bcd7-c2b50de3464b` |
| io | tiff | anomalous | 3 | 0,02 | 0,02 | 0,02 | 0,02 | 0,1 | 6,10 | 1 | `b86f7fa8-6673-4635-8455-87bc7a9175cd` |
| decode | jpeg | S | 20 | 3,18 | 3,24 | 3,26 | 0,02 | 3,3 | 1,04 | 13 | `e53820c3-d78b-4747-a3e2-c34a7b309142` |
| decode | jpeg | M | 20 | 1,47 | 2,07 | 2,08 | 0,02 | 2,1 | 1,42 | 8 | `f43595a4-6fca-416c-a352-bb7fbdba5975` |
| decode | jpeg | L | 20 | 3,91 | 4,37 | 5,00 | 0,03 | 4,4 | 1,13 | 17 | `dcec968d-64b5-4613-993a-8a2ad38d4043` |
| decode | heic | S | 20 | 0,72 | 0,90 | 0,97 | 0,02 | 1,0 | 1,39 | 4 | `a487ea0d-7e23-494f-af45-f8785a9a509b` |
| decode | heic | M | 20 | 0,71 | 0,94 | 1,06 | 0,01 | 1,0 | 1,40 | 4 | `a0a8ed38-9a0c-4d34-96fb-1cf653106ce0` |
| decode | heic | L | 20 | 0,72 | 1,07 | 1,10 | 0,02 | 1,1 | 1,53 | 5 | `a6f4abbd-97cf-4b71-92ec-aafd14786a9c` |
| decode | png | S | 20 | 3,84 | 4,19 | 6,26 | 0,05 | 4,2 | 1,09 | 16 | `41988dc5-6e7c-44de-b996-5ac57d7d5bee` |
| decode | png | M | 20 | 1,53 | 2,09 | 2,61 | 0,02 | 2,1 | 1,37 | 8 | `25747ff1-4051-43ec-b7c6-403f2914ee76` |
| decode | png | L | 20 | 1,52 | 2,12 | 2,57 | 0,02 | 2,2 | 1,44 | 9 | `f0e3844d-1f4d-433b-9252-58e35b0cb9fd` |
| decode | tiff | S | 20 | 3,19 | 3,36 | 3,39 | 0,03 | 3,4 | 1,06 | 13 | `b52f5063-8d6d-4a2c-8828-34e9ab93f112` |
| decode | tiff | M | 20 | 1,55 | 2,08 | 2,47 | 0,02 | 2,1 | 1,36 | 8 | `8f74c1a5-d8de-4dcf-8524-3c2ec7efdee0` |
| decode | tiff | L | 20 | 2,33 | 2,85 | 2,90 | 0,09 | 2,9 | 1,25 | 11 | `8d1c3f78-066a-4f4b-9833-22e79103dda8` |
| decode | tiff | anomalous | 3 | 2,36 | 3,02 | 3,10 | 0,28 | 3,1 | 1,31 | 12 | `2e029c24-f724-43c1-93c6-45714df64993` |
| quicklook | jpeg | S | 20 | 0,03 | 0,10 | 0,11 | 0,00 | 0,1 | 3,05 | 1 | `858e6ef9-ffd4-420a-96ad-dd4261e7e173` |
| quicklook | jpeg | M | 20 | 0,04 | 0,08 | 0,08 | 0,01 | 0,1 | 2,44 | 1 | `1aefe717-a184-47c2-802a-99dcbeeea404` |
| quicklook | jpeg | L | 20 | 0,03 | 0,08 | 0,08 | 0,00 | 0,1 | 3,05 | 1 | `095526b1-56c0-487d-bfda-cb03750d29a7` |
| quicklook | heic | S | 20 | 0,03 | 0,10 | 0,10 | 0,00 | 0,1 | 3,05 | 1 | `18207692-2359-425e-98a1-76e9e3163728` |
| quicklook | heic | M | 20 | 0,03 | 0,08 | 0,10 | 0,00 | 0,1 | 3,05 | 1 | `1df1cc20-ad57-425c-855e-e997be0199e2` |
| quicklook | heic | L | 20 | 0,03 | 0,08 | 0,10 | 0,00 | 0,1 | 3,05 | 1 | `ed3c3eb2-b6b7-4570-8d79-9e598ee7745c` |
| quicklook | png | S | 20 | 0,03 | 0,08 | 0,10 | 0,00 | 0,1 | 3,05 | 1 | `fd4ff146-2116-4390-af0b-2f420038a313` |
| quicklook | png | M | 20 | 0,03 | 0,08 | 0,08 | 0,00 | 0,1 | 3,05 | 1 | `3b5d88e3-5706-4a02-9072-bd483efdda04` |
| quicklook | png | L | 20 | 0,03 | 0,07 | 0,08 | 0,00 | 0,1 | 3,05 | 1 | `6ba452e7-36b7-42e9-a998-656134b44c35` |
| quicklook | tiff | S | 20 | 0,03 | 0,08 | 0,11 | 0,00 | 0,1 | 3,05 | 1 | `309d0916-e228-4420-bd7b-a5dbfc031ac9` |
| quicklook | tiff | M | 20 | 0,03 | 0,07 | 0,08 | 0,00 | 0,1 | 3,05 | 1 | `201f671d-014c-4c0c-8388-4cd05865491a` |
| quicklook | tiff | L | 20 | 0,03 | 0,08 | 0,08 | 0,00 | 0,1 | 3,05 | 1 | `32f4e4ea-3e49-4a3b-b1a2-51984a7e0ca9` |
| quicklook | tiff | anomalous | 3 | 0,07 | 0,07 | 0,07 | 0,03 | 0,1 | 1,53 | 1 | `9b4a6436-8c98-4ac3-8e8a-9d216828b5b0` |
| vision | jpeg | S | 20 | 1,74 | 3,05 | 3,51 | 0,02 | 3,1 | 1,78 | 12 | `9ee291e0-430a-4e23-abd5-410272142027` |
| vision | jpeg | M | 20 | 2,98 | 4,20 | 4,23 | 0,02 | 4,2 | 1,41 | 17 | `d9e1f16e-78c7-40c3-9b3f-d379593e150d` |
| vision | jpeg | L | 20 | 3,60 | 5,88 | 20,15 | 0,05 | 5,9 | 1,64 | 29 | `34076a23-f695-4b2c-9a65-5de2960fffe2` |
| vision | heic | S | 20 | 2,01 | 3,28 | 3,29 | 0,10 | 3,3 | 1,64 | 13 | `ce9867fa-371a-4a24-993c-9cebd3314c99` |
| vision | heic | M | 20 | 2,33 | 4,38 | 4,42 | 0,07 | 4,4 | 1,88 | 17 | `ec94c987-f133-4304-9470-9d2e701d3b28` |
| vision | heic | L | 20 | 3,25 | 6,45 | 12,93 | 0,00 | 6,5 | 2,00 | 25 | `bea80980-8153-41ee-8f8e-0cedaf778bdc` |
| vision | png | S | 20 | 3,09 | 4,80 | 6,67 | 0,25 | 4,9 | 1,59 | 19 | `7ede8515-7fbd-4b40-bc47-b88ce15c1101` |
| vision | png | M | 20 | 4,15 | 6,24 | 6,24 | 0,03 | 6,3 | 1,52 | 24 | `23e7eb2b-ccd4-4800-9ebf-f2a74e272f9e` |
| vision | png | L | 20 | 4,33 | 5,16 | 5,18 | 0,03 | 5,2 | 1,20 | 20 | `5731aa8d-2cbf-46e9-a492-71460cbbfb76` |
| vision | tiff | S | 20 | 2,38 | 3,06 | 3,06 | 0,02 | 3,1 | 1,30 | 12 | `df33c8f8-e56a-4016-bc83-944a7bb3f0d1` |
| vision | tiff | M | 20 | 3,23 | 4,32 | 4,54 | 0,07 | 4,4 | 1,36 | 17 | `343e334e-a2cb-4a2a-b83d-799814fe76da` |
| vision | tiff | L | 20 | 3,60 | 4,71 | 5,13 | 0,04 | 4,8 | 1,33 | 18 | `8f7d53cd-1669-46c0-9c16-4f2843d95f5e` |
| vision | tiff | anomalous | 3 | 13,48 | 15,71 | 15,96 | -0,44 | 15,8 | 1,17 | 60 | `cc33dbdd-bdf0-491c-bbdf-380e3258b9fe` |
| store | jpeg | S | 20 | 0,69 | 1,23 | 1,29 | 0,67 | 1,3 | 1,89 | 5 | `7706e675-0d1f-460c-b692-7a8ed35fff66` |
| store | jpeg | M | 20 | 0,68 | 1,15 | 1,26 | 0,67 | 1,2 | 1,76 | 5 | `919206ad-76ea-4e5c-9af3-8700f6701c78` |
| store | jpeg | L | 20 | 0,69 | 1,20 | 1,36 | 0,67 | 1,3 | 1,89 | 5 | `73a78dfb-5367-4832-943c-037a187056fa` |
| store | heic | S | 20 | 0,67 | 0,99 | 1,05 | 0,67 | 1,0 | 1,49 | 4 | `d651dc54-2eea-4898-80ba-a5aa6d887265` |
| store | heic | M | 20 | 0,67 | 1,22 | 1,33 | 0,67 | 1,3 | 1,94 | 5 | `f3de6bb4-272b-4a15-ac0d-7bccd41f37dc` |
| store | heic | L | 20 | 0,91 | 1,23 | 1,26 | 0,67 | 1,3 | 1,43 | 5 | `e2a9ef05-8270-4609-b136-24682273de5b` |
| store | png | S | 20 | 0,70 | 1,16 | 1,34 | 0,67 | 1,2 | 1,70 | 5 | `6481b8b9-5ddc-4d76-99b4-bfe4005e69a0` |
| store | png | M | 20 | 0,67 | 1,03 | 1,31 | 0,67 | 1,1 | 1,64 | 4 | `e3de9c06-1e3c-4a9c-8c0c-24d176079cd5` |
| store | png | L | 20 | 0,70 | 1,23 | 1,33 | 0,67 | 1,3 | 1,87 | 5 | `074f084e-c596-4f2e-b0a8-4bb19af24006` |
| store | tiff | S | 20 | 0,70 | 1,26 | 1,31 | 0,67 | 1,3 | 1,87 | 5 | `2299387c-a94d-45d4-9b16-92f94659f3f3` |
| store | tiff | M | 20 | 0,69 | 0,89 | 1,00 | 0,67 | 0,9 | 1,31 | 4 | `02ed30b5-9895-4686-b25b-0118eb64df0b` |
| store | tiff | L | 20 | 0,77 | 1,25 | 1,26 | 0,67 | 1,3 | 1,69 | 5 | `a2a4a317-fc6b-4ecc-aac0-03b2151aa747` |
| store | tiff | anomalous | 3 | 0,87 | 1,10 | 1,13 | 0,72 | 1,2 | 1,38 | 5 | `e85e9aa4-77be-404c-b13d-52d2642b5cd2` |

Risultato unito: `d4448e56-759b-4cc6-ad46-0924343e54d1`.

Nessuna delle 1.215 operazioni misurate è fallita (`operationFailedCount` = 0 in ogni cella). Lettura per tipo di lavoro:

- **`io`.** Il costo è indistinguibile dal fondo dello strumento: massimi da 0,02 a 0,05 MB, contro 0,03 MB della cella `noop`.
- **`decode`.** Le mediane vanno da 0,71 a 3,91 MB e il trattenuto è trascurabile (0,02-0,09 MB), salvo la cella anomala (0,28 MB). **Il costo non cresce con i pixel del sorgente:**
  - un JPEG S da 1,9 MP costa 3,18 MB, più di un JPEG M da 12,2 MP (1,47 MB). Lo stesso accade per PNG S (3,84 MB) e PNG M (1,53 MB);
  - il TIFF anomalo da 192 MP costa 2,36 MB, come il TIFF L da 48 MP (2,33 MB);
  - HEIC resta fra 0,71 e 0,72 MB in ogni classe, cioè poco più dei 0,69 MB dell'anteprima prodotta.

  È la prova misurata che le dimensioni in pixel non stimano il costo e che la segmentazione per formato e classe è necessaria. L'ipotesi sul meccanismo (riduzione in fase di decodifica per fattori di 2 sui JPEG grandi, decodifica HEIC in hardware) non è verificata da questa misura.
- **`quicklook`.** Il costo nel processo è circa 0,03 MB e non contiene nemmeno l'anteprima prodotta: `peakNotObserved` in tutte le 243 misure. L'anteprima arriva in memoria condivisa con il servizio di sistema che la genera. Il costo reale sta fuori dal processo (punto 7 di § *Limiti della misura*), quindi **queste righe non sono stime utilizzabili per un budget**.
- **`vision`.** Le mediane vanno da 1,74 a 4,33 MB per le classi S, M e L. Il TIFF anomalo arriva a 13,48 MB, 3,7 volte il TIFF L (3,60 MB): la visione è l'unico lavoro il cui costo cresce con i pixel del sorgente. Nelle due celle di classe L con massimo fuori scala il massimo coincide con **un'allocazione una tantum** su uno solo dei 20 elementi, che resta nel processo dopo l'elemento:

  | Cella | Picco transitorio | Trattenuto | Elemento | Massimo degli altri 19 |
  |---|---|---|---|---|
  | `vision:jpeg:L` | 20,15 MB | 16,88 MB | secondo | 5,13 MB, sotto la stima adottata di 5,9 MB |
  | `vision:heic:L` | 12,93 MB | 11,78 MB | primo | 6,11 MB, sotto la stima adottata di 6,5 MB |

  È un costo fisso del framework, non un costo per elemento. I valori per elemento sono nel JSON unito (`transientPeakDeltaBytesPerItem`, `retainedDeltaBytesPerItem`).
- **`store`.** Le mediane vanno da 0,67 a 0,91 MB, attorno alla dimensione dell'anteprima riletta (0,69 MB). Ogni elemento lascia trattenuti 0,67-0,72 MB dopo il drenaggio. La causa, che sia la cache dell'allocatore o di ImageIO, non è stata indagata. In un archivio di anteprime reale questo trattenuto va osservato dalla misura a posteriori.

Il costo in memoria di un'anteprima trattenuta dalla banda è l'uscita della decodifica: **691.200 byte**, 480×360 pixel × 4 byte (`outputBytes` della cella `decode:jpeg:M`, `f43595a4-6fca-416c-a352-bb7fbdba5975`).

## Banda di ritenzione

Il banco `retention-band` misura che cosa costa un piccolo movimento di scorrimento per ogni coppia di soglie (entrata, uscita). Lavora sulla cartella da 50.000 file, al suo centro, e le soglie sono espresse in schermate di distanza dalla porta di vista. Le regole della banda sono tre:

- un elemento entra nella banda, cioè la sua anteprima viene richiesta, quando la sua distanza dalla porta di vista scende sotto la soglia di entrata;
- gli elementi in vista sono sempre richiesti;
- l'anteprima viene rilasciata quando la distanza supera la soglia di uscita.

Per ogni coppia il banco porta la vista a regime ed esegue due oscillazioni, entrambe a 3 schermate al secondo:

- 10 cicli di **±0,25 schermate**, il movimento piccolo di AC-5;
- 10 cicli di **±1 schermata**.

Per ciascuna conta le anteprime **rigenerate**, cioè rilasciate e poi richieste di nuovo. Ogni anteprima rigenerata è lavoro appena svolto e buttato via.

Lo spazzolamento dichiarato copre 15 coppie: soglia di entrata 0,5, 1, 2, 3 o 4 schermate, per un divario (uscita − entrata) di 0,5, 1 o 2 schermate. Fuori dallo spazzolamento ci sono altri due gruppi di righe:

- i **riferimenti senza isteresi** (uscita = entrata), cioè il rilascio immediato di ciò che esce dalla banda. È l'alternativa che ADR-009 scarta, qui misurata;
- le **righe supplementari** con divario 0,25, che mostrano dove l'oscillazione di ±0,25 comincia a rigenerare.

Le colonne della tabella:

| Colonna | Significato |
|---|---|
| Regime | Footprint del processo a vista ferma. Non è confrontabile fra righe: vedi il punto 11 di § *Limiti della misura*. |
| Trattenute | Anteprime trattenute a regime. |
| Rigenerate | Totale sui 10 cicli di ciascuna oscillazione. |
| Ritorno a regime | Tempo dalla fine dell'oscillazione al completamento delle rigenerazioni. |

| Entrata | Uscita | Regime (MB) | Trattenute | Rigenerate ±0,25 | Rigenerate ±1 | Ritorno a regime ±0,25 (ms) | Ritorno a regime ±1 (ms) | measurementId |
|---|---|---|---|---|---|---|---|---|
| 0,50 | 1,00 | 297,4 | 48 | 0 | 678 | 0 | 65 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 0,50 | 1,50 | 327,6 | 48 | 0 | 438 | 0 | 0 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 0,50 | 2,50 | 149,9 | 48 | 0 | 0 | 0 | 0 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 1,00 | 1,50 | 184,4 | 72 | 0 | 678 | 0 | 42 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 1,00 | 2,00 | 184,2 | 72 | 0 | 438 | 0 | 0 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 1,00 | 3,00 | 184,8 | 72 | 0 | 0 | 0 | 0 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 2,00 | 2,50 | 195,3 | 120 | 0 | 677 | 0 | 0 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 2,00 | 3,00 | 196,8 | 120 | 0 | 438 | 0 | 0 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 2,00 | 4,00 | 198,1 | 120 | 0 | 0 | 0 | 0 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 3,00 | 3,50 | 215,5 | 168 | 0 | 659 | 0 | 154 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 3,00 | 4,00 | 228,0 | 168 | 0 | 429 | 0 | 0 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 3,00 | 5,00 | 233,7 | 168 | 0 | 0 | 0 | 0 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 4,00 | 4,50 | 232,9 | 216 | 0 | 678 | 0 | 66 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 4,00 | 5,00 | 231,0 | 216 | 0 | 438 | 0 | 0 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 4,00 | 6,00 | 230,7 | 216 | 0 | 0 | 0 | 0 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |

**Riferimenti senza isteresi** (uscita = entrata)

| Entrata | Uscita | Regime (MB) | Trattenute | Rigenerate ±0,25 | Rigenerate ±1 | Ritorno a regime ±0,25 (ms) | Ritorno a regime ±1 (ms) | measurementId |
|---|---|---|---|---|---|---|---|---|
| 0,00 | 0,00 | 143,1 | 24 | 207 | 801 | 64 | 43 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 0,50 | 0,50 | 171,0 | 48 | 228 | 896 | 42 | 108 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 1,00 | 1,00 | 203,9 | 72 | 129 | 910 | 255 | 108 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 2,00 | 2,00 | 218,9 | 120 | 190 | 901 | 0 | 0 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 3,00 | 3,00 | 232,1 | 168 | 165 | 831 | 219 | 198 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 4,00 | 4,00 | 240,6 | 216 | 226 | 905 | 44 | 610 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |

**Righe supplementari** (uscita = entrata + 0,25)

| Entrata | Uscita | Regime (MB) | Trattenute | Rigenerate ±0,25 | Rigenerate ±1 | Ritorno a regime ±0,25 (ms) | Ritorno a regime ±1 (ms) | measurementId |
|---|---|---|---|---|---|---|---|---|
| 0,50 | 0,75 | 183,3 | 48 | 108 | 804 | 0 | 66 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 1,00 | 1,25 | 187,3 | 72 | 107 | 800 | 0 | 44 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 2,00 | 2,25 | 197,3 | 120 | 107 | 802 | 0 | 0 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 3,00 | 3,25 | 212,5 | 168 | 75 | 783 | 43 | 175 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |
| 4,00 | 4,25 | 232,9 | 216 | 108 | 804 | 0 | 552 | `75091c70-bde8-482d-8311-7a4944ffb6c1` |

Raccomandazione del banco: entrata 0,50, uscita 1,00 (15 coppie su 15 azzerano il ricalcolo sull'oscillazione piccola; scelta quella con soglia di uscita minima)

### Coppia dichiarata: entrata 0,5 schermate, uscita 1,0 schermate

Le due soglie sono distinte: l'anteprima viene richiesta entro mezza schermata dalla porta di vista e rilasciata solo oltre una schermata intera.

**Motivazione misurata** (`75091c70-bde8-482d-8311-7a4944ffb6c1`). Con questa coppia l'oscillazione di ±0,25 schermate rigenera **0 anteprime** in 10 cicli. Con la stessa soglia di entrata le altre forme di banda ne rigenerano molte di più:

| Coppia | Forma della banda | Anteprime rigenerate in 10 cicli di ±0,25 |
|---|---|---|
| 0,5 / 1,0 | Coppia dichiarata | 0 |
| 0,5 / 0,5 | Rilascio immediato, senza isteresi | 228 |
| 0,5 / 0,75 | Divario di 0,25 | 108 |

Ogni anteprima rigenerata è una decodifica da 480 pixel appena eseguita e buttata via. Lo stesso schema vale per ogni soglia di entrata dello spazzolamento:

| Forma della banda | Anteprime rigenerate in 10 cicli di ±0,25 |
|---|---|
| Senza isteresi | da 129 a 228 |
| Divario di 0,25 | da 75 a 108 |
| Divario di almeno 0,5 | 0 in tutte le 15 coppie |

Quindi:

- **Lo zero del divario 0,5 è atteso per costruzione.** Un'oscillazione di ±0,25 ha un'escursione di 0,5 schermate e non può portare un elemento oltre una soglia di uscita lontana almeno 0,5 dalla soglia di entrata. Lo dichiara anche il banco (`derived.geometryNote`). La misura conferma la geometria e quantifica che cosa costa non rispettarla.
- **La scelta.** Fra le 15 coppie che azzerano il ricalcolo il banco sceglie quella con la soglia di uscita minima, perché la banda è memoria occupata di proposito (NFR-P12).

**Memoria che la scelta comporta.** La coppia trattiene **48 anteprime a regime**: le 24 in vista e le 24 entro mezza schermata. Durante lo scorrimento continuo su 50.000 file ne trattiene al massimo **66** (`retainedCountMax`, `804a05bc-2849-44e8-bee8-f7aa4ad165f8`). Con 691.200 byte per anteprima (§ *Stime di costo in memoria*):

| Situazione | Anteprime trattenute | Memoria |
|---|---|---|
| A regime | 48 | 33,2 MB |
| In movimento, massimo osservato | 66 | 45,6 MB |
| Ogni mezza schermata in più di soglia di entrata | +24 | +16,6 MB |

**Che cosa la coppia non protegge.** L'oscillazione di ±1 schermata rigenera 678 anteprime con 0,5/1,0. Per azzerarla serve un divario di 2 schermate (0,5/2,5: 0 rigenerate), con le stesse 48 anteprime a regime ma una coda di uscita più lunga durante il movimento. La coppia è dimensionata sul movimento piccolo nominato da AC-5 e da NFR-P6. Un movimento di ±1 schermata non è piccolo, e su di esso rigenerare è il comportamento atteso.

## Limiti della misura

Ogni limite è dichiarato per intero. Nessuno è stato attenuato in fase di scrittura.

1. **Cloni APFS nella cartella da 50.000 file.**
   - `scroll-50k` contiene 2.800 file unici e 47.200 cloni `clonefile(2)`. I cloni condividono i blocchi fisici, quindi su quella cartella la lettura a freddo è **sottostimata**: un clone di un file già letto si legge dalla cache.
   - L'occupazione di memoria e il costo di decodifica restano reali, perché ogni clone viene decodificato da capo.
   - Le dieci cartelle da 3.000 file della prima schermata sono **uniche e non clonate**: la misura di NFR-P1 non ne è affetta.
2. **32 GB invece del Mac con meno memoria in target.** Il PRD prescrive di misurare dal Mac con meno memoria in target in su. La macchina di misura ha 32 GB contro gli 8 GB della configurazione più piccola compatibile con il PRD. Lo scarto è dichiarato in § *Hardware di misura* e coperto dal fattore dichiarato in § *Stime di costo in memoria*. Quel fattore è un'ipotesi, non una misura.
3. **Contenuto sintetico.**
   - Le immagini sono sintetiche: un gradiente, due ottave di rumore e una regione di dettaglio. La qualità di codifica è calibrata per centrare i byte per megapixel fotografici dichiarati in `dataset.json`.
   - Valori ottenuti (MB per megapixel, obiettivo fra parentesi): JPEG 0,357–0,358 (0,35); HEIC 0,164–0,197 (0,18); PNG 1,608–1,619 (1,5); TIFF 3,000–3,002 (3,0). Nessuna cella è fuori dalla tolleranza del ±20%. I valori per cella sono in `.data/dataset-manifest.json`, generato e non versionato.
   - Il contenuto sintetico non contiene volti. Il costo di `VNDetectFaceLandmarksRequest` misurato qui comprende la sola ricerca dei volti, non l'estrazione dei punti caratteristici: per fotografie con volti il costo della visione è un **limite inferiore**.
4. **Niente Xcode.**
   - Sulla macchina sono installati solo i Command Line Tools. Nessuna misura passa da `xcodebuild` e non esiste alcun test di interfaccia XCUITest.
   - Il banco è un eseguibile SwiftPM non impacchettato in un'app. Quick Look e Vision funzionano anche così: lo mostrano le misure stesse, che non registrano anteprime né analisi fallite.
5. **Limitazione termica.** Nessuna: tutte le ripetizioni di tutte le misure citate hanno stato termico `nominal` all'inizio e alla fine.
6. **Oracolo del fotogramma.** «Visibile» significa completamento della transazione Core Animation, non comparsa dei fotoni sul pannello. La presentazione aggiunge al più un intervallo di aggiornamento del display: 8,3 ms a 120 Hz, 16,7 ms a 60 Hz.
7. **Quick Look lavora fuori dal processo.** `QLThumbnailGenerator` delega la generazione a un servizio di sistema. La memoria di quel servizio non entra nel `phys_footprint` del banco, quindi le righe `quicklook` della tabella dei costi **sottostimano** il costo per il sistema. Allo stesso modo la decodifica HEIC usa con ogni probabilità il motore multimediale hardware: le sue allocazioni di superfici possono essere attribuite solo in parte al processo.
8. **Prima esecuzione completa scartata.**
   - Una prima esecuzione completa del banco si è svolta in parte a schermo bloccato. La finestra di strumentazione era occlusa e i timer rallentati.
   - Tutti i suoi risultati sono stati scartati. Restano in `runs/discarded-locked-screen/`, non versionati e non citati.
   - Il dataset è stato rigenerato da zero e ogni misura è stata ripetuta sulla stessa macchina, a schermo sbloccato, con le verifiche delle condizioni descritte in § *Hardware di misura*. Non si tratta di una ripetizione su configurazione diversa.
9. **Dieci cartelle di prima schermata invece di cinque.** Il piano prevedeva cinque cartelle disgiunte. Ne servono dieci perché la prima schermata si misura con due percorsi di anteprima e cinque ripetizioni ciascuno, e una cartella già letta non è più fredda. Il pre-volo sullo spazio ha accettato le dieci cartelle, quindi `firstScreenFolders.count` non è stato ridotto.
10. **Ordine dei banchi.** `retention-band` precede `scroll-memory`, perché la corsa da 50.000 file usa la coppia di soglie raccomandata dallo spazzolamento. PROCEDURE.md riporta lo stesso ordine.
11. **Footprint di regime della banda.** Lo spazzolamento della banda esegue tutte le coppie nello stesso processo, una dopo l'altra. Il footprint di regime di una riga contiene quindi anche la storia delle righe precedenti: la stessa banda d'entrata con 48 anteprime trattenute vale 297,4 MB in una riga e 149,9 MB in un'altra. Per questo la scelta della coppia si fonda sui conteggi di rigenerazione e di anteprime trattenute, che sono deterministici, e il costo in memoria della banda si calcola dalle anteprime trattenute per il costo misurato di un'anteprima.
12. **Pagine dei file nella cache durante il costo per elemento.** Le stesse immagini del pool sono lette da più tipi di lavoro in sequenza (decodifica, Quick Look, visione, archivio). Dal secondo tipo in poi si trovano quindi nella cache dei file. Le pagine di file pulite non entrano in `phys_footprint`: la cache influisce solo sui tempi di esecuzione, che questa misura non usa.
13. **Celle anomale con tre elementi.** Le celle `anomalous` del costo per elemento hanno n = 3, non 20: il dataset contiene tre TIFF 16000×12000, da circa 576 MB ciascuno. Per quelle righe p95 e limite derivano da tre campioni e valgono come ordine di grandezza, non come stima di coda.
14. **Celle sotto la risoluzione dello strumento.** La cella di controllo `noop` misura il fondo della strumentazione: p95 e massimo 0,03 MB. Le celle `io` hanno massimi da 0,02 a 0,05 MB, quindi un costo indistinguibile da quel fondo. Per loro la stima adottata (0,1 MB) e il limite minimo (1 MiB) sono convenzioni, non misure di coda.

## Esito

Quattro voci, una per ADR-009, NFR-P1, NFR-P9 e NFR-P10. Ognuna ha la stessa forma:

- il marcatore, **confermato** oppure **emendato**;
- se la soglia è raggiunta su questa configurazione;
- il testo del PRD, citato testualmente;
- la cifra che decide, con il suo `measurementId`;
- se la voce è emendata, il testo di sostituzione da usare nel PRD.

Le regole di decisione sono quelle fissate nel piano del cancello prima della misura. Il PRD non è modificato da questo documento.

### NFR-P1 — prima schermata su 3.000 immagini

**confermato** · Soglia raggiunta: sì

Testo del PRD (`docs/PRD.md`, riga 732):

> **NFR-P1** Alla prima apertura di una cartella con 3.000 immagini, la prima schermata di anteprime è visibile entro **1 secondo**; la griglia è navigabile mentre il resto continua a caricarsi in sottofondo.

Regola: confermato se il p95 di `firstScreenMs` sulle cinque ripetizioni sta entro 1 secondo per almeno uno dei due percorsi di anteprima.

Misura che decide:

- **Percorso ImageIO**: p95 **441,8 ms**, massimo 447,7 ms, su cinque cartelle fredde da 3.000 file (`791e26a7-0932-4b08-b2af-43e5319a70d1`).
- **Percorso Quick Look**: p95 1771,9 ms (`24b45870-5d53-4120-9a20-2dff884bad0c`). **Non** regge la soglia.
- **Griglia navigabile durante il caricamento**: con le code di decodifica, ingresso/uscita e visione sature, lo spostamento della selezione ha p95 1,55 ms e massimo 2,80 ms; 0 spostamenti su 200 oltre 100 ms (`cdf28c91-87ea-4691-af7e-23ca51274bed`).

La soglia è retta **solo dal percorso ImageIO**. La decodifica ridimensionata diventa quindi un vincolo per la costruzione (§ *Conseguenze per la costruzione*).

### NFR-P9 — tetto di memoria e sessione di lunga durata

**emendato** · Soglia raggiunta: no

Testo del PRD (`docs/PRD.md`, riga 740):

> **NFR-P9 Tetto di memoria dichiarato e verificato.** Esiste un limite superiore dichiarato all'occupazione di picco su una cartella da 50.000 immagini con scorrimento continuo, e una sessione di lunga durata non mostra crescita monotona. Entrambe le soglie sono verificate da un test automatico che fallisce la build quando vengono superate.

Regola: le due parti si decidono separatamente. Il tetto di picco diventa la cifra misurata più il margine dichiarato. L'assenza di crescita monotona si decide su `slopeDistinguishableFromZero` e sull'intervallo di confidenza, non sul segno della pendenza.

Misura che decide (`804a05bc-2849-44e8-bee8-f7aa4ad165f8`):

- **Tetto di picco, parte che regge.** Picco misurato su cinque corse complete di 50.000 file: mediana 281,7 MB, p95 356,4 MB, massimo **372,8 MB**. Con il margine dichiarato di 1,5 il tetto è 559,2 MB, arrotondato a **560 MB**.
- **Assenza di crescita, parte che non regge.** Nella sessione di 60 minuti la pendenza è **6,75 MB/h**, con IC95 da 3,19 a 10,32 MB/h, **distinguibile da zero**. Il footprint passa da 189,5 a 216,5 MB in 59 minuti.

La parte «non mostra crescita monotona» non regge su questa configurazione. Il testo di sostituzione la rimpiazza con una pendenza massima dichiarata.

**Testo di sostituzione:**

> **NFR-P9 Tetto di memoria dichiarato e verificato.** Su una cartella da 50.000 immagini con scorrimento continuo a 3 schermate al secondo, l'occupazione di picco del processo (`phys_footprint`) non supera **560 MB**. In una sessione di 60 minuti di scorrimento intermittente l'occupazione cresce al più di **16 MB/h** (pendenza delle mediane al minuto, escluso il primo minuto) e non supera il tetto di picco. I valori sono calibrati dal cancello n°1 su Apple M1 Pro con 32 GB: picco massimo misurato 372,8 MB; pendenza misurata 6,75 MB/h con intervallo di confidenza al 95% da 3,19 a 10,32 MB/h. Tetto e pendenza ammessa sono i valori misurati, il picco massimo e l'estremo superiore dell'intervallo, moltiplicati per il margine dichiarato di 1,5 e arrotondati per eccesso. Entrambe le soglie sono verificate da un test automatico che fallisce la build quando vengono superate.

### NFR-P10 — stime conservative calibrate e limite per elemento

**emendato** · Soglia raggiunta: sì

Testo del PRD (`docs/PRD.md`, riga 741):

> **NFR-P10 Il parallelismo è derivato da stime conservative calibrate.** Il lavoro passa da code specializzate per tipo, ammesse entro un budget di memoria comune. Poiché l'ammissione precede l'esecuzione, il costo è **stimato**: le stime sono conservative, segmentate per tipo di lavoro, formato, classe di risoluzione e hardware, **calibrate su misure reali**, dotate di margine di sicurezza, corrette dalla misura a posteriori, e affiancate da un **limite per singolo elemento** che interrompe l'elemento anomalo anziché il processo. Il budget si riduce sotto pressione di memoria. Nessuna immagine viene decodificata a piena risoluzione quando ne basta una ridimensionata.

Regola: confermato se, in ogni cella, la stima con il margine dichiarato copre il massimo osservato, **ed** esiste un limite per elemento che intercetta la cella degli anomali. Se la stima con margine non copre il massimo in qualche cella, la voce è emendata e il testo di sostituzione dichiara il margine effettivamente necessario.

Misura che decide (`d4448e56-759b-4cc6-ad46-0924343e54d1`, 65 celle, n = 20 per cella e n = 3 per le celle anomale):

1. **Copertura del massimo.** La stima adottata × 1,5 copre il massimo osservato in **63 celle su 65**. Le due celle scoperte sono entrambe di visione in classe L, e in entrambe il massimo è un'allocazione una tantum trattenuta dal processo. Tolta quell'allocazione, il massimo degli altri 19 elementi sta sotto la stima adottata.

   | Cella | Massimo | Stima adottata | Massimo / stima | Trattenuto dell'allocazione una tantum | Massimo degli altri 19 | measurementId |
   |---|---|---|---|---|---|---|
   | `vision:jpeg:L` | 20,15 MB | 5,9 MB | 3,42 | 16,88 MB | 5,13 MB | `34076a23-f695-4b2c-9a65-5de2960fffe2` |
   | `vision:heic:L` | 12,93 MB | 6,5 MB | 1,99 | 11,78 MB | 6,11 MB | `bea80980-8153-41ee-8f8e-0cedaf778bdc` |

   Il margine necessario a coprire il massimo con la sola stima per elemento è quindi **3,42**. Con una riserva fissa per l'allocazione una tantum resta **1,5**.
2. **Intercettazione degli anomali.** Nessun limite derivato dalla classe L intercetta gli elementi anomali (TIFF 16000×12000, 192 MP), perché con la decodifica a dimensione dichiarata non sono anomali in memoria:

   | Lavoro | TIFF anomalo, mediana | TIFF L, mediana | Limite della classe L |
   |---|---|---|---|
   | Decodifica | 2,36 MB (`2e029c24-f724-43c1-93c6-45714df64993`) | 2,33 MB (`8d1c3f78-066a-4f4b-9833-22e79103dda8`) | 11 MiB |
   | Visione | 13,48 MB, massimo 15,96 MB (`cc33dbdd-bdf0-491c-bbdf-380e3258b9fe`) | 3,60 MB (`8f7d53cd-1669-46c0-9c16-4f2843d95f5e`) | 18 MiB |

   La condizione non è soddisfatta nella forma prevista: l'anomalia che il limite deve fermare va definita dal costo misurato, non dai pixel del sorgente.

La voce è **emendata** per entrambe le ragioni. La soglia è raggiunta: NFR-P10 non fissa un valore numerico, e ogni sua condizione è realizzabile su questa configurazione con il margine e la riserva misurati: stime per cella calibrate, margine dichiarato, limite per elemento in ogni cella, nessuna operazione fallita.

**Testo di sostituzione:**

> **NFR-P10 Il parallelismo è derivato da stime conservative calibrate.** Il lavoro passa da code specializzate per tipo, ammesse entro un budget di memoria comune. Poiché l'ammissione precede l'esecuzione, il costo è **stimato**. La stima di un elemento è il **p95 misurato della sua cella** (tipo di lavoro × formato × classe di risoluzione × hardware), arrotondato per eccesso al decimo di MB, e si usa con un **margine di sicurezza di 1,5**. Le stime sono **calibrate su misure reali** e corrette dalla misura a posteriori. Le allocazioni una tantum dei framework, che restano nel processo dopo il primo elemento, sono una **riserva fissa per tipo di lavoro**, contata una volta e non per elemento: per la visione è di almeno 17 MB, contro 16,88 MB misurati. Senza la riserva, il margine necessario per coprire il massimo osservato sale a 3,42 nella visione di classe L. Su un hardware non ancora misurato ogni grandezza per elemento si moltiplica per un fattore di scarto di 1,5, fino alla misura a posteriori. Le stime sono affiancate da un **limite per singolo elemento**, `max(1 MiB, max(4 × p95, 1,5 × massimo osservato))` per cella, che interrompe l'elemento anziché il processo. L'elemento anomalo è definito dal costo misurato, non dai pixel del sorgente. Un'immagine oltre la classe di risoluzione più grande ha una cella propria per i lavori il cui costo cresce con i pixel, come la visione artificiale. Il budget si riduce sotto pressione di memoria. Nessuna immagine viene decodificata a piena risoluzione quando ne basta una ridimensionata.

### ADR-009 — code specializzate sotto stime calibrate, con banda di ritenzione

**emendato** · Soglia raggiunta: sì

Testo del PRD (`docs/PRD.md`, riga 532):

> **ADR-009 — Code specializzate sotto stime conservative calibrate, con banda di ritenzione.** *Decisione:* il lavoro asincrono passa da **code separate** — ingresso/uscita, decodifica, visione artificiale e modelli, archivio — coordinate da una politica di **budget di memoria comune**. Poiché l'ammissione precede l'esecuzione, il costo va **stimato**: le stime sono **conservative e calibrate su misure reali**, segmentate per tipo di lavoro, formato, classe di risoluzione e hardware, con margine di sicurezza, **misura a posteriori che ricalibra** e un **limite per singolo elemento** che interrompe l'elemento anomalo. Attorno alla parte visibile si mantiene una **banda di ritenzione con isteresi**; ogni elemento è avvolto in un blocco di rilascio esplicito; la decodifica è sempre a dimensione dichiarata; il budget si riduce sotto pressione di memoria. *Motivo:* tre correzioni. Un punto unico di ammissione concentra in un componente la conoscenza di ogni tipo di lavoro e ne fa un collo di bottiglia. Le dimensioni in pixel non stimano il costo di un modello, di una texture o di un contenitore multipagina. E la formulazione "costi misurati, non stimati" della revisione precedente descriveva qualcosa di impossibile: per ammettere un lavoro prima di eseguirlo bisogna stimarlo — la misura serve a **calibrare** la stima, non a sostituirla. Una media, per quanto misurata, non protegge dall'immagine anomala che consuma molte volte il normale. *Conseguenza:* nessun componente avvia lavoro fuori dalle code; stime, margini e limite per elemento sono parametri prodotti dal cancello n°1 e rivedibili con la misura a posteriori; **l'ampiezza della banda di ritenzione è un parametro del budget** e va calibrata insieme ad esso; il test di lunga durata è parte del contratto.

Regola: confermato se NFR-P1, NFR-P9 e NFR-P10 reggono **e** la banda di ritenzione ha una coppia di soglie che azzera il ricalcolo sull'oscillazione piccola. Altrimenti è emendato.

Misura che decide:

- **La condizione propria dell'ADR è raggiunta.** La coppia entrata 0,5 / uscita 1,0 schermate rigenera 0 anteprime sull'oscillazione di ±0,25 schermate, contro 228 senza isteresi alla stessa entrata (`75091c70-bde8-482d-8311-7a4944ffb6c1`).
- **Le altre condizioni no.** NFR-P1 regge solo con la decodifica ImageIO (`791e26a7-0932-4b08-b2af-43e5319a70d1`). NFR-P9 ed NFR-P10 sono emendati (`804a05bc-2849-44e8-bee8-f7aa4ad165f8`, `d4448e56-759b-4cc6-ad46-0924343e54d1`).

L'ADR è quindi emendato nelle parti che le misure precisano o contraddicono:

- il percorso di anteprima;
- la struttura delle stime: riserva fissa per tipo di lavoro, anomalia definita dal costo;
- i valori del margine, del limite e della banda;
- le soglie del test di lunga durata.

**Testo di sostituzione:**

> **ADR-009 — Code specializzate sotto stime conservative calibrate, con banda di ritenzione.** *Decisione:* il lavoro asincrono passa da **code separate** — ingresso/uscita, decodifica, visione artificiale e modelli, archivio — coordinate da una politica di **budget di memoria comune**. Le anteprime della griglia sono prodotte dalla **decodifica ridimensionata di ImageIO**, a dimensione dichiarata: 480 pixel di lato su schermo a scala 2. Quick Look non è nel percorso della prima schermata (p95 misurato 1771,9 ms su 3.000 immagini, contro 441,8 ms della decodifica ridimensionata). Poiché l'ammissione precede l'esecuzione, il costo va **stimato**. La stima di un elemento è il **p95 misurato della sua cella** (tipo di lavoro × formato × classe di risoluzione × hardware), arrotondato per eccesso al decimo di MB, con **margine di sicurezza 1,5**. Le allocazioni una tantum dei framework sono una **riserva fissa per tipo di lavoro**: almeno 17 MB per la visione. Su un hardware non ancora misurato ogni grandezza per elemento si moltiplica per un **fattore di scarto 1,5**, finché la **misura a posteriori** non la ricalibra. Un **limite per singolo elemento**, `max(1 MiB, max(4 × p95, 1,5 × massimo osservato))`, interrompe l'elemento che lo supera. L'elemento anomalo è definito dal costo misurato, non dai pixel: un TIFF da 192 MP costa in decodifica quanto uno da 48 MP (2,36 contro 2,33 MB), mentre la visione artificiale cresce con i pixel (13,48 contro 3,60 MB) e ha una cella propria oltre la classe di risoluzione più grande. Attorno alla parte visibile si mantiene una **banda di ritenzione con isteresi**, con entrata a 0,5 e uscita a 1,0 schermate. La banda azzera il ricalcolo su un'oscillazione di ±0,25 schermate, che senza isteresi rigenera 228 anteprime, e trattiene 48 anteprime a regime (33,2 MB). Ogni elemento è avvolto in un blocco di rilascio esplicito. Il budget si riduce sotto pressione di memoria. *Motivo:* tre correzioni. Un punto unico di ammissione concentra in un componente la conoscenza di ogni tipo di lavoro e ne fa un collo di bottiglia. Le dimensioni in pixel non stimano il costo di un modello, di una texture o di un contenitore multipagina: il cancello n°1 l'ha misurato anche per la decodifica, dove un JPEG da 1,9 MP costa più di uno da 12,2 MP (3,18 contro 1,47 MB). E la formulazione "costi misurati, non stimati" descriveva qualcosa di impossibile: per ammettere un lavoro prima di eseguirlo bisogna stimarlo, e la misura serve a **calibrare** la stima, non a sostituirla. Una media non protegge dalla coda: il massimo osservato arriva a 3,42 volte la stima in una cella, per un'allocazione una tantum che la riserva fissa assorbe. *Conseguenza:* nessun componente avvia lavoro fuori dalle code. Stime, margine, riserve, fattore di scarto e limite per elemento sono parametri prodotti dal cancello n°1 su Apple M1 Pro con 32 GB e rivedibili con la misura a posteriori, a partire dal Mac con meno memoria in target. **L'ampiezza della banda di ritenzione è un parametro del budget** e va calibrata insieme ad esso. Il test di lunga durata è parte del contratto, con le soglie di NFR-P9: 560 MB di picco e 16 MB/h di pendenza.

## Soglie non supportabili

Una soglia dichiarata nel PRD non è stata raggiunta sull'hardware dichiarato.

### NFR-P9 — assenza di crescita in sessione di lunga durata

- **Requisito:** «una sessione di lunga durata non mostra crescita monotona» (NFR-P9, `docs/PRD.md`, riga 740).
- **Misura che lo dimostra:** pendenza 6,75 MB/h, IC95 da 3,19 a 10,32 MB/h, distinguibile da zero; footprint da 189,5 a 216,5 MB in 59 minuti di sessione (`804a05bc-2849-44e8-bee8-f7aa4ad165f8`).
- **Constatazione:** **non supportabile su questa configurazione.** La crescita misurata è piccola ma statisticamente separata dallo zero. La sua origine non viene dalle anteprime trattenute, che la banda limita, e non è stata isolata.
- **Modifica proposta al requisito:** sostituire «non mostra crescita monotona» con una pendenza massima dichiarata, 16 MB/h su 60 minuti, con l'occupazione che resta sotto il tetto di picco di 560 MB (testo di sostituzione di NFR-P9 in § *Esito*). Nella costruzione si aggiunge un'indagine sull'origine della crescita, con il test di lunga durata come oracolo. Se l'origine risultasse eliminabile, la pendenza ammessa si riduce di conseguenza.

Due cifre hanno mancato un obiettivo senza essere soglie mancate. Non compaiono quindi come voci di questa sezione:

- **Quick Look e NFR-P1.** Il percorso Quick Look ha p95 1771,9 ms su 3.000 immagini (`24b45870-5d53-4120-9a20-2dff884bad0c`), oltre il secondo. NFR-P1 è però raggiunto dal percorso ImageIO, e la scelta del percorso diventa un vincolo di costruzione.
- **Margine di NFR-P10.** Il margine di 1,5 non copre il massimo di due celle di visione di classe L. NFR-P10 non fissa un margine numerico: il margine necessario è dichiarato nel testo di sostituzione.

**L'esito è valido e chiude il cancello; nessuna misura è stata ripetuta su una configurazione diversa da quella dichiarata.** La prima esecuzione scartata (punto 8 di § *Limiti della misura*) è stata ripetuta sulla stessa macchina perché la finestra di strumentazione era occlusa, non per cercare un esito diverso.

## Conseguenze per la costruzione

Le decisioni che le Tappe successive ereditano. Ogni valore è attribuito ad Apple M1 Pro con 32 GB, macOS 27.2.0 (build 26B123).

1. **Percorso di anteprima: ImageIO.** La griglia usa `CGImageSourceCreateThumbnailAtIndex` a dimensione dichiarata: lato della cella × fattore di scala, cioè 480 pixel per celle da 240 punti su schermo a scala 2. Con questo percorso la prima schermata ha p95 441,8 ms su 3.000 immagini.
   - Quick Look resta fuori dalla prima schermata e dal budget.
   - Se servisse per formati che ImageIO non legge, il suo costo va misurato sul servizio di sistema, perché nel processo non è osservabile.
2. **Stime per cella.** La stima di ciascuna delle 65 righe di § *Stime di costo in memoria* è la «Stima adottata», da usare con le regole seguenti.

   | Regola | Valore |
   |---|---|
   | Margine di sicurezza | 1,5 |
   | Riserva fissa per la visione | 17 MB, contata una volta per processo |
   | Fattore di scarto hardware, finché non c'è misura a posteriori | 1,5 su ogni configurazione diversa da quella di misura |
   | Righe `quicklook` | Non utilizzabili come stime |
   | Righe `io` | Stima minima di 0,1 MB |

3. **Limite per elemento.** `max(1 MiB, max(4 × p95, 1,5 × massimo osservato))` per cella; i valori per cella sono nella colonna «Limite per elemento» (da 1 a 60 MiB).
   - Un'immagine oltre 48 MP non è anomala per la decodifica, mentre per la visione ha una cella propria: stima 15,8 MB, limite 60 MiB.
4. **Banda di ritenzione.** Entrata 0,5 schermate e uscita 1,0 schermate. Trattiene 48 anteprime a regime (33,2 MB) e al massimo 66 in movimento (45,6 MB). Ogni mezza schermata in più di entrata costa 24 anteprime (16,6 MB).
5. **Tetto di memoria.** Due soglie, entrambe da verificare con un test automatico che fallisce la build:

   | Soglia | Valore |
   |---|---|
   | Picco su 50.000 file con scorrimento continuo | 560 MB |
   | Pendenza su una sessione di 60 minuti | 16 MB/h |

   Sul Mac da 8 GB i valori valgono come ipotesi, tramite il fattore di scarto, fino alla prima misura su quella configurazione. Il riferimento per il test di prodotto è `bench scroll-memory --long-session 60`. La pipeline di integrazione continua non è stata introdotta da questo cancello.
6. **Indagini aperte, misurate e non spiegate.**
   - La crescita di 6,75 MB/h nella sessione di lunga durata.
   - I 0,67-0,72 MB trattenuti per elemento dalla scrittura in cache (`store`).
   - Le allocazioni una tantum della visione.
7. **Navigazione sotto carico.** Con code sature, lo spostamento della selezione costa al massimo 2,80 ms fino al fotogramma: le code non bloccano il thread principale.

**Osservazione sullo scope (PRD, riga 192).** Il PRD indica *Area 12 — Editing di base* e il punteggio estetico come candidati al rinvio, «da rivedere alla fine del cancello n°1». Il cancello non ha misurato né l'editing né il modello estetico. Le stime misurate, al più 6,5 MB per elemento di visione al p95 e un picco di 372,8 MB su 50.000 file, non forniscono quindi argomenti né per il rinvio né contro. Prima della Tappa che lo introduce, il costo del modello estetico va misurato con lo stesso banco (`bench item-cost`), come tipo di lavoro aggiuntivo. Il rinvio resta una decisione di piano, qui non presa.
