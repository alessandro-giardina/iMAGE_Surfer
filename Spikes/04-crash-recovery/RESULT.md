# Cancello 4 — Iniezione di arresti su un lotto di operazioni su file

Esito scritto del cancello tecnico n°4 (spec US-004): il banco in `Spikes/04-crash-recovery/` interrompe con `SIGKILL` un lotto di cinque operazioni su file in ciascuno dei 61 punti enumerati, lo recupera in un nuovo processo e confronta ogni affermazione del recupero con un'istantanea del disco.
Ogni esito, conteggio e scostamento di questo documento viene dalla misura versionata in [`measurements/`](measurements/), e `ResultTraceabilityTests` verifica la corrispondenza fra documento e JSON in entrambe le direzioni.
Il documento chiude ADR-007 del PRD e ne propone il testo di sostituzione, senza applicarlo al PRD; la procedura per ripetere la misura è in [`PROCEDURE.md`](PROCEDURE.md).

## Configurazione

| Campo | Valore |
|---|---|
| `measurementId` | `crash-matrix-20261116T154019Z-0eefc599` |
| JSON versionato | [`measurements/crash-matrix-20261116T154019Z-0eefc599.json`](measurements/crash-matrix-20261116T154019Z-0eefc599.json) |
| Host: modello | MacBookPro18,3 |
| Host: macOS | `Version 27.2 (Build 26B123)` |
| Host: build di macOS | 26B123 |
| Host: uid | 502; il Cestino del volume di lavoro è `.Trashes/502` |
| Volume di lavoro | `CrashBench`, APFS su immagine ASIF da 64 MB (`diskutil image create blank --format ASIF --size 64m --fs APFS`), montato con `--nobrowse` sotto `.data/mnt` |
| Digest del manifest delle fixture | `97a65a784b975f41d4d2c11347d56888d90eba35edc9343d24a68b45b6998084` (SHA-256 di `fixtures/MANIFEST.json`) |
| Profilo | `full`: 146 celle, cioè 98 di base (37 punti di esecuzione per 2 strategie, 22 punti di compensazione, 2 doppi arresti) e 48 di perturbazione (8 classi × 3 punti × 2 strategie) |
| Ripetizioni | 5 per cella |
| Inizio | 2026-11-16T15:40:28Z |
| Durata | 2564,6 s (42 min 45 s), somma delle 21 parti |
| Assestamento delle istantanee | 3 catture uguali a 0,25 s l'una dall'altra, al più 10 s |

**Esecuzione a parti.** La misura è una sola, con un solo `measurementId`, ma è stata eseguita in 21 parti: nell'ambiente di esecuzione ogni comando aveva un tetto di durata, e l'intera matrice richiede circa 43 minuti.

- Ogni parte è `crashbench run-matrix --profile full --repetitions 5 --shard k/21 --measurement-id crash-matrix-20261116T154019Z-0eefc599`, con k da 1 a 21: esegue a rotazione una cella ogni 21 dell'elenco del profilo.
- `crashbench combine-matrix` ha unito le 21 parti in un unico JSON. Ha verificato che dichiarassero lo stesso host, lo stesso digest del manifest, lo stesso profilo e le stesse ripetizioni, che nessuna cella comparisse due volte e che l'unione coprisse esattamente le 146 celle del profilo (`COPERTURA completa 146/146`).
- Il JSON versionato elenca le parti in `parts`, ciascuna con la propria durata, da 91,6 a 152,3 s. La durata dichiarata è la loro somma. Dall'inizio della prima parte alla fine dell'ultima sono trascorsi circa 49 minuti, comprese le due parti ripetute e le pause fra un comando e l'altro.

I comandi esatti sono in [`PROCEDURE.md`](PROCEDURE.md).

**Due parti ripetute.** Al primo tentativo due parti sono uscite con stato 1 per un errore del banco, sempre nella stessa operazione: `crashbench perturb G-space-exhausted` è terminato con `fsync fallita su .data/mnt/.riempimento: No space left on device (errno 28)`. Il file di riempimento, scritto fino a esaurire lo spazio del volume, non è stato sincronizzato.

- Parte 12: cella `S06-b/resume/G-space-exhausted`, ripetizioni 2-5 e ramo `retry`.
- Parte 17: cella `X03-prepare/resume/G-space-exhausted`, tutte e cinque le ripetizioni.

Ciascuna parte è stata rieseguita una volta, con lo stesso `measurementId`, e la seconda esecuzione non ha avuto errori: le due celle, le sole applicabili della classe `G-space-exhausted`, hanno 5 ripetizioni valide su 5. I due tentativi scartati restano in `runs/scartate/`, non versionati, e non entrano né nella misura né nella durata. L'errore riguarda la preparazione della perturbazione, prima di qualunque recupero: è del banco, non della macchina sotto misura (§ *Limiti dichiarati*, punto 13).

**Riepilogo della misura.**

- 146 celle: 129 applicabili e 17 di perturbazione non applicabili per mancanza di bersaglio, con il motivo: `nessun-passo-eseguito-applicabile` (6), `nessun-passo-non-eseguito-applicabile` (5), `solo-compensazione-di-trash-eseguito` (3), `solo-copie-in-ripresa` (3).
- 645 ripetizioni con esito: `completato` 190, `compensato` 295, `parzialmente-recuperato` 85, `bloccato` 65, `NON_SUPPORTABILE` 10. Dopo ogni `bloccato`, 5 rami `retry` e 5 rami `abandon`: 65 e 65.
- 0 celle `PUNTO_NON_RAGGIUNTO`: in ogni ripetizione, rami compresi, il processo figlio è morto per segnale 9 nel punto chiesto.
- 0 celle `RICONOSCIMENTO_ERRATO`, 0 celle non deterministiche, 0 istantanee non assestate e 0 errori del banco nella misura unita.
- 2465 istantanee assestate, di cui 22 cambiate durante l'attesa; l'ultimo cambiamento osservato è arrivato al più 0,61 s dopo l'inizio della cattura.

## Limiti dichiarati

Ogni limite è dichiarato per intero. I primi sette sono quelli fissati dal piano prima della misura.

1. **`SIGKILL` non equivale a una perdita di alimentazione.** `SIGKILL` simula la caduta del processo: ciò che è nella cache delle pagine sopravvive. Una perdita di alimentazione o un kernel panic non sono riproducibili senza una macchina virtuale, e la misura non li copre.
2. **Un solo volume APFS locale.** Il lotto gira su un volume APFS locale su immagine disco. Volume esterno, cartella sincronizzata e volume di rete spettano al cancello n°2: nessun esito di questo documento vale per loro.
3. **Il log JSONL non è `DurableState`.** Il registro di intenti è un file JSONL sul volume ospite, una riga per record scritta con una sola `write(2)` e seguita da `F_FULLFSYNC`. Non è il motore di stato durevole di ADR-003, che quindi **non** è provato da questo cancello.
4. **`ctime` e `atime` sono esclusi** dal confronto delle istantanee: `ctime` cambia a ogni rinomina per costruzione. Gli altri campi sono confrontati tutti: dimensione, digest, modo, flag, `mtime`, `birthtime`, inode e attributi estesi.
5. **Il doppio arresto è coperto solo da `D01` e `D02`**: un secondo arresto durante la ripresa e uno durante la compensazione, entrambi dopo un primo arresto a `S03-b`.
6. **Il lotto è unico**, con 5 operazioni e 10 passi: una operazione per tipo (rinomina, spostamento, spostamento con rinomina, copia, Cestino), ciascuna su una coppia immagine-sidecar. Lotti più grandi, più operazioni sullo stesso file e convenzioni del sidecar diverse da `<radice>.xmp` non sono misurati.
7. **Il Cestino è per uid.** Il Cestino usato è `.Trashes/502` sul volume di lavoro, quello che il sistema assegna all'uid che esegue il banco. Il Cestino dell'utente non viene mai toccato, e il comportamento del Cestino su altri volumi o per altri utenti non è misurato.

Limiti del banco, dichiarati con la stessa forza:

8. **Perturbazioni in tre punti, con un bersaglio fisso.** Le otto classi di errore si applicano solo a `X03-prepare`, `S06-b` e `S10-c`, sul passo scelto dalla regola del piano. 17 combinazioni su 48 non hanno bersaglio e sono registrate come non applicabili. `G-space-exhausted` si applica solo ai punti con una copia ancora da fare, per una restrizione della baseline che la misura mostra troppo stretta (§ *Classi di errore*).
9. **L'istantanea dopo il recupero precede la rimozione della perturbazione.** Nelle celle di perturbazione gli scostamenti di § *Compensazione* comprendono quindi la perturbazione stessa: per esempio `lotto:mode` della cartella resa non scrivibile, o il file estraneo di `L-collision`.
10. **Nessuna cella prova il rovesciamento della direzione.** I punti `K*` si provano solo in compensazione. Che una compensazione già avviata prevalga su `--strategy resume` è una regola del riconoscitore, non una misura di questa matrice: in ogni cella applicabile la direzione del recupero coincide con la strategia chiesta, salvo `X00-plan-torn`, che non ha direzione.
11. **Due casi restano fuori dalla matrice.** Nessuna cella raggiunge `interrotto-prima-di-agire`, l'interruzione prima di agire di FR-080, perché le perturbazioni si applicano dopo l'arresto e non fra anteprima ed esecuzione. Nessuna cella ha il motivo `stato-non-riconoscibile`. Entrambi sono prodotti dai test del banco (`BatchExecutorTests`, `RecognizerTests`, `RecoveryScenarioTests`), non da questa misura.
12. **Politiche del banco.** I file temporanei di copia (`.<nome>.partial-<planId>`) si rimuovono con `unlink`, come artefatti del lotto. La compensazione di una copia sposta la copia nel Cestino, per NFR-A1. Sono scelte dichiarate, non misurate contro alternative.
13. **Il riempimento del volume non è affidabile.** Il file `.riempimento` di `G-space-exhausted` può fallire `fsync` con `ENOSPC` (§ *Configurazione*, *Due parti ripetute*). Nei due tentativi scartati la perturbazione è riuscita 1 volta su 11, e ogni fallimento è stato un `fsync` con `ENOSPC`; nelle riesecuzioni è riuscita 20 volte su 20. Le celle misurate vengono tutte da riempimenti riusciti, ma ciascuna poggia su un solo stato del volume pieno, raggiunto fra esecuzioni dall'esito diverso. Il difetto non è stato corretto: correggerlo avrebbe richiesto una nuova misura completa.

## Punti di interruzione

Una riga per ciascuno dei 61 punti, nell'ordine di `crashbench list-points`. Le colonne di esito e di stato vengono dalle celle `<punto>/resume` e `<punto>/compensate` del JSON. Le celle di perturbazione sono in § *Classi di errore* e § *Punti bloccati in attesa dell'utente*.

| Punto | Fase | Esito ripresa | Esito compensazione | Ripetizioni | Stato dopo ripresa | Stato dopo compensazione |
|---|---|---|---|---|---|---|
| X00-plan-torn | esecuzione | NON_SUPPORTABILE (5/5) | NON_SUPPORTABILE (5/5) | 5 | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| X01-plan | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| X02-recheck | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| X03-prepare | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S01-a | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S01-b | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S01-c | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S02-a | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S02-b | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S02-c | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S03-a | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S03-b | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S03-c | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S04-a | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S04-b | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S04-c | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S05-a | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S05-b | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S05-c | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S06-a | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S06-b | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S06-c | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S07-a | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S07-m | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S07-b | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S07-c | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S08-a | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S08-m | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S08-b | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S08-c | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S09-a | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S09-b | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S09-c | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S10-a | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S10-b | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S10-c | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| S05-torn | esecuzione | completato (5/5) | compensato (5/5) | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K10-a | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K10-b | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K09-a | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K09-b | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K08-a | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K08-b | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K07-a | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K07-b | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K06-a | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K06-b | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K05-a | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K05-b | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K04-a | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K04-b | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K03-a | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K03-b | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K02-a | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K02-b | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K01-a | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K01-b | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K00-a | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| K00-b | compensazione | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |
| D01 | doppio | completato (5/5) | — | 5 | OP1 i:dest s:dest OP2 i:dest s:dest OP3 i:dest s:dest OP4 i:dest s:dest OP5 i:cest s:cest | — |
| D02 | doppio | — | compensato (5/5) | 5 | — | OP1 i:orig s:orig OP2 i:orig s:orig OP3 i:orig s:orig OP4 i:orig s:orig OP5 i:orig s:orig |

Legenda:

- **Fase**: `esecuzione` per gli arresti durante il lotto; `compensazione` per gli arresti durante l'annullamento di un lotto completato, come lo chiederebbe l'utente (FR-083); `doppio` per i due doppi arresti.
- **Esito**: `<esito> (<n>/<ripetizioni>)`, dove `<n>` sono le ripetizioni che hanno raggiunto quell'esito; più esiti si separano con `; `.
- **`—`**: la strategia non si applica. I punti `K*` e `D02` sono arresti durante una compensazione e non hanno una cella di ripresa; `D01` è un arresto durante una ripresa e non ha una cella di compensazione.
- **Stato**: `OPn i:<pos> s:<pos>` per ciascuna delle cinque operazioni, immagine (`i`) e sidecar (`s`). Viene dall'istantanea presa dal banco dopo il recupero, non dalle righe stampate dal recupero.
- **Posizione**: dove si trova il file con il digest del piano. `orig` all'origine, `dest` alla destinazione, `cest` nel Cestino del volume, `ass` in nessuna delle posizioni attese, `amb` in più di una oppure non osservabile, quando il volume del lotto non c'è.
- **Operazioni**: `OP1` rinomina di `IMG_0001`; `OP2` spostamento di `IMG_0002` in `selezione/`; `OP3` spostamento con rinomina di `IMG_0003` in `selezione/`; `OP4` copia di `IMG_0004` in `consegna/`; `OP5` `IMG_0005` nel Cestino. I passi da `S01` a `S10` agiscono su ogni coppia prima con l'immagine e poi con il sidecar.

Cosa mostra la tabella:

- **Da 60 punti su 61 la strategia scelta conclude in 5 ripetizioni su 5.** Le 96 celle di base diverse da `X00-plan-torn` raggiungono l'esito della propria strategia: `completato` in ripresa (36 punti di esecuzione e `D01`), `compensato` in compensazione (36 punti di esecuzione, i 22 punti `K*` e `D02`).
- **Lo stato finale dipende solo dalla strategia.** Dopo ogni ripresa `OP1`…`OP4` sono a destinazione e `OP5` nel Cestino; il confronto del banco con il lotto completato atteso, per percorsi e digest, non trova differenze in nessuna delle 38 celle `completato`. Dopo ogni compensazione tutte le coppie sono all'origine.
- **`X00-plan-torn` è l'unico punto da cui non si raggiunge alcun esito**: `NON_SUPPORTABILE` in 5 ripetizioni su 5 con entrambe le strategie, con tutte le coppie all'origine (§ *Esiti non supportabili*).
- **Il disco prevale sul log.** In ogni punto `-b` (azione eseguita, fatto non registrato) il recupero riferisce `DIVERGENZA Sxx log=non-fatto disco=fatto`, e nei punti da `K01-b` a `K10-b` `log=fatto disco=non-fatto` (`K00-b`, la rimozione delle cartelle preparate, non ne riferisce): in tutti decide dal disco e conclude come negli altri punti. `S05-torn` riferisce anche `RECORD-TRONCATO si` per il record di fatto scritto a metà. `D01` riferisce due divergenze, `S03` e `S08`, una per arresto, perché il recupero non riconcilia il log.

## Compensazione

Una riga per ognuna delle 74 celle in cui il recupero ha preso la direzione di compensazione (`compensation.attempted`, direzione `compensate`): le 59 celle di base con esito `compensato` e 15 celle di perturbazione. Di queste 15, le 6 concluse `bloccato` non hanno riportato all'origine alcun passo: il loro confronto con lo stato di partenza misura ciò che il recupero bloccato lascia, non una compensazione eseguita.

- «Coincide» vale `sì` se e solo se il confronto campo per campo fra l'istantanea presa prima del lotto e quella presa dopo il recupero non trova scostamenti (`ctime` e `atime` esclusi).
- Gli scostamenti si scrivono `percorso:campo`: `lotto/…` è la cartella del lotto, `@cestino/…` il Cestino del volume. `aggiunto` e `rimosso` indicano un'entrata presente in una sola delle due istantanee.

| Cella | Esito | Coincide con lo stato iniziale | Scostamenti su file | Scostamenti mtime di directory |
|---|---|---|---|---|
| X01-plan/compensate | compensato (5/5) | sì | nessuno | nessuno |
| X02-recheck/compensate | compensato (5/5) | sì | nessuno | nessuno |
| X03-prepare/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S01-a/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S01-b/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S01-c/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S02-a/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S02-b/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S02-c/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S03-a/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S03-b/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S03-c/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S04-a/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S04-b/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S04-c/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S05-a/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S05-b/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S05-c/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S06-a/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S06-b/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S06-c/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S07-a/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S07-m/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| S07-b/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto | @cestino:mtime, lotto:mtime |
| S07-c/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto | @cestino:mtime, lotto:mtime |
| S08-a/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto | @cestino:mtime, lotto:mtime |
| S08-m/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto | @cestino:mtime, lotto:mtime |
| S08-b/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| S08-c/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| S09-a/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| S09-b/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| S09-c/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| S10-a/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| S10-b/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| S10-c/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| S05-torn/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| K10-a/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K10-b/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K09-a/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K09-b/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K08-a/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K08-b/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K07-a/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K07-b/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K06-a/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K06-b/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K05-a/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K05-b/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K04-a/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K04-b/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K03-a/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K03-b/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K02-a/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K02-b/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K01-a/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K01-b/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K00-a/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| K00-b/compensate | compensato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| D02/compensate | compensato (5/5) | no | nessuno | lotto:mtime |
| X03-prepare/compensate/G-volume-missing | bloccato (5/5) | no | lotto:size, lotto/consegna:aggiunto, lotto/selezione:aggiunto | lotto:mtime |
| X03-prepare/compensate/G-folder-readonly | bloccato (5/5) | no | lotto:size, lotto:mode, lotto/consegna:aggiunto, lotto/selezione:aggiunto | lotto:mtime |
| S06-b/compensate/G-volume-missing | bloccato (5/5) | no | lotto:size, lotto/2026-08-24_evento_001.jpg:aggiunto, lotto/2026-08-24_evento_001.xmp:aggiunto, lotto/IMG_0001.jpg:rimosso, lotto/IMG_0001.xmp:rimosso, lotto/IMG_0002.jpg:rimosso, lotto/IMG_0002.xmp:rimosso, lotto/IMG_0003.jpg:rimosso, lotto/IMG_0003.xmp:rimosso, lotto/consegna:aggiunto, lotto/selezione:aggiunto, lotto/selezione/2026-08-24_evento_003.jpg:aggiunto, lotto/selezione/2026-08-24_evento_003.xmp:aggiunto, lotto/selezione/IMG_0002.jpg:aggiunto, lotto/selezione/IMG_0002.xmp:aggiunto | lotto:mtime |
| S06-b/compensate/G-folder-readonly | bloccato (5/5) | no | lotto:size, lotto:mode, lotto/2026-08-24_evento_001.jpg:aggiunto, lotto/2026-08-24_evento_001.xmp:aggiunto, lotto/IMG_0001.jpg:rimosso, lotto/IMG_0001.xmp:rimosso, lotto/IMG_0002.jpg:rimosso, lotto/IMG_0002.xmp:rimosso, lotto/IMG_0003.jpg:rimosso, lotto/IMG_0003.xmp:rimosso, lotto/consegna:aggiunto, lotto/selezione:aggiunto, lotto/selezione/2026-08-24_evento_003.jpg:aggiunto, lotto/selezione/2026-08-24_evento_003.xmp:aggiunto, lotto/selezione/IMG_0002.jpg:aggiunto, lotto/selezione/IMG_0002.xmp:aggiunto | lotto:mtime |
| S06-b/compensate/L-locked | parzialmente-recuperato (5/5) | no | lotto/IMG_0003.xmp:rimosso, lotto/selezione:aggiunto, lotto/selezione/2026-08-24_evento_003.xmp:aggiunto | lotto:mtime |
| S06-b/compensate/L-collision | parzialmente-recuperato (5/5) | no | lotto:size, lotto/IMG_0003.xmp:size, lotto/IMG_0003.xmp:sha256, lotto/IMG_0003.xmp:mtime, lotto/IMG_0003.xmp:birthtime, lotto/IMG_0003.xmp:inode, lotto/selezione:aggiunto, lotto/selezione/2026-08-24_evento_003.xmp:aggiunto | lotto:mtime |
| S06-b/compensate/L-modified | parzialmente-recuperato (5/5) | no | lotto/IMG_0003.xmp:rimosso, lotto/selezione:aggiunto, lotto/selezione/2026-08-24_evento_003.xmp:aggiunto | lotto:mtime |
| S06-b/compensate/L-missing | parzialmente-recuperato (5/5) | no | lotto:size, lotto/IMG_0003.xmp:rimosso | lotto:mtime |
| S10-c/compensate/G-volume-missing | bloccato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0005.jpg:aggiunto, @cestino/IMG_0005.xmp:aggiunto, lotto:size, lotto/2026-08-24_evento_001.jpg:aggiunto, lotto/2026-08-24_evento_001.xmp:aggiunto, lotto/IMG_0001.jpg:rimosso, lotto/IMG_0001.xmp:rimosso, lotto/IMG_0002.jpg:rimosso, lotto/IMG_0002.xmp:rimosso, lotto/IMG_0003.jpg:rimosso, lotto/IMG_0003.xmp:rimosso, lotto/IMG_0005.jpg:rimosso, lotto/IMG_0005.xmp:rimosso, lotto/consegna:aggiunto, lotto/consegna/IMG_0004.jpg:aggiunto, lotto/consegna/IMG_0004.xmp:aggiunto, lotto/selezione:aggiunto, lotto/selezione/2026-08-24_evento_003.jpg:aggiunto, lotto/selezione/2026-08-24_evento_003.xmp:aggiunto, lotto/selezione/IMG_0002.jpg:aggiunto, lotto/selezione/IMG_0002.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| S10-c/compensate/G-folder-readonly | bloccato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0005.jpg:aggiunto, @cestino/IMG_0005.xmp:aggiunto, lotto:size, lotto:mode, lotto/2026-08-24_evento_001.jpg:aggiunto, lotto/2026-08-24_evento_001.xmp:aggiunto, lotto/IMG_0001.jpg:rimosso, lotto/IMG_0001.xmp:rimosso, lotto/IMG_0002.jpg:rimosso, lotto/IMG_0002.xmp:rimosso, lotto/IMG_0003.jpg:rimosso, lotto/IMG_0003.xmp:rimosso, lotto/IMG_0005.jpg:rimosso, lotto/IMG_0005.xmp:rimosso, lotto/consegna:aggiunto, lotto/consegna/IMG_0004.jpg:aggiunto, lotto/consegna/IMG_0004.xmp:aggiunto, lotto/selezione:aggiunto, lotto/selezione/2026-08-24_evento_003.jpg:aggiunto, lotto/selezione/2026-08-24_evento_003.xmp:aggiunto, lotto/selezione/IMG_0002.jpg:aggiunto, lotto/selezione/IMG_0002.xmp:aggiunto | @cestino:mtime, lotto:mtime |
| S10-c/compensate/L-locked | parzialmente-recuperato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto, @cestino/IMG_0005.xmp:aggiunto, lotto:size, lotto/IMG_0005.xmp:rimosso | @cestino:mtime, lotto:mtime |
| S10-c/compensate/L-collision | parzialmente-recuperato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto, @cestino/IMG_0005.xmp:aggiunto, lotto/IMG_0005.xmp:size, lotto/IMG_0005.xmp:sha256, lotto/IMG_0005.xmp:mtime, lotto/IMG_0005.xmp:birthtime, lotto/IMG_0005.xmp:inode | @cestino:mtime, lotto:mtime |
| S10-c/compensate/L-modified | parzialmente-recuperato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto, @cestino/IMG_0005.xmp:aggiunto, lotto:size, lotto/IMG_0005.xmp:rimosso | @cestino:mtime, lotto:mtime |
| S10-c/compensate/L-trash-emptied | parzialmente-recuperato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto, lotto:size, lotto/IMG_0005.xmp:rimosso | @cestino:mtime, lotto:mtime |
| S10-c/compensate/L-missing | parzialmente-recuperato (5/5) | no | @cestino:size, @cestino/.DS_Store:aggiunto, @cestino/IMG_0004.jpg:aggiunto, @cestino/IMG_0004.xmp:aggiunto, lotto:size, lotto/IMG_0005.xmp:rimosso | @cestino:mtime, lotto:mtime |

**Scostamenti ricorrenti e loro causa.**

- **Solo 2 celle su 74 coincidono con lo stato iniziale**: `X01-plan/compensate` e `X02-recheck/compensate`, arresti prima che il lotto creasse alcunché. Nelle altre 57 celle `compensato` ogni immagine e ogni sidecar torna all'origine con il digest del piano, e nessun file del lotto ha uno scostamento di contenuto, inode o `birthtime`; lo stato però non coincide con quello di partenza.
- **`lotto:mtime`**, in 72 righe su 74. La preparazione crea `selezione/` e `consegna/` nella cartella del lotto, e la compensazione le rimuove con `rmdir`: il contenuto della cartella torna quello di partenza, il suo `mtime` no. In 23 celle `compensato` è l'unico scostamento.
- **`@cestino/IMG_0004.jpg:aggiunto` e `@cestino/IMG_0004.xmp:aggiunto`**, in 34 celle `compensato`. Compensare `OP4`, la copia, significa spostare la copia nel Cestino del volume, perché NFR-A1 vieta le eliminazioni dirette: dopo una compensazione corretta le copie restano nel Cestino. Il solo `.jpg` compare nelle 4 celle in cui la copia del sidecar non era ancora pubblicata: `S07-b`, `S07-c`, `S08-a` e `S08-m`. In `S08-m` il temporaneo della copia del sidecar è rimosso con `unlink`, per la politica del banco.
- **`@cestino/.DS_Store:aggiunto`, `@cestino:size` e `@cestino:mtime`**, nelle stesse 34 celle. Il sistema crea `.DS_Store` nel Cestino del volume alla prima voce, e la cartella del Cestino cambia dimensione e `mtime` con le voci che riceve.
- **Nessuno scostamento su `IMG_0005`** in alcuna cella `compensato`. Quando la compensazione riporta `OP5` dal Cestino lo trova per digest e lo rimette all'origine, e nel Cestino non ne resta traccia.
- **Nelle celle di perturbazione gli scostamenti nominano ciò che la compensazione non ha potuto riportare.**
  - `S06-b/compensate/L-locked` e `S06-b/compensate/L-modified`: il sidecar di `OP3` resta nella destinazione (`lotto/selezione/2026-08-24_evento_003.xmp:aggiunto`, `lotto/IMG_0003.xmp:rimosso`), e `lotto/selezione:aggiunto` perché la cartella, non vuota, non si rimuove.
  - `S06-b/compensate/L-collision`: il file estraneo occupa l'origine (`lotto/IMG_0003.xmp` con `size`, `sha256`, `mtime`, `birthtime` e `inode` diversi) e il sidecar resta nella destinazione.
  - `S06-b/compensate/L-missing`, `S10-c/compensate/L-trash-emptied` e `S10-c/compensate/L-missing`: il sidecar manca (`lotto/IMG_0003.xmp:rimosso`, `lotto/IMG_0005.xmp:rimosso`).
  - `S10-c/compensate/L-locked` e `S10-c/compensate/L-modified`: il sidecar di `OP5` resta nel Cestino (`@cestino/IMG_0005.xmp:aggiunto`). In `S10-c/compensate/L-collision` resta nel Cestino e l'origine è occupata dal file estraneo.
  - Le 6 celle `bloccato`: nessun passo è compensato, quindi gli scostamenti sono lo stato del lotto all'arresto, più `lotto:mode` dove la cartella resta non scrivibile.

## Classi di errore

Le otto classi si applicano fra l'arresto e il recupero (`crashbench perturb`), a `X03-prepare`, `S06-b` e `S10-c`, in ripresa e in compensazione.

- «Ambito adottato» è l'ambito che il classificatore assegna alla classe.
- «Errore osservato» è il fallimento registrato dal recupero nel log (`step-failed`), con le chiamate che lo hanno prodotto.
- «Celle provate» sono le celle applicabili della classe, e «Esiti» somma le loro ripetizioni.

| Classe | Ambito adottato | Errore osservato | Celle provate | Esiti | Classificazione confermata |
|---|---|---|---|---|---|
| G-volume-missing | sistemico | non applicabile (volume assente riconosciuto prima di agire) | X03-prepare/resume/G-volume-missing, X03-prepare/compensate/G-volume-missing, S06-b/resume/G-volume-missing, S06-b/compensate/G-volume-missing, S10-c/resume/G-volume-missing, S10-c/compensate/G-volume-missing | bloccato (30/30) | sì |
| G-folder-readonly | sistemico | errno 13 (EACCES) da renamex_np, rmdir, copyfile | X03-prepare/resume/G-folder-readonly, X03-prepare/compensate/G-folder-readonly, S06-b/resume/G-folder-readonly, S06-b/compensate/G-folder-readonly, S10-c/resume/G-folder-readonly, S10-c/compensate/G-folder-readonly | bloccato (25/30); completato (5/30) | sì |
| G-space-exhausted | sistemico | errno 28 (ENOSPC) da renamex_np, copyfile | X03-prepare/resume/G-space-exhausted, S06-b/resume/G-space-exhausted | bloccato (10/10) | sì |
| L-locked | locale | errno 1 (EPERM) da renamex_np; Cocoa NSCocoaErrorDomain 513 / NSOSStatusErrorDomain -5000 da trashItem | X03-prepare/resume/L-locked, S06-b/resume/L-locked, S06-b/compensate/L-locked, S10-c/compensate/L-locked | parzialmente-recuperato (20/20) | sì |
| L-collision | locale | non applicabile (riconosciuta dal disco prima di agire) | X03-prepare/resume/L-collision, S06-b/resume/L-collision, S06-b/compensate/L-collision, S10-c/compensate/L-collision | parzialmente-recuperato (20/20) | sì |
| L-modified | locale | non applicabile (riconosciuta dal disco prima di agire) | X03-prepare/resume/L-modified, S06-b/resume/L-modified, S06-b/compensate/L-modified, S10-c/compensate/L-modified | parzialmente-recuperato (20/20) | no — in S10-c/compensate/L-modified il recupero adotta L-trash-emptied, con lo stesso ambito e lo stesso esito: la voce modificata del Cestino non ha più il digest del piano, e il Cestino si cerca per digest |
| L-trash-emptied | locale | non applicabile (riconosciuta dal disco prima di agire) | S10-c/compensate/L-trash-emptied | parzialmente-recuperato (5/5) | sì |
| L-missing | locale | non applicabile (riconosciuta dal disco prima di agire) | X03-prepare/resume/L-missing, S06-b/resume/L-missing, S06-b/compensate/L-missing, S10-c/compensate/L-missing | parzialmente-recuperato (20/20) | no — in S10-c/compensate/L-missing il recupero adotta L-trash-emptied, con lo stesso ambito e lo stesso esito: una voce sparita dal Cestino non si distingue da un Cestino svuotato |

**Errore locale ed errore sistemico.**

- **Un errore sistemico sospende il lotto.** Delle 14 celle applicabili delle tre classi `G-*`, 13 finiscono `bloccato` in 5 ripetizioni su 5. Il recupero si ferma al primo passo che incontra l'errore e non tocca i passi successivi: ogni cella bloccata registra **al più un** fallimento, nessuno con il volume assente, e nessuna lo ripete sui file restanti (FR-079).
- **Il volume assente si riconosce prima di agire.** Con `G-volume-missing` il recupero non tenta alcun passo: riconosce che la radice del lotto non è sul volume del piano e sospende tutti e dieci i passi. È la ragione della classificazione per ambito e non per errno: dopo l'espulsione una rinomina restituirebbe `ENOENT`, lo stesso errno di un file scomparso.
- **Un errore sistemico morde solo se un passo lo incontra.** `S10-c/resume/G-folder-readonly` conclude `completato` in 5 ripetizioni su 5: a `S10-c` ogni passo è già fatto, e la ripresa non deve scrivere nelle cartelle rese non scrivibili.
- **Un errore locale fa saltare il file, e il lotto prosegue.** Tutte le 17 celle applicabili delle cinque classi `L-*` finiscono `parzialmente-recuperato` in 5 ripetizioni su 5: il passo colpito è `saltato`, gli altri si concludono nella direzione del recupero, e nessuna cella finisce `bloccato`. `L-collision`, `L-modified`, `L-missing` e `L-trash-emptied` sono riconosciute dal disco prima di agire, senza alcuna chiamata fallita. `L-locked` si scopre solo agendo: `EPERM` da `renamex_np`, oppure l'errore Cocoa 513 di `trashItem`, che non porta alcun errno.
- **Lo spazio esaurito può mordere anche le rinomine.** In `X03-prepare/resume/G-space-exhausted` il bersaglio dichiarato è la copia `S07`, ma il primo passo a fallire è la rinomina `S01`: `renamex_np` restituisce `ENOSPC` in 5 ripetizioni su 5. La sonda della baseline aveva visto riuscire una rinomina su un volume pieno; questa misura la smentisce, su questo volume riempito fino all'ultimo byte. È una sola cella, misurata in un solo stato del volume pieno (limite 13): basta a smentire «le rinomine riescono sempre», non a dire che falliscano sempre. La classificazione regge, perché si fonda su `ENOSPC` e non sul tipo di passo. La restrizione «solo copie» delle perturbazioni, invece, non regge.
- **Il Cestino si cerca per digest, e assorbe due classi.** In compensazione di un passo Cestino già eseguito, `L-modified` e `L-missing` sulla voce del Cestino si classificano `L-trash-emptied` (`S10-c/compensate/L-modified`, `S10-c/compensate/L-missing`). Sul disco i tre stati coincidono: nessuna voce del Cestino ha il digest del piano. L'ambito e l'esito non cambiano.

## Punti bloccati in attesa dell'utente

Una riga per ogni cella con almeno una ripetizione `bloccato`. Dopo ogni `bloccato` il banco prova i due rami dell'utente, ciascuno 5 volte:

- `retry`, su una ripetizione nuova: rimozione della causa (`unperturb`), poi `decide retry`;
- `abandon`, sulla stessa ripetizione: `decide abandon`.

| Cella | Classe | Ambito | Ragione | Esito dopo retry | Esito dopo abandon |
|---|---|---|---|---|---|
| X03-prepare/resume/G-volume-missing | G-volume-missing | sistemico | il volume del lotto non c'è: il recupero lo riconosce prima di agire e sospende ogni passo, perché né riprendere né compensare è possibile senza il volume; solo l'utente può ricollegarlo o rinunciare | completato (5/5) | abbandonato (5/5) |
| X03-prepare/resume/G-folder-readonly | G-folder-readonly | sistemico | le cartelle del lotto non sono scrivibili: il passo S01 fallisce con EACCES su renamex_np, e ogni passo restante fallirebbe allo stesso modo; solo l'utente può ripristinare il permesso | completato (5/5) | abbandonato (5/5) |
| X03-prepare/resume/G-space-exhausted | G-space-exhausted | sistemico | il volume è pieno: il passo S01 fallisce con ENOSPC su renamex_np, e proseguire ripeterebbe il fallimento sui passi restanti; solo l'utente può liberare spazio | completato (5/5) | abbandonato (5/5) |
| X03-prepare/compensate/G-volume-missing | G-volume-missing | sistemico | il volume del lotto non c'è: il recupero lo riconosce prima di agire e sospende ogni passo, perché né riprendere né compensare è possibile senza il volume; solo l'utente può ricollegarlo o rinunciare | compensato (5/5) | abbandonato (5/5) |
| X03-prepare/compensate/G-folder-readonly | G-folder-readonly | sistemico | le cartelle del lotto non sono scrivibili: la rimozione delle cartelle preparate fallisce con EACCES su rmdir, e la compensazione non può concludersi finché il permesso non torna; solo l'utente può ripristinarlo | compensato (5/5) | abbandonato (5/5) |
| S06-b/resume/G-volume-missing | G-volume-missing | sistemico | il volume del lotto non c'è: il recupero lo riconosce prima di agire e sospende ogni passo, perché né riprendere né compensare è possibile senza il volume; solo l'utente può ricollegarlo o rinunciare | completato (5/5) | abbandonato (5/5) |
| S06-b/resume/G-folder-readonly | G-folder-readonly | sistemico | le cartelle del lotto non sono scrivibili: il passo S07 fallisce con EACCES su copyfile, e ogni passo restante fallirebbe allo stesso modo; solo l'utente può ripristinare il permesso | completato (5/5) | abbandonato (5/5) |
| S06-b/resume/G-space-exhausted | G-space-exhausted | sistemico | il volume è pieno: il passo S07 fallisce con ENOSPC su copyfile, e proseguire ripeterebbe il fallimento sui passi restanti; solo l'utente può liberare spazio | completato (5/5) | abbandonato (5/5) |
| S06-b/compensate/G-volume-missing | G-volume-missing | sistemico | il volume del lotto non c'è: il recupero lo riconosce prima di agire e sospende ogni passo, perché né riprendere né compensare è possibile senza il volume; solo l'utente può ricollegarlo o rinunciare | compensato (5/5) | abbandonato (5/5) |
| S06-b/compensate/G-folder-readonly | G-folder-readonly | sistemico | le cartelle del lotto non sono scrivibili: il passo S06 fallisce con EACCES su renamex_np, e ogni passo restante fallirebbe allo stesso modo; solo l'utente può ripristinare il permesso | compensato (5/5) | abbandonato (5/5) |
| S10-c/resume/G-volume-missing | G-volume-missing | sistemico | il volume del lotto non c'è: il recupero lo riconosce prima di agire e sospende ogni passo, perché né riprendere né compensare è possibile senza il volume; solo l'utente può ricollegarlo o rinunciare | completato (5/5) | abbandonato (5/5) |
| S10-c/compensate/G-volume-missing | G-volume-missing | sistemico | il volume del lotto non c'è: il recupero lo riconosce prima di agire e sospende ogni passo, perché né riprendere né compensare è possibile senza il volume; solo l'utente può ricollegarlo o rinunciare | compensato (5/5) | abbandonato (5/5) |
| S10-c/compensate/G-folder-readonly | G-folder-readonly | sistemico | le cartelle del lotto non sono scrivibili: il passo S10 fallisce con EACCES su renamex_np, e ogni passo restante fallirebbe allo stesso modo; solo l'utente può ripristinare il permesso | compensato (5/5) | abbandonato (5/5) |

- **I 13 punti sono tutti sistemici**: 6 `G-volume-missing`, 5 `G-folder-readonly` e 2 `G-space-exhausted`. Nessun errore locale finisce `bloccato`, e nessuna cella `NON_SUPPORTABILE` compare in questa tabella. La traccia di ogni cella è `errore sistemico non risolto: <classe>`: `bloccato` nasce solo dalla regola 4 del classificatore degli esiti.
- **Il blocco è legittimo, e la decisione dell'utente lo chiude.** In tutti e tredici la direzione del recupero non può procedere finché la causa resta. Rimossa la causa, `retry` conclude nella direzione del log, `completato` per le celle in ripresa e `compensato` per quelle in compensazione, in 5 rami su 5. `abandon` conclude `abbandonato` in 5 rami su 5, senza toccare i file, e riferisce dove è rimasto ciascuno. L'esito dei rami `retry` è quello stampato dalla macchina: la matrice non vi prende un'istantanea finale e non vi applica gli oracoli del disco.
- **Le posizioni riferite reggono.** In nessun ramo `abandon` le posizioni riferite contraddicono l'istantanea. Con il volume assente le righe `COPPIA` del recupero bloccato dicono `amb`, cioè non osservabile, e non sono un'affermazione di posizione; `decide abandon` si esegue dopo che il volume è tornato.

## Separazione di immagine e sidecar

Una riga per ogni cella in cui il banco osserva coppie separate nell'istantanea da cui parte il recupero: dopo l'arresto; dopo la perturbazione, per le celle di perturbazione; dopo il secondo arresto, per `D01` e `D02`.

- «Rilevata dal recupero» confronta quelle separazioni con la riga `SEPARAZIONI-ALL-AVVIO` stampata dal recupero.
- «Cosa riferisce» riporta quella riga e la posizione finale della coppia. La posizione viene dall'istantanea dopo il recupero, e coincide con la riga `COPPIA` del recupero in ogni ripetizione (0 `RICONOSCIMENTO_ERRATO`).

| Cella | Coppie separate all'arresto | Rilevata dal recupero | Cosa riferisce | Separazioni residue |
|---|---|---|---|---|
| S01-b/resume | OP1 | rilevata | SEPARAZIONI-ALL-AVVIO OP1; dopo il recupero COPPIA OP1 i:dest s:dest | nessuna |
| S01-b/compensate | OP1 | rilevata | SEPARAZIONI-ALL-AVVIO OP1; dopo il recupero COPPIA OP1 i:orig s:orig | nessuna |
| S01-c/resume | OP1 | rilevata | SEPARAZIONI-ALL-AVVIO OP1; dopo il recupero COPPIA OP1 i:dest s:dest | nessuna |
| S01-c/compensate | OP1 | rilevata | SEPARAZIONI-ALL-AVVIO OP1; dopo il recupero COPPIA OP1 i:orig s:orig | nessuna |
| S02-a/resume | OP1 | rilevata | SEPARAZIONI-ALL-AVVIO OP1; dopo il recupero COPPIA OP1 i:dest s:dest | nessuna |
| S02-a/compensate | OP1 | rilevata | SEPARAZIONI-ALL-AVVIO OP1; dopo il recupero COPPIA OP1 i:orig s:orig | nessuna |
| S03-b/resume | OP2 | rilevata | SEPARAZIONI-ALL-AVVIO OP2; dopo il recupero COPPIA OP2 i:dest s:dest | nessuna |
| S03-b/compensate | OP2 | rilevata | SEPARAZIONI-ALL-AVVIO OP2; dopo il recupero COPPIA OP2 i:orig s:orig | nessuna |
| S03-c/resume | OP2 | rilevata | SEPARAZIONI-ALL-AVVIO OP2; dopo il recupero COPPIA OP2 i:dest s:dest | nessuna |
| S03-c/compensate | OP2 | rilevata | SEPARAZIONI-ALL-AVVIO OP2; dopo il recupero COPPIA OP2 i:orig s:orig | nessuna |
| S04-a/resume | OP2 | rilevata | SEPARAZIONI-ALL-AVVIO OP2; dopo il recupero COPPIA OP2 i:dest s:dest | nessuna |
| S04-a/compensate | OP2 | rilevata | SEPARAZIONI-ALL-AVVIO OP2; dopo il recupero COPPIA OP2 i:orig s:orig | nessuna |
| S05-b/resume | OP3 | rilevata | SEPARAZIONI-ALL-AVVIO OP3; dopo il recupero COPPIA OP3 i:dest s:dest | nessuna |
| S05-b/compensate | OP3 | rilevata | SEPARAZIONI-ALL-AVVIO OP3; dopo il recupero COPPIA OP3 i:orig s:orig | nessuna |
| S05-c/resume | OP3 | rilevata | SEPARAZIONI-ALL-AVVIO OP3; dopo il recupero COPPIA OP3 i:dest s:dest | nessuna |
| S05-c/compensate | OP3 | rilevata | SEPARAZIONI-ALL-AVVIO OP3; dopo il recupero COPPIA OP3 i:orig s:orig | nessuna |
| S06-a/resume | OP3 | rilevata | SEPARAZIONI-ALL-AVVIO OP3; dopo il recupero COPPIA OP3 i:dest s:dest | nessuna |
| S06-a/compensate | OP3 | rilevata | SEPARAZIONI-ALL-AVVIO OP3; dopo il recupero COPPIA OP3 i:orig s:orig | nessuna |
| S07-b/resume | OP4 | rilevata | SEPARAZIONI-ALL-AVVIO OP4; dopo il recupero COPPIA OP4 i:dest s:dest | nessuna |
| S07-b/compensate | OP4 | rilevata | SEPARAZIONI-ALL-AVVIO OP4; dopo il recupero COPPIA OP4 i:orig s:orig | nessuna |
| S07-c/resume | OP4 | rilevata | SEPARAZIONI-ALL-AVVIO OP4; dopo il recupero COPPIA OP4 i:dest s:dest | nessuna |
| S07-c/compensate | OP4 | rilevata | SEPARAZIONI-ALL-AVVIO OP4; dopo il recupero COPPIA OP4 i:orig s:orig | nessuna |
| S08-a/resume | OP4 | rilevata | SEPARAZIONI-ALL-AVVIO OP4; dopo il recupero COPPIA OP4 i:dest s:dest | nessuna |
| S08-a/compensate | OP4 | rilevata | SEPARAZIONI-ALL-AVVIO OP4; dopo il recupero COPPIA OP4 i:orig s:orig | nessuna |
| S08-m/resume | OP4 | rilevata | SEPARAZIONI-ALL-AVVIO OP4; dopo il recupero COPPIA OP4 i:dest s:dest | nessuna |
| S08-m/compensate | OP4 | rilevata | SEPARAZIONI-ALL-AVVIO OP4; dopo il recupero COPPIA OP4 i:orig s:orig | nessuna |
| S09-b/resume | OP5 | rilevata | SEPARAZIONI-ALL-AVVIO OP5; dopo il recupero COPPIA OP5 i:cest s:cest | nessuna |
| S09-b/compensate | OP5 | rilevata | SEPARAZIONI-ALL-AVVIO OP5; dopo il recupero COPPIA OP5 i:orig s:orig | nessuna |
| S09-c/resume | OP5 | rilevata | SEPARAZIONI-ALL-AVVIO OP5; dopo il recupero COPPIA OP5 i:cest s:cest | nessuna |
| S09-c/compensate | OP5 | rilevata | SEPARAZIONI-ALL-AVVIO OP5; dopo il recupero COPPIA OP5 i:orig s:orig | nessuna |
| S10-a/resume | OP5 | rilevata | SEPARAZIONI-ALL-AVVIO OP5; dopo il recupero COPPIA OP5 i:cest s:cest | nessuna |
| S10-a/compensate | OP5 | rilevata | SEPARAZIONI-ALL-AVVIO OP5; dopo il recupero COPPIA OP5 i:orig s:orig | nessuna |
| S05-torn/resume | OP3 | rilevata | SEPARAZIONI-ALL-AVVIO OP3; dopo il recupero COPPIA OP3 i:dest s:dest | nessuna |
| S05-torn/compensate | OP3 | rilevata | SEPARAZIONI-ALL-AVVIO OP3; dopo il recupero COPPIA OP3 i:orig s:orig | nessuna |
| K10-b/compensate | OP5 | rilevata | SEPARAZIONI-ALL-AVVIO OP5; dopo il recupero COPPIA OP5 i:orig s:orig | nessuna |
| K09-a/compensate | OP5 | rilevata | SEPARAZIONI-ALL-AVVIO OP5; dopo il recupero COPPIA OP5 i:orig s:orig | nessuna |
| K08-b/compensate | OP4 | rilevata | SEPARAZIONI-ALL-AVVIO OP4; dopo il recupero COPPIA OP4 i:orig s:orig | nessuna |
| K07-a/compensate | OP4 | rilevata | SEPARAZIONI-ALL-AVVIO OP4; dopo il recupero COPPIA OP4 i:orig s:orig | nessuna |
| K06-b/compensate | OP3 | rilevata | SEPARAZIONI-ALL-AVVIO OP3; dopo il recupero COPPIA OP3 i:orig s:orig | nessuna |
| K05-a/compensate | OP3 | rilevata | SEPARAZIONI-ALL-AVVIO OP3; dopo il recupero COPPIA OP3 i:orig s:orig | nessuna |
| K04-b/compensate | OP2 | rilevata | SEPARAZIONI-ALL-AVVIO OP2; dopo il recupero COPPIA OP2 i:orig s:orig | nessuna |
| K03-a/compensate | OP2 | rilevata | SEPARAZIONI-ALL-AVVIO OP2; dopo il recupero COPPIA OP2 i:orig s:orig | nessuna |
| K02-b/compensate | OP1 | rilevata | SEPARAZIONI-ALL-AVVIO OP1; dopo il recupero COPPIA OP1 i:orig s:orig | nessuna |
| K01-a/compensate | OP1 | rilevata | SEPARAZIONI-ALL-AVVIO OP1; dopo il recupero COPPIA OP1 i:orig s:orig | nessuna |
| X03-prepare/resume/L-modified | OP1 | rilevata | SEPARAZIONI-ALL-AVVIO OP1; dopo il recupero COPPIA OP1 i:ass s:dest | OP1 |
| X03-prepare/resume/L-missing | OP1 | rilevata | SEPARAZIONI-ALL-AVVIO OP1; dopo il recupero COPPIA OP1 i:ass s:dest | OP1 |
| S06-b/resume/L-modified | OP4 | rilevata | SEPARAZIONI-ALL-AVVIO OP4; dopo il recupero COPPIA OP4 i:ass s:dest | OP4 |
| S06-b/resume/L-missing | OP4 | rilevata | SEPARAZIONI-ALL-AVVIO OP4; dopo il recupero COPPIA OP4 i:ass s:dest | OP4 |
| S06-b/compensate/L-modified | OP3 | rilevata | SEPARAZIONI-ALL-AVVIO OP3; dopo il recupero COPPIA OP3 i:orig s:ass | OP3 |
| S06-b/compensate/L-missing | OP3 | rilevata | SEPARAZIONI-ALL-AVVIO OP3; dopo il recupero COPPIA OP3 i:orig s:ass | OP3 |
| S10-c/compensate/L-modified | OP5 | rilevata | SEPARAZIONI-ALL-AVVIO OP5; dopo il recupero COPPIA OP5 i:orig s:ass | OP5 |
| S10-c/compensate/L-trash-emptied | OP5 | rilevata | SEPARAZIONI-ALL-AVVIO OP5; dopo il recupero COPPIA OP5 i:orig s:ass | OP5 |
| S10-c/compensate/L-missing | OP5 | rilevata | SEPARAZIONI-ALL-AVVIO OP5; dopo il recupero COPPIA OP5 i:orig s:ass | OP5 |

- **La separazione è rilevata in tutte le 53 celle**, 44 di base e 9 di perturbazione. In nessuna delle 146 celle una separazione sfugge al recupero (`non-rilevata`) o è riferita senza esserci (`falsa-segnalazione`).
- **Nelle 44 celle di base la coppia si ricompone.** Sono gli arresti fra il passo dell'immagine e quello del sidecar, e i corrispondenti punti `K*`. La ripresa porta il sidecar a destinazione, la compensazione riporta l'immagine all'origine, e il recupero riferisce `SEPARAZIONI-RESIDUE nessuna`.
- **Nelle 9 celle di perturbazione la separazione resta.** `L-modified`, `L-missing` e `L-trash-emptied` colpiscono un solo file della coppia: la separazione nasce dalla perturbazione, non dall'arresto, che non ne lasciava alcuna. Il recupero la riferisce all'avvio e di nuovo come residua, con il file colpito in `ass`.
- **Il recupero stesso può separare una coppia.** In 8 celle senza separazioni all'avvio il salto di un solo file per errore locale lascia la coppia separata alla fine, e il recupero lo riferisce in `SEPARAZIONI-RESIDUE`: X03-prepare/resume/L-locked (OP1), X03-prepare/resume/L-collision (OP1), S06-b/resume/L-locked (OP5), S06-b/resume/L-collision (OP4), S06-b/compensate/L-locked (OP3), S06-b/compensate/L-collision (OP3), S10-c/compensate/L-locked (OP5), S10-c/compensate/L-collision (OP5). È l'effetto del salto per file (FR-079) su una coppia che dovrebbe viaggiare unita (FR-053).
- **Doppio arresto.** `D01` e `D02` separano `OP2` al primo arresto, a `S03-b`. Al secondo arresto il primo recupero ha già ricomposto la coppia, e il secondo recupero non ha separazioni da riferire.

## Esiti non supportabili

Una riga per ogni cella con almeno una ripetizione `NON_SUPPORTABILE` o con `RICONOSCIMENTO_ERRATO`. La misura non ha celle `RICONOSCIMENTO_ERRATO`.

| Cella | Motivo | Traccia |
|---|---|---|
| X00-plan-torn/resume | nessun-esito-applicabile (5/5) | log senza piano completo: per costruzione del log di intenti nessuna azione è stata eseguita |
| X00-plan-torn/compensate | nessun-esito-applicabile (5/5) | log senza piano completo: per costruzione del log di intenti nessuna azione è stata eseguita |

In `X00-plan-torn` il processo muore dopo aver scritto e sincronizzato metà del record del piano.

- Il recupero riconosce il record troncato (`RECORD-TRONCATO si`), ne conserva il frammento come evidenza e tronca il log all'ultima riga completa. Non ne resta alcuna: il log non ha un piano.
- Lo stato è riconoscibile. Nessuna azione è stata eseguita, e l'istantanea dopo il recupero mostra tutte e cinque le coppie all'origine.
- Nessuno dei cinque esiti lo descrive: il lotto non è completato, non c'è nulla da compensare, nessun errore attende l'utente e l'utente non ha abbandonato nulla.
- La regola 1 del classificatore degli esiti lo registra `NON_SUPPORTABILE`, motivo `nessun-esito-applicabile`, con la direzione `nessuna`, in 5 ripetizioni su 5 per ciascuna strategia.

**Nessuna di queste celle è stata riclassificata come «bloccato in attesa dell'utente».** Non compaiono in § *Punti bloccati in attesa dell'utente*, e il classificatore degli esiti non ha alcuna regola che porti a `bloccato` uno stato senza esito o non riconoscibile. Il caso è invece la traccia dell'insieme di esiti sostitutivo proposto in § *Esito su ADR-007*.

## Esito su ADR-007

ADR-007: **emendato**

Testo del PRD (`docs/PRD.md`, riga 530):

> **ADR-007 — Operazioni massive recuperabili, non atomiche, con cinque esiti dichiarati.** *Decisione:* `FileOps` è una macchina a stati con log di intenti scritto **prima** dell'azione: piano e precondizioni registrati → **ricontrollo delle precondizioni dopo il dry-run e immediatamente prima di agire** → lotto preparato → passi **idempotenti** eseguiti e registrati uno a uno → conclusione in uno di **cinque esiti**: completato, compensato, parzialmente recuperato, bloccato in attesa dell'utente, abbandonato dall'utente. Un **errore locale** su un file lo fa saltare e il lotto prosegue; un **errore sistemico** — volume scomparso, permessi revocati, spazio esaurito — **sospende** il lotto. Le eliminazioni passano dal Cestino. *Motivo:* due correzioni. La prima: la promessa di un'unità indivisibile è insostenibile perché non esiste una transazione multi-file; il registro non rende atomico un lotto, lo rende recuperabile. La seconda: "ripreso o compensato" è binario, ma volume smontato, file modificato dall'esterno, spazio esaurito, permesso revocato o Cestino svuotato producono situazioni in cui **nessuna delle due** è possibile. Il contratto realistico non è "possiamo sempre concludere o riportare indietro" ma *"riconosciamo sempre lo stato raggiunto, tentiamo ripresa o compensazione, e dichiariamo esplicitamente ciò che richiede intervento umano"*. Analogamente, proseguire un lotto quando l'errore è sistemico produce centinaia di fallimenti identici e lo lascia a metà nel modo peggiore. *Conseguenza:* ogni passo va progettato idempotente e compensabile; gli esiti sono parte dell'interfaccia e non del registro interno, perché "bloccato in attesa dell'utente" richiede che l'utente lo sappia; la distinzione locale/sistemico va decisa per ogni classe di errore; il registro vive in `DurableState`. Anche il Cestino è dichiarato per quello che è: il sistema sposta l'elemento e riferisce dove è finito, senza promettere che vi resti. Verificato dal cancello n°4, che deve stabilire quali punti di interruzione finiscono legittimamente in "bloccato".

**Che cosa regge.**

- **Il contratto di recuperabilità.** Da ogni punto diverso da `X00-plan-torn` la strategia scelta conclude in 5 ripetizioni su 5 (96 celle di base), e il recupero riconosce dal disco lo stato di ogni file: 0 `RICONOSCIMENTO_ERRATO` in 146 celle, divergenze fra log e disco riferite e decise dal disco.
- **La distinzione fra errore locale ed errore sistemico.** Le 17 celle con errore locale finiscono `parzialmente-recuperato`; 13 delle 14 celle con errore sistemico finiscono `bloccato`, e la quattordicesima non incontra l'errore (§ *Classi di errore*).
- **I cinque esiti sono tutti raggiungibili**: `completato` in 38 celle, `compensato` in 59, `parzialmente-recuperato` in 17, `bloccato` in 13, `abbandonato` nei 65 rami `abandon` delle celle bloccate.
- **Le eliminazioni passano dal Cestino**, e la compensazione ritrova `OP5` nel Cestino per digest in ogni cella `compensato` in cui `OP5` era già stato cestinato.

**Che cosa non regge.**

1. **Il numero degli esiti.** `X00-plan-torn/resume` e `X00-plan-torn/compensate` non raggiungono alcuno dei cinque esiti, in 10 ripetizioni su 10, con motivo `nessun-esito-applicabile`. Lo stato è riconoscibile e nessuna azione è stata eseguita, ma l'insieme non ha un esito per un lotto che si ferma prima della prima azione sul disco. L'interruzione di FR-080 è lo stesso caso per costruzione: il PRD la prescrive e non è fra i cinque esiti, benché nessuna cella di questa matrice la raggiunga.
2. **La definizione di «compensato».** In 57 delle 59 celle `compensato` lo stato dopo la compensazione non coincide con quello di partenza: `lotto:mtime` in tutte e 57, e in 34 le copie di `OP4` e `.DS_Store` nel Cestino (per esempio `K00-b/compensate`). Coincide solo in `X01-plan/compensate` e `X02-recheck/compensate`. «Compensato» va quindi definito come «ogni passo riportato all'origine, con gli scostamenti dichiarati», non come ritorno allo stato di partenza.
3. **File modificato e Cestino svuotato non sospendono il lotto.** Il *Motivo* dell'ADR mette il file modificato dall'esterno e il Cestino svuotato fra le situazioni in cui né la ripresa né la compensazione sono possibili. La misura li mostra come errori locali su un solo file, che lo fanno saltare mentre il resto del lotto si conclude: `S10-c/compensate/L-trash-emptied`, `X03-prepare/resume/L-modified`, `S06-b/resume/L-modified` e `S06-b/compensate/L-modified` finiscono `parzialmente-recuperato` in 5 ripetizioni su 5.

**Le domande del cancello** (`docs/PRD.md`, riga 293):

- **Quale esito si raggiunge da ogni punto.** Da 60 dei 61 punti la ripresa conclude `completato` e la compensazione `compensato`, in 5 ripetizioni su 5; da `X00-plan-torn` nessuno dei cinque esiti si raggiunge; con un errore iniettato fra arresto e recupero l'esito è `parzialmente-recuperato` nelle 17 celle con errore locale e `bloccato` in 13 delle 14 con errore sistemico, da cui si arriva ad `abbandonato` solo per decisione dell'utente.
- **Se la compensazione è corretta.** Lo è per i passi, non per lo stato: in tutte le 59 celle `compensato` ogni immagine e ogni sidecar torna all'origine con il digest del piano, ma solo `X01-plan/compensate` e `X02-recheck/compensate` coincidono con lo stato di partenza, e le altre 57 lasciano gli scostamenti nominati in § *Compensazione*.
- **Quali casi finiscono legittimamente in «bloccato».** I 13 di § *Punti bloccati in attesa dell'utente*, tutti sistemici e incontrati da un passo: volume assente (6 celle), cartelle non scrivibili quando un passo deve scriverci (5), volume pieno quando un passo deve occupare spazio (2, `X03-prepare/resume/G-space-exhausted` e `S06-b/resume/G-space-exhausted`); nessun errore locale e nessuno stato senza esito.

### Insieme di esiti sostitutivo

Sei esiti invece di cinque. I cinque del PRD restano, con «compensato» precisato; si aggiunge **interrotto prima di agire**.

| Esito | Definizione | Celle della misura che lo motivano |
|---|---|---|
| completato | Ogni passo fatto nella direzione in avanti. | 38 celle, per esempio `S03-b/resume`, più i rami `retry` delle celle bloccate in ripresa. |
| compensato | Ogni passo eseguito riportato all'origine. Lo stato può differire da quello di partenza, e gli scostamenti si dichiarano. | 59 celle, per esempio `K05-a/compensate` e `D02/compensate`; coincidono con lo stato di partenza solo `X01-plan/compensate` e `X02-recheck/compensate`. |
| parzialmente recuperato | Almeno un file saltato per errore locale; il resto concluso. | 17 celle, per esempio `S06-b/resume/L-locked` e `S10-c/compensate/L-trash-emptied`. |
| bloccato in attesa dell'utente | Un errore sistemico non risolto, incontrato da un passo. | 13 celle, elencate in § *Punti bloccati in attesa dell'utente*. |
| abbandonato dall'utente | Decisione dell'utente su un lotto bloccato; i file restano dove sono, e la loro posizione si riferisce. | I 65 rami `abandon` delle 13 celle bloccate. |
| interrotto prima di agire | Nessuna azione eseguita sul disco: il piano non è stato registrato per intero, oppure il ricontrollo delle precondizioni lo ha fermato (FR-080). Nulla da riprendere né da compensare. | `X00-plan-torn/resume` e `X00-plan-torn/compensate`, oggi `NON_SUPPORTABILE` con motivo `nessun-esito-applicabile`. L'interruzione di FR-080 non è raggiunta da questa matrice. |

Uno stato non riconoscibile non entra nell'insieme: nessuna cella della misura ha il motivo `stato-non-riconoscibile`. Se la costruzione lo incontrasse, resta un esito non supportabile, dichiarato come tale e mai ricondotto a «bloccato».

### Testo di sostituzione

> **ADR-007 — Operazioni massive recuperabili, non atomiche, con sei esiti dichiarati.** *Decisione:* `FileOps` è una macchina a stati con log di intenti scritto **prima** dell'azione: piano e precondizioni registrati → **ricontrollo delle precondizioni dopo il dry-run e immediatamente prima di agire** → lotto preparato → passi **idempotenti** eseguiti e registrati uno a uno → conclusione in uno di **sei esiti**: completato, compensato, parzialmente recuperato, bloccato in attesa dell'utente, abbandonato dall'utente, interrotto prima di agire. *Interrotto prima di agire* è il lotto che si ferma prima della prima azione sul disco, perché il piano non è stato registrato per intero o perché il ricontrollo ha trovato le precondizioni cambiate: non c'è nulla da riprendere né da compensare. *Compensato* significa che ogni passo eseguito è stato riportato all'origine, **non** che il disco coincida con lo stato di partenza: la compensazione dichiara ciò che lascia, come l'`mtime` delle cartelle toccate, le copie annullate spostate nel Cestino invece che eliminate e i file che il sistema crea nel Cestino. Lo stato raggiunto si riconosce **dal disco, non dal log**, e ogni file si cerca per **digest**, anche nel Cestino, dove il sistema può assegnargli un altro nome; una divergenza fra log e disco si riporta, e decide il disco. Un **errore locale** su un file — file scomparso, bloccato, modificato dall'esterno, posizione di arrivo occupata, voce non più nel Cestino — lo fa saltare e il lotto prosegue; se il file appartiene a una coppia immagine-sidecar, la separazione che ne risulta si riporta. Un **errore sistemico** — volume scomparso, cartella non scrivibile, spazio esaurito, che può colpire anche le rinomine e non solo le copie — **sospende** il lotto al primo passo che lo incontra. La distinzione si decide per ambito della precondizione, nell'ordine volume, scrittura, spazio e cause locali, e mai dal solo errno. Le eliminazioni passano dal Cestino. *Motivo:* tre correzioni. La prima: la promessa di un'unità indivisibile è insostenibile perché non esiste una transazione multi-file; il registro non rende atomico un lotto, lo rende recuperabile. La seconda: "ripreso o compensato" è binario, ma volume smontato, spazio esaurito o permesso revocato producono situazioni in cui **nessuna delle due** è possibile senza l'utente; un file modificato dall'esterno o una voce sparita dal Cestino impediscono invece un solo file, non il lotto. La terza: un arresto prima che il piano sia registrato per intero lascia un lotto che nessuno dei cinque esiti della revisione precedente descriveva, e lo stesso vale per il ricontrollo che ferma il lotto prima di agire. Il contratto realistico non è "possiamo sempre concludere o riportare indietro" ma *"riconosciamo sempre lo stato raggiunto, tentiamo ripresa o compensazione, e dichiariamo esplicitamente ciò che richiede intervento umano"*. Analogamente, proseguire un lotto quando l'errore è sistemico produce centinaia di fallimenti identici e lo lascia a metà nel modo peggiore. *Conseguenza:* ogni passo va progettato idempotente e compensabile; gli esiti sono parte dell'interfaccia e non del registro interno, perché "bloccato in attesa dell'utente" richiede che l'utente lo sappia; l'annullamento elenca all'utente gli scostamenti che lascia; la classificazione di ogni classe di errore è quella misurata dal cancello n°4; il registro vive in `DurableState`. Anche il Cestino è dichiarato per quello che è: il sistema sposta l'elemento e riferisce dove è finito, senza promettere che vi resti. Verificato dal cancello n°4: finiscono legittimamente in "bloccato" solo gli errori sistemici che un passo incontra.

Il testo non è applicato a `docs/PRD.md`. La frase «il registro vive in `DurableState`» resta quella del PRD e non è verificata da questo cancello, che ha usato un registro JSONL (§ *Limiti dichiarati*, punto 3).

## Conseguenze per la costruzione

Che cosa la Tappa 3 eredita, misurato invece che ipotizzato. Ogni regola vale per un volume APFS locale e per il lotto di prova di questo cancello.

1. **La classificazione per ambito, nell'ordine misurato.** Volume prima di agire (la radice del lotto sul volume del piano), poi scrittura (`access(W_OK)` sulla radice e sulla cartella di arrivo), poi spazio (`ENOSPC`, `EDQUOT`), infine le cause locali osservate sul disco. Le otto righe di § *Classi di errore* sono la tabella di partenza: tre classi sistemiche, cinque locali. Lo spazio esaurito va trattato su ogni passo, rinomine comprese (`X03-prepare/resume/G-space-exhausted`).
2. **Il Cestino cercato per digest.** È ciò che permette alla compensazione di ritrovare `OP5` in ogni cella `compensato` in cui era già stato cestinato. Una voce modificata o sparita dal Cestino non si distingue da un Cestino svuotato (`S10-c/compensate/L-modified`, `S10-c/compensate/L-missing`): il prodotto può dire che l'elemento non è più nel Cestino con il contenuto atteso, non perché.
3. **La direzione di una compensazione avviata.** La regola del banco, il log prevale sulla strategia, va ereditata con un proprio test: questa matrice non la misura (§ *Limiti dichiarati*, punto 10). La misura mostra soltanto che una compensazione arrestata due volte si conclude `compensato` (`D02/compensate`, 5 su 5).
4. **Gli scostamenti da dichiarare all'utente dopo un annullamento** (FR-083): l'`mtime` delle cartelle toccate; le copie annullate spostate nel Cestino, in 34 celle; `.DS_Store` creato dal sistema nel Cestino. In un annullamento parziale, ogni file non riportato, con percorso e motivo, come le righe delle celle di perturbazione in § *Compensazione*.
5. **L'esito aggiuntivo.** «Interrotto prima di agire» entra nell'interfaccia, nella cronologia dei lotti (FR-078) e nel resoconto (FR-084). Un arresto durante la scrittura del piano va riconosciuto e dichiarato così, non come «bloccato» né come errore.
6. **Le coppie immagine-sidecar.** Il recupero riferisce le separazioni all'avvio e quelle residue, e la misura le conferma tutte (53 celle `rilevata`). Il salto per file separa la coppia in 8 celle con errore locale: la Tappa 3 deve decidere se un errore locale sull'immagine debba fermare anche il suo sidecar. Questo cancello non lo misura; misura solo che la separazione, se c'è, viene riferita.
7. **Log e disco.** In ogni punto `-b` il log dice «non fatto» e il disco «fatto». Il recupero del banco non riconcilia il log, e un secondo recupero riferisce di nuovo la stessa divergenza (`D01/resume`). Il registro del prodotto dovrebbe annotare ciò che il recupero ha riconosciuto.
8. **I temporanei di copia.** Il banco li rimuove con `unlink`, come artefatti del lotto e non come file dell'utente. Il prodotto deve dichiarare la stessa politica, o un'altra, rispetto a NFR-A1.
9. **Il banco come base dei test di iniezione.** Esiste ed è ripetibile, ma non gira in integrazione continua: portarlo in CI spetta alla Tappa 3. Prima va corretto il riempimento del volume di `G-space-exhausted`, che non è affidabile (§ *Limiti dichiarati*, punto 13).
