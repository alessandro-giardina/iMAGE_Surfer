# Spike 04 — Recupero dei lotti dopo un arresto

Banco del **cancello tecnico n°4** (US-004): interrompe un lotto di operazioni su file in ogni punto di un elenco enumerato, recupera in un nuovo processo e osserva sul disco quale dei cinque esiti dichiarati viene raggiunto, e se la compensazione riporta lo stato di partenza. Chiude **ADR-007**: l'esito misurato, **emendato** con un sesto esito e una definizione precisata di «compensato», è in [`RESULT.md`](RESULT.md).

- [`PROCEDURE.md`](PROCEDURE.md): prerequisiti, build, dimostrazione manuale di un punto (arresto, stato, recupero, perturbazione e decisione dell'utente), esecuzione della matrice completa e chiusura, scritti perché un altro sviluppatore possa ripeterli senza `sudo`.
- [`RESULT.md`](RESULT.md): l'esito scritto del cancello, con una riga per ciascuno dei 61 punti, le compensazioni, le classi di errore, i punti bloccati, le separazioni di immagine e sidecar, gli esiti non supportabili e l'esito su ADR-007. Ogni riga rimanda a una cella della misura versionata.
- [`measurements/`](measurements/): l'**unica** misura versionata, `crash-matrix-20261116T154019Z-0eefc599.json` (profilo `full`, 146 celle, 5 ripetizioni), copiata da `runs/`.
- `fixtures/`: il lotto di prova versionato. `batch.json` è scritto a mano; le cinque coppie in `folder/` e `MANIFEST.json`, con SHA-256 e dimensione di ogni file, sono generati una volta da `crashbench make-fixtures`. `crashbench verify-fixtures` fallisce, nominando il file, se una fixture diverge dal manifest.
- I dati generati (`.data/`: immagine disco, punto di montaggio, stato) e le esecuzioni di scarto (`runs/`) non sono versionati.

Struttura del pacchetto SwiftPM, senza dipendenze esterne, senza Xcode e senza dipendenze da `Spikes/01-scale-memory`:

| Target | Ruolo |
|---|---|
| `CrashKit` | Libreria del banco: percorsi, fixture e manifest, impronta dell'host; poi volume di lavoro, istantanea, log di intenti, passi, classificatori e matrice. |
| `crashbench` | Eseguibile, un sottocomando per azione (`make-fixtures`, `verify-fixtures`, …). |
| `CrashKitTests` | Suite Swift Testing dello strumento; dipende anche da `crashbench`, così `swift test` ricostruisce il binario usato dai test di integrazione. |

**Nome del sidecar.** La convenzione `<radice>.xmp` (per esempio `IMG_0001.jpg` con `IMG_0001.xmp`) è una scelta della **sola fixture**. La decisione sul nome del sidecar appartiene al cancello n°3, e nessun esito di questo cancello ne dipende.

Tutto il codice qui è **materiale di verifica usa-e-getta** e non anticipa la struttura dei pacchetti del prodotto.
