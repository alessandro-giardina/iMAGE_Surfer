# Cancello 4 — Procedura dell'iniezione di arresti

Questa procedura permette a un altro sviluppatore di ripetere il banco del cancello n°4 (US-004): interrompere un lotto di operazioni su file in un punto scelto, recuperarlo in un nuovo processo, ed eseguire l'intera matrice che produce la misura citata da [`RESULT.md`](RESULT.md).

La build si lancia dalla **radice del repository**; tutti gli altri comandi da **`Spikes/04-crash-recovery/`**. Il binario risolve fixture, dati ed esecuzioni dalla posizione dei propri sorgenti, quindi funziona da qualunque directory, ma i percorsi relativi di questa pagina presuppongono quella.

Il materiale sotto `Spikes/04-crash-recovery/` è **usa-e-getta**: macchina a stati, registro e classificatori esistono qui nella forma minima che serve a misurare, e non vanno riusati nel prodotto.

## Prerequisiti

- macOS 15 o successivo su Apple Silicon. Il banco usa `diskutil image` e il formato di immagine ASIF, entrambi inclusi nel sistema; la misura versionata è stata presa su macOS 27.2 (build 26B123). Su una versione di macOS che non li offre, `crashbench setup` fallisce riportando l'errore di `diskutil`.
- Toolchain Swift 6 dei Command Line Tools (`xcode-select --install`), verificata con Swift 6.4.2. **Xcode non è richiesto**: il banco è un pacchetto SwiftPM senza dipendenze esterne.
- Circa **100 MB liberi** sul volume del repository: l'immagine disco è dichiarata da 64 MB, e su disco ne occupa circa 12.
- **Nessun `sudo`**, nessuna rete, nessuna variabile d'ambiente, nessun servizio. Il volume di lavoro si crea, si monta e si espelle con i permessi dell'utente.

Verifica rapida, dalla radice del repository:

```sh
swift --version                                      # Swift 6.x
swift build --package-path Spikes/04-crash-recovery
swift test  --package-path Spikes/04-crash-recovery  # circa 150 s
```

Note sulla toolchain dei soli Command Line Tools:

- `Package.swift` aggiunge `-plugin-path /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` alla sola suite di test, e solo se quella directory esiste: senza, il sistema di build di SwiftPM non trova il plugin delle macro di Swift Testing e la suite non compila.
- Al collegamento il linker stampa `ld: warning: search path '/Library/Developer/CommandLineTools/Developer/...' not found`. Sono percorsi che la toolchain aggiunge da sé e che l'installazione dei Command Line Tools non contiene: non hanno effetto sul risultato. Il compilatore non emette diagnostiche.
- `swift test` monta più volumi di prova in parallelo e dura circa 150 s: lanciarlo con un timeout di almeno 600 s. I volumi di prova stanno in `.data/tests/` e vengono espulsi alla fine di ogni suite.

## Build

Dalla radice del repository:

```sh
swift build --package-path Spikes/04-crash-recovery
cd Spikes/04-crash-recovery
```

Il binario è `.build/debug/crashbench`. Si usa **il binario e non `swift run`**: `swift run` riformula lo stato di uscita, mentre l'arresto deve restare visibile come stato 137 (`SIGKILL`). `.build/debug/crashbench` senza argomenti stampa l'uso completo di ogni sottocomando.

Le fixture del lotto sono versionate in `fixtures/`: cinque coppie immagine-sidecar in `fixtures/folder/`, il lotto in `fixtures/batch.json` e il manifest con SHA-256 e dimensione di ogni file in `fixtures/MANIFEST.json`. Prima di misurare si verifica che non siano cambiate:

```sh
.build/debug/crashbench verify-fixtures    # stato 0; con una fixture diversa, stato 1 e il nome del file
```

## Dimostrazione manuale di un punto

La sequenza mostra, su un punto scelto, ciò che la matrice ripete su tutti: l'arresto, il riconoscimento dal disco, il recupero, e il ciclo di una perturbazione con la decisione dell'utente.

1. **Volume di lavoro.**

   ```sh
   .build/debug/crashbench setup
   ```

   Crea, se manca, l'immagine `.data/work.asif` (ASIF, 64 MB, APFS, nome `CrashBench`), la monta con `--nobrowse` sotto `.data/mnt` e ripristina la cartella di prova dalle fixture. Stampa `punto di montaggio: …` e `uuid del volume: …`.

2. **Elenco dei punti.**

   ```sh
   .build/debug/crashbench list-points
   ```

   Stampa i 61 punti derivati dal piano, uno per riga: `id`, fase e descrizione, separati da tabulazione. Non richiede il volume. Con `--json` stampa lo stesso elenco in JSON.

3. **Arresto.**

   ```sh
   .build/debug/crashbench run --crash-at S03-b
   echo $?
   ```

   Il lotto riparte dalle fixture, scrive il log di intenti `.data/state/intent-log.jsonl` ed esegue i passi. Al punto scelto stampa `ARRESTO S03-b: azione eseguita, fatto non registrato (S03, OP2: …)` e si uccide con `SIGKILL`. In un terminale interattivo zsh stampa `zsh: killed`, e `echo $?` stampa **137**. Nessuna pulizia è eseguita.

4. **Stato riconosciuto dal disco, senza agire.**

   ```sh
   .build/debug/crashbench status
   ```

   A `S03-b` stampa fra l'altro `DIVERGENZA S03 log=non-fatto disco=fatto`, `PASSO S03 fatto`, `COPPIA OP2 immagine=dest sidecar=orig SEPARATA` e `SEPARAZIONI-ALL-AVVIO OP2`. Non scrive nel log, salvo la riparazione dichiarata di un record troncato.

5. **Recupero in un nuovo processo.**

   ```sh
   .build/debug/crashbench recover --strategy resume       # oppure --strategy compensate
   ```

   Le righe hanno un ordine fisso: `RECUPERO strategia=… direzione=…`, `RECORD-TRONCATO si|no`, `DIVERGENZA …`, una riga `PASSO <id> <avvio> -> <finale>` per passo, una riga `COPPIA` per operazione con le posizioni dopo il recupero, `SEPARAZIONI-ALL-AVVIO`, `SEPARAZIONI-RESIDUE`, `ESITO <esito>` e le righe `TRACCIA`. A `S03-b` la ripresa termina con `ESITO completato`. Per vedere la compensazione si ripete il passo 3, poi `recover --strategy compensate`, che termina con `ESITO compensato`. Il recupero esce con 0 per qualunque esito, `NON_SUPPORTABILE` compreso.

   Le posizioni sono `orig` (origine), `dest` (destinazione), `cest` (Cestino del volume), `ass` (in nessuna posizione attesa) e `amb` (in più di una, oppure non osservabile perché il volume manca).

6. **Perturbazione, recupero, decisione dell'utente.** Una delle otto classi di errore si applica fra l'arresto e il recupero, e si rimuove dopo.

   Ramo `retry`, con le cartelle del lotto rese non scrivibili:

   ```sh
   .build/debug/crashbench run --crash-at S06-b
   .build/debug/crashbench perturb G-folder-readonly --strategy resume   # PERTURBAZIONE G-folder-readonly bersaglio=nessuno ambito=sistemico
   .build/debug/crashbench recover --strategy resume                     # PASSO S07 non-fatto -> sospeso …, ESITO bloccato
   .build/debug/crashbench unperturb                                     # RIMOZIONE G-folder-readonly bersaglio=nessuno
   .build/debug/crashbench decide retry                                  # DECISIONE retry, …, ESITO completato
   ```

   Ramo `abandon`, con il volume espulso:

   ```sh
   .build/debug/crashbench run --crash-at S06-b
   .build/debug/crashbench perturb G-volume-missing --strategy resume    # espelle il volume di lavoro
   .build/debug/crashbench recover --strategy resume                     # ogni PASSO sospeso, COPPIA … amb, ESITO bloccato
   .build/debug/crashbench unperturb                                     # rimonta il volume
   .build/debug/crashbench decide abandon                                # DECISIONE abandon, COPPIA …, ESITO abbandonato
   ```

   - Le classi sono `G-volume-missing`, `G-folder-readonly`, `G-space-exhausted`, `L-locked`, `L-collision`, `L-modified`, `L-trash-emptied` e `L-missing`. Una combinazione senza bersaglio stampa `PERTURBAZIONE <classe> NON-APPLICABILE motivo=<…>` e non tocca nulla.
   - `decide` esce con 2, senza scrivere nel log, se l'ultimo esito non è `bloccato`.
   - **Rimuovere sempre la perturbazione con `unperturb` prima di un nuovo `run` o di `reset`**: il ripristino svuota `.data/state/`, e con esso il record della perturbazione, e non rimuove il file di riempimento `.data/mnt/.riempimento` di `G-space-exhausted`. `unperturb` senza perturbazione attiva stampa `RIMOZIONE nessuna`.
   - `.build/debug/crashbench snapshot --out <file>` scrive l'istantanea del volume, cartella di prova e Cestino, per confrontare a mano due stati.

## Matrice completa

La matrice esegue ogni cella in processi figli dello stesso binario: `run`, `perturb`, `recover`, `decide` e `unperturb`, con le istantanee del volume prima e dopo. Le celle sono 146: 37 punti di esecuzione per 2 strategie, 22 punti di compensazione, 2 doppi arresti e 48 combinazioni di perturbazione. Il profilo `full` ripete ogni cella 5 volte.

**In un solo comando**, se l'ambiente non ha un tetto di durata:

```sh
.build/debug/crashbench run-matrix --profile full --repetitions 5
```

Durata attesa: **circa 43 minuti** (la misura versionata somma 2564,6 s). Esegue `setup` se il volume non è montato, scrive una riga di avanzamento per cella su stderr, il riepilogo su stdout e il JSON in `runs/<measurementId>.json`.

**In parti, come è stata eseguita la misura versionata.** L'ambiente di esecuzione della misura versionata aveva un tetto di durata per comando, quindi la matrice è stata divisa in 21 parti con un solo `measurementId`, poi unite. Le parti si formano a rotazione sull'elenco delle celle, e 21 è primo con 8, il periodo delle classi di errore in quell'elenco: le celle più lente, quelle `bloccato` con i due rami, non finiscono tutte nella stessa parte. Ogni parte dura da 92 a 152 s.

```sh
ID=crash-matrix-20261116T154019Z-0eefc599
for k in $(seq 1 21); do
  .build/debug/crashbench run-matrix --profile full --repetitions 5 --shard $k/21 --measurement-id $ID
done
.build/debug/crashbench combine-matrix runs/$ID-parte-*-di-21.json
cp runs/$ID.json measurements/
```

- L'`ID` riportato è quello della misura versionata. Una nuova misura ne usa uno nuovo, nella stessa forma: `ID=crash-matrix-$(date -u +%Y%m%dT%H%M%SZ)-$(uuidgen | tr -d - | tr 'A-Z' 'a-z' | cut -c1-8)`.
- Ogni parte scrive `runs/<ID>-parte-<k>-di-21.json`. Tutte usano lo stesso volume (`.data`), che resta montato fra una parte e l'altra.
- `combine-matrix` scrive `runs/<ID>.json`. Rifiuta con stato 2, senza scrivere nulla, parti con `measurementId`, host, digest del manifest, profilo o ripetizioni diversi, o con una cella in due parti. Esce con 4 se l'unione non copre esattamente le 146 celle.
- **Riepilogo atteso dell'unione**: `COPERTURA completa 146/146`, `PUNTO_NON_RAGGIUNTO 0`, `ERRORI_DEL_BANCO 0`, stato 0. La misura versionata riporta inoltre `NON_SUPPORTABILE 2`, `RICONOSCIMENTO_ERRATO 0` e `NON_DETERMINISTICHE 0`.

**Stati di uscita di `run-matrix`:** 0 se ogni cella è stata misurata; 3 se in una cella il processo non è morto nel punto chiesto (`PUNTO_NON_RAGGIUNTO`, difetto del banco); 1 se un processo figlio è uscito in modo inatteso (`ERRORI_DEL_BANCO`, JSON scritto comunque) o se la preparazione è fallita; 2 per un uso errato.

**Se una parte esce con 1 per un errore del banco**, si legge `benchErrors` della cella nel JSON della parte, si sposta il file della parte fuori dal modello `runs/<ID>-parte-*-di-21.json` e si riesegue la parte una volta, con lo stesso `ID`. Se l'errore si ripresenta, va riportato come difetto e non nascosto. Nella misura versionata è accaduto alle parti 12 e 17, entrambe per `perturb G-space-exhausted` con `fsync` fallita su `.riempimento` (`ENOSPC`); i tentativi scartati sono in `runs/scartate/`, e `RESULT.md` li dichiara in § *Configurazione*.

**Profilo `smoke`.** `.build/debug/crashbench run-matrix --profile smoke` esegue 12 celle con 1 ripetizione, in circa un minuto: serve a verificare il banco, e le sue cifre non entrano in `RESULT.md`.

### Dove finiscono i risultati

- `runs/`: ogni esecuzione e ogni parte. **Non versionato** (`.gitignore`: `Spikes/*/runs/`).
- `measurements/`: la sola misura citata da `RESULT.md`, copiata da `runs/`. **Versionato**: è il riferimento di ogni cifra del documento, e `ResultTraceabilityTests` fallisce se in `measurements/` c'è più di un JSON.
- `.data/`: immagine disco, punto di montaggio e stato del banco. **Non versionato** (`Spikes/*/.data/`).

## Chiusura

```sh
.build/debug/crashbench unperturb       # RIMOZIONE nessuna, se non c'è una perturbazione attiva
.build/debug/crashbench teardown        # espelle il volume di lavoro
mount | grep 04-crash-recovery/.data    # nessuna riga attesa
```

Per eliminare anche i dati generati, dalla radice del repository:

```sh
rm -rf Spikes/04-crash-recovery/.data
```

Il comando rimuove l'immagine disco, il punto di montaggio e lo stato. Va lanciato solo dopo `teardown`: con il volume ancora montato, `rm -rf` agirebbe sul contenuto del volume. Il successivo `setup` ricrea tutto da zero.

## Il Cestino

Il banco **non tocca mai il Cestino dell'utente**. Il passo Cestino del lotto (`OP5`) e la compensazione delle copie usano il Cestino del volume di lavoro, `.data/mnt/.Trashes/<uid>`, che il sistema crea sul volume stesso. Prima di agire, il passo Cestino verifica che la sorgente sia sul volume registrato nel piano, e altrimenti si rifiuta. `setup` e `reset` svuotano il Cestino del volume insieme alla cartella di prova; `teardown` e `rm -rf .data` lo eliminano con il volume.
