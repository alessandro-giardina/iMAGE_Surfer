import CrashKit
import Foundation

let usage = """
  uso: crashbench <sottocomando> [opzioni] [--data-dir <percorso>]

  Sottocomandi:
    make-fixtures [--force]   genera le cinque coppie immagine+sidecar e MANIFEST.json in
                              fixtures/; senza --force rifiuta di sovrascrivere
    verify-fixtures           confronta le fixture con MANIFEST.json: esce con 0 se coincidono,
                              con 1 nominando il primo file divergente
    setup                     crea l'immagine disco se manca, monta il volume di lavoro e
                              ripristina la cartella di prova; stampa punto di montaggio e UUID
    teardown                  espelle il volume di lavoro, se montato
    reset                     ripristina la cartella di prova dalle fixture e svuota Cestino del
                              volume, quarantena e state/; esige il volume montato
    snapshot --out <file>     scrive in JSON, con chiavi ordinate, l'istantanea della cartella di
                              prova e del Cestino del volume; esige il volume montato
    perturb <classe> --strategy resume|compensate
                              applica la perturbazione di una delle otto classi di errore al
                              bersaglio scelto dalla regola fissa, leggendo piano e log; stampa
                              PERTURBAZIONE <classe> bersaglio=<passo>|nessuno ambito=<…>
                              oppure PERTURBAZIONE <classe> NON-APPLICABILE motivo=<…>;
                              esige il volume montato
    unperturb                 rimuove la perturbazione applicata, anche da un altro processo, e
                              stampa RIMOZIONE <classe> bersaglio=<…> oppure RIMOZIONE nessuna;
                              idempotente
    list-points [--json]      stampa i 61 punti di interruzione derivati dal piano della fixture,
                              una riga per punto: id<TAB>fase<TAB>descrizione (con --json, un
                              array JSON); non richiede il volume
    run [--crash-at <id>]     ripristina la cartella di prova, salva state/pre-snapshot.json ed
                              esegue il lotto; nel punto scelto stampa ARRESTO <id>: <descrizione>
                              e si uccide con SIGKILL (stato 137 da shell). Un punto K* annulla il
                              lotto completato; D01 e D02 si arrestano a S03-b e lasciano il
                              secondo arresto in state/pending-second-crash.json. Senza arresto
                              stampa ESITO <kind>; esige il volume montato
    recover --strategy resume|compensate
                              recupera in questo processo il lotto del log: riconosce dal disco
                              lo stato di ogni file, riprende o compensa (una compensazione già
                              avviata nel log prevale sulla strategia) e stampa, una voce per
                              riga: RECUPERO, RECORD-TRONCATO, DIVERGENZA, PASSO, COPPIA,
                              SEPARAZIONI-ALL-AVVIO, SEPARAZIONI-RESIDUE, ESITO, TRACCIA. Esce
                              con 0 per qualunque esito, NON_SUPPORTABILE compreso. Consuma
                              state/pending-second-crash.json, se c'è, e si arresta al secondo
                              punto con la sua strategia; non esige il volume montato
    decide retry|abandon      registra la decisione dell'utente su un lotto bloccato: retry
                              ripete il recupero nella direzione del log, abandon non tocca i file
                              e riferisce dove è rimasto ognuno; esce con 2 se l'ultimo esito
                              del log non è bloccato
    status                    stampa RECORD-TRONCATO, DIVERGENZA, PASSO, COPPIA e
                              SEPARAZIONI-ALL-AVVIO dello stato riconosciuto dal disco, senza
                              agire e senza scrivere nel log, salvo la riparazione dichiarata di
                              un record troncato
    run-matrix [--profile full|smoke] [--repetitions N] [--out <file.json|directory>]
               [--only <modello>[,<modello>…]] [--shard k/n] [--measurement-id <id>]
                              esegue ogni cella della matrice in processi figli (run, perturb,
                              recover, decide, unperturb), con N ripetizioni (full: 5, smoke: 1),
                              e calcola gli oracoli sulle istantanee del volume; scrive il JSON di
                              misura in runs/<measurementId>.json (o in --out), una riga di
                              avanzamento per cella su stderr e il riepilogo su stdout. Esce con 0,
                              con 3 se un punto non è stato raggiunto, con 1 per un errore del
                              banco. --only (modelli fnmatch sull'ID di cella, ripetibile) e
                              --shard eseguono una parte, da unire con combine-matrix usando lo
                              stesso --measurement-id. Esegue setup se il volume non è montato e
                              lo lascia montato
    combine-matrix [--out <file.json|directory>] <parte.json>…
                              unisce le parti di una stessa misura in un unico JSON (predefinito:
                              runs/<measurementId>.json); rifiuta con 2 parti con measurementId,
                              host, digest del manifest, profilo o ripetizioni diversi, o che si
                              sovrappongono su una cella; esce con 4 se l'unione non copre
                              esattamente le celle del profilo

  Opzione globale:
    --data-dir <percorso>     directory dei dati del banco (immagine disco, mnt/, state/);
                              predefinita: Spikes/04-crash-recovery/.data

  Banco del cancello n°4 (US-004, ADR-007).
  """

func fail(_ message: String, status: Int32) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(status)
}

enum Subcommand: String, CaseIterable {
  case makeFixtures = "make-fixtures"
  case verifyFixtures = "verify-fixtures"
  case setup
  case teardown
  case reset
  case snapshot
  case perturb
  case unperturb
  case listPoints = "list-points"
  case run
  case recover
  case decide
  case status
  case runMatrix = "run-matrix"
  case combineMatrix = "combine-matrix"
}

/// Esce con 2, chiedendo `setup`, se il volume di lavoro non è montato.
func requireMounted(_ volume: WorkVolume, for subcommand: Subcommand) {
  guard volume.isMounted else {
    fail(
      "crashbench \(subcommand.rawValue): "
        + "\(WorkVolumeError.notMounted(mountPoint: volume.mountPoint.fileSystemPath))",
      status: 2)
  }
}

/// Esce con 2, chiedendo `setup`, se l'immagine del volume di lavoro non è mai stata creata. Il
/// recupero non esige il volume montato: un volume espulso è un errore sistemico da riferire.
func requireImage(_ volume: WorkVolume, for subcommand: Subcommand) {
  guard FileManager.default.fileExists(atPath: volume.imageURL.fileSystemPath) else {
    fail(
      "crashbench \(subcommand.rawValue): volume di lavoro mai creato "
        + "(\(volume.imageURL.fileSystemPath)): esegui prima `crashbench setup`",
      status: 2)
  }
}

/// I punti di interruzione del piano registrato nel log, per la descrizione della riga `ARRESTO`;
/// vuoto se il log non ha un piano.
func recoveryPoints(_ log: IntentLog) throws -> [CrashPoint] {
  try Perturbations.plan(in: log).map(CrashPoints.enumerate) ?? []
}

/// Dichiara su stderr il file di evidenza di un record troncato riparato.
func declareTornRepair(_ evidence: URL?) {
  guard let evidence else { return }
  FileHandle.standardError.write(
    Data("record troncato riparato: evidenza in \(evidence.fileSystemPath)\n".utf8))
}

/// Rifiuta ogni argomento residuo di un sottocomando che non ne accetta.
func rejectArguments(_ arguments: ArraySlice<String>, for subcommand: Subcommand) {
  if let argument = arguments.first {
    fail(
      "argomento sconosciuto per \(subcommand.rawValue): \(argument)\n\n\(usage)", status: 2)
  }
}

/// Una riga per punto, `id<TAB>fase<TAB>descrizione`, senza `\n` finale.
func pointListing(_ points: [CrashPoint]) -> String {
  points.map { "\($0.id)\t\($0.phase.rawValue)\t\($0.description)" }.joined(separator: "\n")
}

/// Il file del JSON di misura: `--out` se è un file; `<--out>/<nome>.json` se è una directory
/// esistente o termina con `/`; altrimenti `runs/<nome>.json`.
func measurementDestination(_ output: String?, name: String) -> URL {
  guard let output else {
    return CrashPaths.runs.appending(path: "\(name).json", directoryHint: .notDirectory)
  }
  var isDirectory: ObjCBool = false
  if output.hasSuffix("/")
    || (FileManager.default.fileExists(atPath: output, isDirectory: &isDirectory)
      && isDirectory.boolValue)
  {
    return URL(filePath: output, directoryHint: .isDirectory)
      .appending(path: "\(name).json", directoryHint: .notDirectory)
  }
  return URL(filePath: output, directoryHint: .notDirectory)
}

/// Nome predefinito del JSON di una misura: il `measurementId`, più il nome della parte se è
/// un'esecuzione parziale, così che le parti di una stessa misura non si sovrascrivano.
func measurementFileName(id: String, selection: MatrixSelection?) -> String {
  guard let selection else { return id }
  var tags: [String] = []
  if let only = selection.only {
    tags.append("sel-" + Fixtures.sha256Hex(of: Data(only.joined(separator: ",").utf8)).prefix(8))
  }
  if let shard = selection.shard {
    tags.append("parte-" + shard.replacingOccurrences(of: "/", with: "-di-"))
  }
  return ([id] + tags).joined(separator: "-")
}

/// Scrive la misura e stampa il riepilogo su stdout.
func writeMeasurement(_ result: MeasurementResult, to destination: URL) throws {
  try FileManager.default.createDirectory(
    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
  try result.jsonData().write(to: destination, options: .atomic)
  let summary = result.summary
  let outcomes = OutcomeKind.allCases.compactMap { kind in
    summary.outcomes[kind.rawValue].map { "\(kind.rawValue)=\($0)" }
  }
  print(
    "MISURA \(result.measurementId) profilo=\(result.profile.rawValue) "
      + "ripetizioni=\(result.repetitions)")
  print(
    "CELLE \(summary.cells) applicabili=\(summary.applicableCells) "
      + "non-applicabili=\(summary.cells - summary.applicableCells)")
  print("ESITI " + (outcomes.isEmpty ? "nessuno" : outcomes.joined(separator: " ")))
  print("NON_SUPPORTABILE \(summary.nonSupportableCells)")
  print("RICONOSCIMENTO_ERRATO \(summary.recognitionErrorCells)")
  print("PUNTO_NON_RAGGIUNTO \(summary.pointNotReachedCells)")
  print("NON_DETERMINISTICHE \(summary.nonDeterministicCells)")
  print("ISTANTANEE_NON_ASSESTATE \(summary.unsettledSnapshotCells)")
  print("ERRORI_DEL_BANCO \(summary.benchErrorCells)")
  print(
    "COPERTURA \(result.coverage.complete ? "completa" : "parziale") "
      + "\(result.coverage.presentCells)/\(result.coverage.expectedCells)")
  print(String(format: "DURATA %.1f s", result.durationSeconds))
  print("JSON \(destination.fileSystemPath)")
}

/// Stato di uscita di una misura: 1 per un errore del banco, 3 per un punto non raggiunto, 0
/// altrimenti. `NON_SUPPORTABILE` e `RICONOSCIMENTO_ERRATO` sono misure e non lo cambiano.
func measurementStatus(_ summary: MeasurementSummary) -> Int32 {
  if summary.benchErrorCells > 0 { return 1 }
  if summary.pointNotReachedCells > 0 { return 3 }
  return 0
}

// Uscita a righe anche verso una pipe: il processo padre legge l'output mentre arriva.
setvbuf(stdout, nil, _IOLBF, 0)

var arguments = CommandLine.arguments.dropFirst()

// Opzione globale `--data-dir <percorso>`, accettata in qualunque posizione.
var dataDirectory = CrashPaths.defaultDataDirectory
if let index = arguments.firstIndex(of: "--data-dir") {
  let valueIndex = arguments.index(after: index)
  guard valueIndex < arguments.endIndex else {
    fail("--data-dir richiede un percorso\n\n\(usage)", status: 2)
  }
  dataDirectory =
    URL(filePath: arguments[valueIndex], directoryHint: .isDirectory)
    .standardizedFileURL
  arguments.removeSubrange(index...valueIndex)
}
let volume = WorkVolume(dataDirectory: dataDirectory)

guard let first = arguments.popFirst() else { fail(usage, status: 2) }
if first == "--help" || first == "-h" {
  print(usage)
  exit(0)
}
guard let subcommand = Subcommand(rawValue: first) else {
  fail("sottocomando sconosciuto: \(first)\n\n\(usage)", status: 2)
}

switch subcommand {
case .makeFixtures:
  var force = false
  while let argument = arguments.popFirst() {
    guard argument == "--force" else {
      fail("argomento sconosciuto per make-fixtures: \(argument)\n\n\(usage)", status: 2)
    }
    force = true
  }
  do {
    let manifest = try makeFixtures(into: CrashPaths.fixtures, force: force)
    for entry in manifest.files {
      print("\(entry.sha256)  \(entry.size)  \(entry.path)")
    }
    print(
      "fixture scritte in \(CrashPaths.fixtures.path(percentEncoded: false)): "
        + "\(manifest.files.count) file nel manifest")
  } catch {
    fail("crashbench make-fixtures: \(error)", status: 1)
  }

case .verifyFixtures:
  rejectArguments(arguments, for: subcommand)
  do {
    let manifest = try verifyFixtures(at: CrashPaths.fixtures)
    print("fixture conformi al manifest: \(manifest.files.count) file")
  } catch {
    fail("crashbench verify-fixtures: \(error)", status: 1)
  }

case .setup:
  rejectArguments(arguments, for: subcommand)
  do {
    try volume.ensureImage()
    try volume.attach()
    try volume.resetBatchFolder()
    print("punto di montaggio: \(volume.mountPoint.fileSystemPath)")
    print("uuid del volume: \(try WorkVolume.volumeUUID(of: volume.mountPoint))")
  } catch {
    fail("crashbench setup: \(error)", status: 1)
  }

case .teardown:
  rejectArguments(arguments, for: subcommand)
  do {
    let wasMounted = volume.isMounted
    try volume.eject()
    print(
      wasMounted
        ? "volume espulso: \(volume.mountPoint.fileSystemPath)"
        : "volume già smontato: \(volume.mountPoint.fileSystemPath)")
  } catch {
    fail("crashbench teardown: \(error)", status: 1)
  }

case .reset:
  rejectArguments(arguments, for: subcommand)
  requireMounted(volume, for: subcommand)
  do {
    try volume.resetBatchFolder()
    print("cartella di prova ripristinata: \(volume.batchRoot.fileSystemPath)")
  } catch {
    fail("crashbench reset: \(error)", status: 1)
  }

case .snapshot:
  var output: URL?
  while let argument = arguments.popFirst() {
    guard argument == "--out", let path = arguments.popFirst() else {
      fail("argomento sconosciuto per snapshot: \(argument)\n\n\(usage)", status: 2)
    }
    output = URL(filePath: path, directoryHint: .notDirectory)
  }
  guard let output else { fail("snapshot richiede --out <file>\n\n\(usage)", status: 2) }
  requireMounted(volume, for: subcommand)
  do {
    let snapshot = try Snapshot.capture(volume: volume)
    try snapshot.jsonData().write(to: output, options: .atomic)
    print(
      "istantanea scritta: \(output.path(percentEncoded: false)) (\(snapshot.entries.count) voci)")
  } catch {
    fail("crashbench snapshot: \(error)", status: 1)
  }

case .perturb:
  var errorClass: ErrorClass?
  var strategy: RecoveryStrategy?
  let classes = ErrorClass.allCases.map(\.rawValue).joined(separator: ", ")
  while let argument = arguments.popFirst() {
    if argument == "--strategy" {
      guard let value = arguments.popFirst(), let parsed = RecoveryStrategy(rawValue: value) else {
        fail("perturb: --strategy richiede resume oppure compensate\n\n\(usage)", status: 2)
      }
      strategy = parsed
    } else if errorClass == nil, let parsed = ErrorClass(rawValue: argument) {
      errorClass = parsed
    } else {
      fail(
        "argomento sconosciuto per perturb: \(argument) (classi: \(classes))\n\n\(usage)",
        status: 2)
    }
  }
  guard let errorClass else {
    fail("perturb richiede una classe fra: \(classes)\n\n\(usage)", status: 2)
  }
  guard let strategy else {
    fail("perturb richiede --strategy resume|compensate\n\n\(usage)", status: 2)
  }
  requireMounted(volume, for: subcommand)
  do {
    let log = IntentLog(volume: volume)
    let record =
      if let plan = try Perturbations.plan(in: log) {
        try Perturbations.apply(
          errorClass, strategy: strategy, plan: plan, log: log, volume: volume)
      } else {
        PerturbationRecord.notApplicable(
          errorClass, strategy: strategy, reason: Perturbations.Reason.planNotInLog)
      }
    print(record.line)
  } catch {
    fail("crashbench perturb: \(error)", status: 1)
  }

case .unperturb:
  rejectArguments(arguments, for: subcommand)
  do {
    print(Perturbations.removalLine(try Perturbations.remove(volume: volume)))
  } catch {
    fail("crashbench unperturb: \(error)", status: 1)
  }

case .listPoints:
  var json = false
  while let argument = arguments.popFirst() {
    guard argument == "--json" else {
      fail("argomento sconosciuto per list-points: \(argument)\n\n\(usage)", status: 2)
    }
    json = true
  }
  do {
    let points = try CrashPoints.fixturePoints()
    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
      print(String(decoding: try encoder.encode(points), as: UTF8.self))
    } else {
      print(pointListing(points))
    }
  } catch {
    fail("crashbench list-points: \(error)", status: 1)
  }

case .run:
  var crashAt: String?
  while let argument = arguments.popFirst() {
    guard argument == "--crash-at", crashAt == nil, let value = arguments.popFirst() else {
      fail("argomento sconosciuto per run: \(argument)\n\n\(usage)", status: 2)
    }
    crashAt = value
  }
  // Il punto si valida sul piano della fixture prima di toccare il volume.
  let referencePoints: [CrashPoint]
  do {
    referencePoints = try CrashPoints.fixturePoints()
  } catch {
    fail("crashbench run: \(error)", status: 1)
  }
  if let crashAt, !referencePoints.contains(where: { $0.id == crashAt }) {
    fail(
      "punto di interruzione sconosciuto: \(crashAt)\n\npunti di interruzione:\n"
        + pointListing(referencePoints),
      status: 2)
  }
  requireMounted(volume, for: subcommand)
  do {
    try volume.resetBatchFolder()
    try Snapshot.capture(volume: volume).jsonData()
      .write(to: BatchExecutor.preSnapshotURL(in: volume), options: .atomic)
    let definition = try BatchDefinition.load(
      from: CrashPaths.fixtures.appending(
        path: Fixtures.batchFileName, directoryHint: .notDirectory))
    let plan = try BatchPlan.make(definition: definition, volume: volume)
    let points = CrashPoints.enumerate(plan)

    var target = crashAt
    var undoAfter = false
    if let crashAt, let composite = CrashPoints.composite(crashAt) {
      // Primo arresto ora; il secondo lo esegue il recupero, leggendo il file in attesa.
      target = composite.firstCrash
      try composite.writePending(in: volume)
      print(composite.line)
    } else if let crashAt, points.first(where: { $0.id == crashAt })?.phase == .compensazione {
      undoAfter = true
    }

    let result = try BatchExecutor.run(
      plan: plan, volume: volume, log: IntentLog(volume: volume),
      injector: CrashInjector(target: target, mode: .kill, points: points),
      undoAfter: undoAfter)
    print(result.line)
    for line in result.trace { print("TRACCIA \(line)") }
  } catch {
    fail("crashbench run: \(error)", status: 1)
  }
case .recover:
  var requested: RecoveryStrategy?
  while let argument = arguments.popFirst() {
    guard argument == "--strategy", requested == nil, let value = arguments.popFirst(),
      let parsed = RecoveryStrategy(rawValue: value)
    else {
      fail("recover: --strategy richiede resume oppure compensate\n\n\(usage)", status: 2)
    }
    requested = parsed
  }
  guard var strategy = requested else {
    fail("recover richiede --strategy resume|compensate\n\n\(usage)", status: 2)
  }
  requireImage(volume, for: subcommand)
  do {
    let log = IntentLog(volume: volume)
    // Secondo arresto di D01 e D02: il file si consuma e si rimuove prima di agire, così il
    // recupero successivo procede normalmente.
    var target: String?
    if let pending = try CompositeCrash.loadPending(in: volume) {
      try FileManager.default.removeItem(at: CompositeCrash.pendingURL(in: volume))
      target = pending.secondCrash
      strategy = pending.strategy
      print(pending.line)
    }
    let report = try Recovery.run(
      strategy: strategy, log: log, volume: volume,
      injector: CrashInjector(target: target, mode: .kill, points: try recoveryPoints(log)),
      output: { print($0) })
    declareTornRepair(report.tornEvidence)
  } catch {
    fail("crashbench recover: \(error)", status: 1)
  }

case .decide:
  guard let value = arguments.popFirst(), let decision = UserDecision(rawValue: value) else {
    fail("decide richiede retry oppure abandon\n\n\(usage)", status: 2)
  }
  rejectArguments(arguments, for: subcommand)
  requireImage(volume, for: subcommand)
  do {
    let log = IntentLog(volume: volume)
    let report = try Recovery.decide(
      decision, log: log, volume: volume,
      injector: CrashInjector(target: nil, mode: .kill, points: try recoveryPoints(log)),
      output: { print($0) })
    declareTornRepair(report.tornEvidence)
  } catch let error as RecoveryError {
    fail("crashbench decide: \(error)", status: 2)
  } catch {
    fail("crashbench decide: \(error)", status: 1)
  }

case .status:
  rejectArguments(arguments, for: subcommand)
  requireImage(volume, for: subcommand)
  do {
    let state = try Recovery.status(log: IntentLog(volume: volume), volume: volume)
    for line in state.statusLines { print(line) }
    declareTornRepair(state.tornEvidence)
  } catch {
    fail("crashbench status: \(error)", status: 1)
  }

case .runMatrix:
  var profile = MatrixProfile.full
  var repetitions: Int?
  var output: String?
  var patterns: [String] = []
  var shard: MatrixShard?
  var measurementId: String?
  while let argument = arguments.popFirst() {
    guard let value = arguments.popFirst() else {
      fail("run-matrix: \(argument) richiede un valore\n\n\(usage)", status: 2)
    }
    switch argument {
    case "--profile":
      guard let parsed = MatrixProfile(rawValue: value) else {
        fail("run-matrix: --profile richiede full oppure smoke\n\n\(usage)", status: 2)
      }
      profile = parsed
    case "--repetitions":
      guard let parsed = Int(value), parsed >= 1 else {
        fail("run-matrix: --repetitions richiede un intero positivo\n\n\(usage)", status: 2)
      }
      repetitions = parsed
    case "--out":
      output = value
    case "--only":
      patterns += value.split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespaces)
      }.filter { !$0.isEmpty }
    case "--shard":
      guard let parsed = MatrixShard(value) else {
        fail("run-matrix: --shard richiede k/n con 1 ≤ k ≤ n\n\n\(usage)", status: 2)
      }
      shard = parsed
    case "--measurement-id":
      guard MeasurementResult.isValidMeasurementId(value) else {
        fail(
          "run-matrix: --measurement-id richiede la forma "
            + "crash-matrix-<yyyyMMdd'T'HHmmss'Z'>-<8 esadecimali>\n\n\(usage)",
          status: 2)
      }
      measurementId = value
    default:
      fail("argomento sconosciuto per run-matrix: \(argument)\n\n\(usage)", status: 2)
    }
  }
  guard let executable = Bundle.main.executableURL else {
    fail("crashbench run-matrix: percorso dell'eseguibile non disponibile", status: 1)
  }
  let profileCells: [MatrixCellSpec]
  do {
    profileCells = Matrix.cells(points: try CrashPoints.fixturePoints(), profile: profile)
  } catch {
    fail("crashbench run-matrix: \(error)", status: 1)
  }
  let cells: [MatrixCellSpec]
  do {
    cells = try Matrix.select(profileCells, only: patterns, shard: shard)
  } catch {
    fail("crashbench run-matrix: \(error)", status: 2)
  }
  let selection =
    patterns.isEmpty && shard == nil
    ? nil : MatrixSelection(only: patterns.isEmpty ? nil : patterns, shard: shard?.description)
  let id = measurementId ?? MeasurementResult.newMeasurementId()
  let destination = measurementDestination(
    output, name: measurementFileName(id: id, selection: selection))
  do {
    let result = try MatrixRunner.run(
      MatrixConfiguration(
        executable: executable, volume: volume, profile: profile,
        repetitions: repetitions ?? profile.defaultRepetitions, cells: cells,
        selection: selection, measurementId: id),
      progress: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
    try writeMeasurement(result, to: destination)
    exit(measurementStatus(result.summary))
  } catch {
    fail("crashbench run-matrix: \(error)", status: 1)
  }

case .combineMatrix:
  var output: String?
  var inputs: [String] = []
  while let argument = arguments.popFirst() {
    if argument == "--out" {
      guard let value = arguments.popFirst() else {
        fail("combine-matrix: --out richiede un percorso\n\n\(usage)", status: 2)
      }
      output = value
    } else if argument.hasPrefix("--") {
      fail("argomento sconosciuto per combine-matrix: \(argument)\n\n\(usage)", status: 2)
    } else {
      inputs.append(argument)
    }
  }
  guard !inputs.isEmpty else {
    fail("combine-matrix richiede almeno una parte\n\n\(usage)", status: 2)
  }
  do {
    let parts = try inputs.map { path in
      let url = URL(filePath: path, directoryHint: .notDirectory)
      return (file: url.lastPathComponent, result: try MeasurementResult.load(from: url))
    }
    let canonical = Matrix.cells(
      points: try CrashPoints.fixturePoints(), profile: parts[0].result.profile
    )
    .map(\.id)
    let combined: MeasurementResult
    do {
      combined = try MeasurementResult.combine(parts, canonicalCells: canonical)
    } catch let error as MeasurementCombineError {
      fail("crashbench combine-matrix: \(error)", status: 2)
    }
    try writeMeasurement(
      combined, to: measurementDestination(output, name: combined.measurementId))
    exit(combined.coverage.complete ? measurementStatus(combined.summary) : 4)
  } catch {
    fail("crashbench combine-matrix: \(error)", status: 1)
  }
}
