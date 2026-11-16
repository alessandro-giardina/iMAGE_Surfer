# Spike 01 — Scala e memoria su 50.000 file

Banco di misura del **cancello tecnico n°1** (US-001): misura latenza e memoria di una cartella da 50.000 immagini su hardware dichiarato, deriva le stime di costo per elemento e l'ampiezza della banda di ritenzione, e chiude ADR-009 (con NFR-P1, NFR-P9, NFR-P10) come **confermato** o **emendato**.

- [`PROCEDURE.md`](PROCEDURE.md): prerequisiti, generazione del dataset ed esecuzione del banco, scritti perché un altro sviluppatore possa ripeterli.
- [`RESULT.md`](RESULT.md): l'esito scritto del cancello, in cui ogni cifra rimanda a un `measurementId` versionato sotto `measurements/`.
- `dataset.json`: la configurazione versionata del dataset. I file generati (`.data/`) e le esecuzioni di scarto (`runs/`) non sono versionati.

Struttura del pacchetto SwiftPM, senza dipendenze esterne e senza Xcode:

| Target | Ruolo |
|---|---|
| `BenchKit` | Libreria del kernel di misura: campionatore `phys_footprint`, statistica delle ripetizioni, impronta hardware, schema JSON, banchi. |
| `gen-dataset` | Generatore del dataset sintetico. |
| `bench` | Esecuzione delle misure, un sottocomando per misura. |
| `BenchKitTests` | Suite Swift Testing dello strumento di misura. |

Tutto il codice qui è **materiale di misura usa-e-getta** e non anticipa la struttura dei pacchetti del prodotto.
