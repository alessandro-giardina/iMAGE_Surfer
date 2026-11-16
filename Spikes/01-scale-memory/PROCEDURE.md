# Cancello n°1 — Procedura di misura di scala e memoria

Questa procedura permette a un altro sviluppatore di rigenerare il dataset ed eseguire il banco del cancello n°1 (US-001) senza conoscenze non scritte. Tutti i comandi si lanciano dalla **radice del repository**.

Il materiale sotto `Spikes/01-scale-memory/` è **usa-e-getta**: code, politica di ammissione, cache di anteprime e banda di ritenzione esistono qui nella forma minima che serve a misurarle e non vanno riusati nel prodotto.

## Prerequisiti

- macOS 15 o successivo su Apple Silicon.
- Toolchain Swift 6 dai Command Line Tools (`xcode-select --install`). **Xcode non è richiesto**: il banco è un pacchetto SwiftPM costruito con `swift build`, senza dipendenze esterne e senza rete.
- Il volume che ospita il dataset deve essere **APFS con supporto ai cloni** (`clonefile(2)`, l'equivalente di `cp -c`): la cartella da 50.000 file usa cloni per non occupare oltre 350 GB.
- Circa **310 GB liberi** sul volume del dataset (il dataset ne occupa circa 235; il resto è il margine richiesto dal controllo preventivo). Il generatore esegue un controllo preventivo e si rifiuta di partire se lo spazio non basta.
- Una sessione grafica attiva: il banco apre una finestra AppKit di strumentazione per misurare la prima schermata e la latenza della selezione.

Verifica rapida:

```sh
swift --version                                  # Swift 6.x
swift build --package-path Spikes/01-scale-memory
swift test  --package-path Spikes/01-scale-memory
```

Note sulla toolchain dei soli Command Line Tools (verificate con Swift 6.4.2):

- Il sistema di build predefinito di SwiftPM non passa al compilatore il percorso del plugin delle macro di Swift Testing. `Package.swift` aggiunge `-plugin-path /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` alla sola suite di test, e solo se quella directory esiste. Senza questo flag `swift test` fallisce con `plugin for module 'TestingMacros' not found`.
- Al collegamento il linker stampa `ld: warning: search path '/Library/Developer/CommandLineTools/Developer/...' not found`. Sono percorsi che la toolchain aggiunge da sé e che l'installazione dei Command Line Tools non contiene: non dipendono dal codice del pacchetto e non hanno effetto sul risultato. Il compilatore non emette diagnostiche.

## Generazione del dataset

Profilo pieno, una sola volta prima di misurare:

```sh
swift run --package-path Spikes/01-scale-memory gen-dataset --profile full
```

Profilo `smoke`, per verificare il banco in pochi secondi:

```sh
swift run --package-path Spikes/01-scale-memory gen-dataset --profile smoke --out /tmp/spike01-smoke --force
```

Opzioni: `--config <path>` (predefinita `Spikes/01-scale-memory/dataset.json`), `--out <path>` (predefinita `Spikes/01-scale-memory/.data`), `--profile full|smoke` (predefinito `full`), `--force` (rigenera rimuovendo un dataset già presente; senza `--force` il generatore si rifiuta di sovrascrivere). Un argomento sconosciuto stampa l'uso ed esce con stato 2.

- Tempo atteso sul profilo pieno: **30-60 minuti**. Il profilo `smoke` impiega meno di un minuto.
- Spazio atteso sul profilo pieno: **circa 235 GB** (la stima del pre-volo è 234 GB). Il profilo `smoke` occupa meno di 1 GB.
- **Pre-volo.** Prima di scrivere qualunque file il generatore stima lo spazio come somma, per ogni cella, di file unici × megapixel × byte per megapixel dichiarati, e lo confronta con lo spazio libero del volume. Se il libero è inferiore a 1,3 volte la stima (circa 304 GB sul profilo pieno) termina con stato 1, riportando stima e disponibile. Per ripartire libera spazio, oppure riduci `firstScreenFolders.count` e documenta la riduzione in `RESULT.md`. Il generatore verifica anche che il volume accetti `clonefile(2)`; se non lo accetta, avvisa e usa copie piene.
- La configurazione versionata è `Spikes/01-scale-memory/dataset.json`; i file generati finiscono in `Spikes/01-scale-memory/.data/` e **non** sono versionati.

Contenuto della directory generata:

| Voce | Contenuto |
|---|---|
| `p1-run-01/` … `p1-run-10/` | Dieci cartelle disgiunte da 3.000 file, **tutti unici e mai clonati**: ogni ripetizione della prima schermata parte a cache fredda su file mai letti, senza `sudo purge`. Sono dieci perché la prima schermata si misura con due percorsi di anteprima, cinque ripetizioni ciascuno, e una cartella già letta ha le sue anteprime nella cache dei file. |
| `scroll-50k/` | 50.000 file nelle 12 celle formato × classe di risoluzione: 250 unici per cella, il resto cloni APFS a nome distinto. I cloni condividono i blocchi fisici e **sottostimano la lettura a freddo** su questa cartella; memoria e costo di decodifica restano reali. |
| `itemCostPool/` | 25 file unici per cella (`<formato>-<classe>-NNN.<est>`) per la misura del costo per elemento. |
| `anomalous/` | Tre TIFF 16000×12000 non compressi (circa 576 MB ciascuno), per calibrare il limite per singolo elemento. |
| `indexes/<cartella>.tsv` | Indice di ogni cartella: nome, formato, classe, dimensioni, `unique` o `clone` e file sorgente del clone. |
| `dataset-manifest.json` | Seme, digest SHA-256 di `dataset.json`, totali della cartella di scorrimento (`totals.total` = 50.000), e per ogni cella conteggi unici, cloni e totali, byte, byte per megapixel ottenuti, qualità di codifica e `toleranceMiss`. |

Nella cartella da 50.000 file i nomi (`IMG_00001.jpg` …) sono mescolati con un seme fisso, così l'ordine alfabetico alterna formati e classi come in una cartella reale. La qualità di JPEG e HEIC è calibrata per cella, con una ricerca binaria di al più 6 iterazioni su un campione, per centrare il valore di byte per megapixel dichiarato entro ±20%. PNG e TIFF sono senza perdita e non hanno calibrazione: il manifest riporta il valore ottenuto. Il profilo `smoke` dimezza le dimensioni in pixel delle classi (`S` 800×600, `M` 2016×1512, `L` 4000×3000) per restare rapido.

## Esecuzione del banco

Prima di misurare: alimentazione di rete collegata, modalità a basso consumo disattivata, nessun'altra applicazione utente attiva. Lo stato termico e l'alimentazione vengono comunque registrati a ogni ripetizione.

I sottocomandi si eseguono in quest'ordine:

Il banco apre una finestra AppKit di strumentazione (1512×982 punti, preferibilmente sul display Retina integrato) e la porta in primo piano: durante le misure non usare il Mac, perché la finestra deve restare la finestra chiave. Per tutta la durata di ogni esecuzione il banco tiene attiva un'asserzione `ProcessInfo.beginActivity` (`idleDisplaySleepDisabled`, `idleSystemSleepDisabled`, `userInitiated`, `latencyCritical`). Senza di essa, dopo il tempo di spegnimento del display (60 minuti con alimentazione di rete su questa macchina) la finestra resterebbe occlusa e i timer verrebbero rallentati a metà misura. Ogni risultato la dichiara in `parameters.sleepPrevention` e registra se la finestra era visibile. Le anteprime sono prodotte con fattore di scala 2 (480 pixel di lato), quello del display di riferimento, qualunque sia lo schermo su cui si apre la finestra. Ogni esecuzione stampa a terminale il `measurementId` e le cifre grezze e scrive il JSON in `runs/`.

1. `first-screen`: tempo alla prima schermata su 3.000 immagini (NFR-P1). Si esegue **due volte, una per percorso di anteprima**. Ogni ripetizione apre una cartella `p1-run-NN` **mai letta prima**: il banco tiene traccia delle cartelle lette in `.data/.bench-touched/`, così le cinque ripetizioni di Quick Look e le cinque di ImageIO usano dieci cartelle diverse, tutte a cache fredda. Sul profilo pieno il banco si rifiuta di riusare una cartella già letta, a meno di `--allow-warm`. Circa 2 minuti per esecuzione.

   ```sh
   swift run --package-path Spikes/01-scale-memory bench first-screen --profile full --repetitions 5 --thumbnail-path quicklook --folders p1-run-01,p1-run-03,p1-run-05,p1-run-07,p1-run-09
   swift run --package-path Spikes/01-scale-memory bench first-screen --profile full --repetitions 5 --thumbnail-path imageio --folders p1-run-02,p1-run-04,p1-run-06,p1-run-08,p1-run-10
   ```

   I due percorsi si alternano sulle cartelle (dispari e pari), così l'eventuale calore residuo delle cartelle scritte per ultime non favorisce sistematicamente uno dei due. Prima di misurare conviene verificare che la cache sia fredda: la frazione residente (`mmap` + `mincore`) dei primi file unici di `scroll-50k`, scritti subito dopo `p1-run-10`, deve essere prossima a zero.

   Ogni ripetizione registra `firstUrlsReadyMs` (i primi URL della porta di vista disponibili), `thumbnailsReadyMs` (assegnata l'ultima anteprima della porta di vista iniziale) e `firstScreenMs` (completamento della transazione Core Animation in cui quell'anteprima è stata assegnata). Tutti e tre partono dall'inizio dell'enumerazione della cartella. Prima della prima ripetizione una prova a secco su file sintetici porta l'host e le code a regime; fra due ripetizioni l'host viene ricostruito da zero, e il banco attende che il footprint rientri entro il 10% della baseline (scadenza 30 s; altrimenti `footprintDidNotSettle`).

2. `selection-latency`: latenza dello spostamento della selezione sotto lavoro in sottofondo (NFR-P3), su `scroll-50k`. Il banco satura le code (anteprime di tutti i 50.000 file e impronte Vision sugli elementi di classe M) e verifica la saturazione prima di misurare. Poi invia 200 frecce con `NSApp.postEvent`, una ogni 150 ms, a serpentina: destra, giù a fine riga, sinistra, giù. Ogni spostamento è misurato fino al completamento della transazione Core Animation in cui la selezione riflette il nuovo elemento. Circa 1 minuto.

   ```sh
   swift run --package-path Spikes/01-scale-memory bench selection-latency --profile full
   ```

   Opzioni: `--moves <n>` (predefinito 200; 40 sul profilo `smoke`), `--cadence-ms <ms>` (predefinito 150), `--thumbnail-path quicklook|imageio` (predefinito `imageio`). Il risultato riporta la dispersione sui 200 spostamenti e, separatamente, `movesOver100ms` e le profondità delle code all'inizio e alla fine.

3. `retention-band`: spazzolamento delle soglie della banda di ritenzione (NFR-P6, AC-5). Si esegue **prima** di `scroll-memory`, così il picco su 50.000 file è misurato con la coppia di soglie raccomandata e non con una scelta arbitraria. Per ogni coppia, `enterBand` ∈ {0,5; 1; 2; 3; 4} schermate × `exitBand` = `enterBand` + {0,5; 1; 2}, cioè 15 righe, la vista va al centro di `scroll-50k` e attende il regime. Registra il footprint di regime e le anteprime trattenute, poi quante anteprime vengono ricalcolate da un'oscillazione di ±0,25 schermate e da una di ±1 schermata (10 cicli ciascuna, a 3 schermate al secondo), con il costo in memoria della rigenerazione e il suo costo di parete, cioè il tempo che la pipeline impiega a tornare a regime finito lo scorrimento. La coppia raccomandata è la più piccola, per soglia di uscita e poi di entrata, con zero anteprime ricalcolate sull'oscillazione di ±0,25. Se nessuna coppia lo ottiene, il risultato riporta `recommendation: null` con il motivo. Con delta ≥ 0,5 un'oscillazione di ±0,25 non può portare un elemento oltre la soglia di uscita, quindi lo zero è atteso per costruzione. La motivazione misurata viene da due gruppi di righe aggiuntive: i riferimenti **senza isteresi** (`exitBand` = `enterBand`, con 0 e con ogni soglia di entrata), cioè il rilascio immediato che la banda evita, e le righe con delta 0,25. Circa 30-40 minuti.

   ```sh
   swift run --package-path Spikes/01-scale-memory bench retention-band --profile full
   ```

   Opzioni: `--scroll-speed <s>` (predefinito 3), `--cycles <n>` (predefinito 10; 3 sul profilo `smoke`).

4. `scroll-memory`: occupazione di picco su 50.000 file con scorrimento continuo, e sessione di lunga durata (NFR-P9). Ogni ripetizione scorre a 3 schermate al secondo dall'inizio alla fine di `scroll-50k` e ritorno, con la banda di ritenzione indicata, campionando `phys_footprint` ogni 50 ms. Registra il picco, il regime (mediana dell'ultimo terzo della corsa) e la crescita per 1.000 elementi percorsi nel terzo centrale della discesa. Poi la **sessione di lunga durata: 60 minuti** sul profilo pieno, con raffiche di scorrimento di 20 s e quiete di 10 s. Ne registra la pendenza con intervallo di confidenza al 95%, `slopeDistinguishableFromZero`, le pendenze di sei finestre consecutive e, come controllo di robustezza, la pendenza sulle mediane al minuto. A 3 schermate al secondo una corsa sui 50.000 file dura circa 12 minuti per verso, cioè circa 23 minuti per ripetizione: con la sessione lunga sono **circa 3 ore**. La pendenza della sessione lunga esclude la salita dell'apertura ed è calcolata dal kernel sulle mediane al minuto; la pendenza sui campioni a 50 ms, autocorrelati, è riportata solo come dato secondario. Ogni ripetizione registra anche quanto la banda è davvero piena: anteprime trattenute e frazione degli elementi in vista che hanno già l'anteprima. Si passano le soglie raccomandate da `retention-band`:

   ```sh
   swift run --package-path Spikes/01-scale-memory bench scroll-memory --profile full --repetitions 5 --long-session 60 --enter-band <entrata> --exit-band <uscita>
   ```

   Opzioni: `--scroll-speed <s>` (predefinito 3), `--long-session <minuti>` (predefinito 60 sul profilo pieno e 1 sul profilo `smoke`; 5 minuti bastano durante lo sviluppo), `--enter-band <s>` e `--exit-band <s>` (predefiniti 1 e 2).

5. `item-cost`: costo in memoria di un singolo elemento per tipo di lavoro (`io`, `decode`, `quicklook`, `vision`, `store`) × formato × classe di risoluzione, più la cella degli elementi anomali (NFR-P10, AC-4). `--all` rilancia il banco come **sottoprocesso, una cella per volta**: il footprint è una grandezza dell'intero processo, e celle diverse nello stesso processo contaminerebbero la baseline. Per ogni elemento il banco registra il **picco transitorio** (picco durante l'operazione meno la baseline, campionato ogni 5 ms) e il **delta trattenuto** (footprint dopo il drenaggio del pool meno la baseline). Il primo elemento di ogni cella è un riscaldamento non misurato (un elemento del pool fuori dai 20 misurati), il cui costo una tantum è riportato a parte. L'uscita dell'operazione resta viva fino all'ultima lettura del picco, e una cella di controllo `noop` misura il fondo della strumentazione. Un'operazione che fallisce su un elemento viene marcata (`operationFailed`) e non interrompe la cella. Il limite per singolo elemento segue la formula `max(1 MB, arrotondamento per eccesso al MB di max(p95 × 4, massimo × 1,5))`, registrata nel risultato insieme ai valori che la producono. 65 celle con 20 elementi ciascuna: **da 30 a 90 minuti**.

   ```sh
   swift run --package-path Spikes/01-scale-memory bench item-cost --all --profile full
   ```

   Una sola cella: `bench item-cost --cell decode:jpeg:M --n 20`. Opzioni: `--n <n>` (predefinito 20, ed è anche il minimo sul profilo pieno; 3 sul profilo `smoke`).

Opzioni comuni a tutti i sottocomandi: `--data <path>` (predefinito `Spikes/01-scale-memory/.data`), `--profile full|smoke`, `--repetitions <n>`, `--out <path>` (predefinito `Spikes/01-scale-memory/runs`), `--thumbnail-path quicklook|imageio`, `--window <w>x<h>` (predefinito `1512x982`), `--scale <s>` (predefinito 2). Un sottocomando o un'opzione sconosciuti stampano l'uso ed escono con stato 2. Se il manifest del dataset manca, il banco esce con stato 1 e rimanda a `gen-dataset`.

## Dove finiscono i risultati

- `Spikes/01-scale-memory/runs/`: ogni esecuzione scrive qui un JSON con `measurementId`, impronta hardware e campioni. **Non versionato.**
- `Spikes/01-scale-memory/measurements/`: le esecuzioni citate da `RESULT.md`, copiate da `runs/`. **Versionato**, così ogni cifra del documento è verificabile.
- `Spikes/01-scale-memory/RESULT.md`: l'esito scritto del cancello, con hardware di misura, misure grezze, stime di costo, banda di ritenzione ed esito su ADR-009, NFR-P1, NFR-P9 e NFR-P10.

## Profili

- `--profile full`: il profilo di misura. Usa la cartella da 50.000 file, dieci cartelle disgiunte da 3.000 file per la prima schermata (cinque per percorso di anteprima), e il pool completo per il costo per elemento. È l'unico profilo le cui cifre possono entrare in `RESULT.md`.
- `--profile smoke`: un dataset minuscolo (poche centinaia di file) con cui tutti i sottocomandi girano in pochi secondi. Serve a verificare che il banco funzioni e alla suite di test; le sue cifre non hanno valore di misura.
