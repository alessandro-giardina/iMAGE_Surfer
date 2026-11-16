// Matrice degli arresti: ogni cella eseguita in processi figli dello stesso eseguibile, con
// ripetizioni, e gli oracoli calcolati dal banco sulle istantanee del volume, mai dalla macchina
// sotto test.
//
// La matrice non esegue né `run` né `recover` nel proprio processo: lo fanno sempre i figli
// (`run`, `perturb`, `recover`, `decide`, `unperturb`). Nel proprio processo la matrice ripristina
// la cartella di prova, cattura le istantanee, rilegge il log di intenti e l'istantanea `pre`
// scritti dai figli, e rimonta il volume dopo un'espulsione.
//
// Adattamenti locali, che preservano la soluzione del piano:
// - **Istantanee assestate.** Il Cestino di sistema aggiorna `.Trashes/<uid>` in modo asincrono
//   (`.DS_Store` riscritto circa 0,2 s dopo uno spostamento nel Cestino; `UF_HIDDEN` e
//   `com.apple.FinderInfo` dopo la prima voce). Ogni istantanea della matrice è quindi catturata
//   con `Snapshot.captureSettled`; un'istantanea che non si assesta entro il limite è registrata
//   nella cella (`snapshotsNotSettled`), non nascosta.
// - **`pre` del figlio.** `run` ripristina da sé la cartella di prova e scrive, prima di agire,
//   `state/pre-snapshot.json` con `Snapshot.capture`: è quella l'istantanea `pre` degli oracoli,
//   perché il ripristino del figlio ricrea i file (inode, `birthtime` e `mtime` nuovi) e
//   un'istantanea presa prima non sarebbe confrontabile campo per campo. Il ripristino in-process
//   e un'istantanea assestata con il Cestino vuoto precedono il figlio come barriera di quiete, e
//   la matrice verifica che `pre` abbia gli stessi percorsi e digest di quella, e lo stesso
//   Cestino campo per campo. Il Cestino di sistema può riscrivere `.DS_Store` dopo che il
//   ripristino l'ha cancellato (osservato in 3 ripetizioni su circa 180): il ripristino si ripete,
//   e una ripetizione con `pre` diversa riparte da capo prima che la macchina agisca; entrambi i
//   fatti restano nelle note della cella, e un disaccordo che persiste è dichiarato `r<n>:pre`.
// - **Riscaldamento del Cestino.** Un volume nuovo non ha `.Trashes/<uid>`: la prima cella che lo
//   crea avrebbe scostamenti diversi dalle successive. Se manca, la matrice esegue prima un lotto
//   completo in un figlio e ripristina la cartella, così ogni ripetizione parte dallo stesso Cestino
//   vuoto, qualunque sia l'ordine o la selezione delle celle.
// - **Esecuzioni parziali.** `Matrix.select` (modelli `--only`, parte `--shard k/n`) e
//   `MeasurementResult.combine`: vedi `MeasurementResult.swift`.

import Darwin
import Foundation

// MARK: - Celle

/// Una cella della matrice: un punto di interruzione, una strategia di recupero e, per le celle di
/// perturbazione, la classe di errore applicata fra l'arresto e il recupero.
public struct MatrixCellSpec: Equatable, Sendable {
  public let point: CrashPoint
  public let strategy: RecoveryStrategy
  public let perturbation: ErrorClass?

  public init(point: CrashPoint, strategy: RecoveryStrategy, perturbation: ErrorClass? = nil) {
    self.point = point
    self.strategy = strategy
    self.perturbation = perturbation
  }

  /// `<punto>/<strategia>[/<classe>]`.
  public var id: String {
    ([point.id, strategy.rawValue] + (perturbation.map { [$0.rawValue] } ?? []))
      .joined(separator: "/")
  }

  /// Il doppio arresto, per `D01` e `D02`.
  public var composite: CompositeCrash? { CrashPoints.composite(point.id) }
}

/// Parte `k` di `n` di una selezione di celle.
public struct MatrixShard: Equatable, Sendable, CustomStringConvertible {
  /// Da 1.
  public let index: Int
  public let count: Int

  /// Legge `k/n`, con `1 ≤ k ≤ n`.
  public init?(_ text: String) {
    let parts = text.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2, let index = Int(parts[0]), let count = Int(parts[1]), count >= 1,
      (1...count).contains(index)
    else { return nil }
    self.index = index
    self.count = count
  }

  public var description: String { "\(index)/\(count)" }
}

/// Errori della matrice che non sono una misura.
public enum MatrixError: Error, Equatable, CustomStringConvertible, LocalizedError {
  /// Un modello di `--only` non seleziona nessuna cella del profilo.
  case patternMatchesNothing(String)
  /// La selezione è vuota.
  case emptySelection
  /// Un'operazione del banco fuori dalle celle è fallita: preparazione o pulizia.
  case benchFailure(String)

  public var description: String {
    switch self {
    case .patternMatchesNothing(let pattern):
      "il modello \(pattern) non seleziona nessuna cella del profilo"
    case .emptySelection:
      "la selezione non contiene celle"
    case .benchFailure(let description):
      "errore del banco: \(description)"
    }
  }

  public var errorDescription: String? { description }
}

/// Celle, selezione e oracoli della matrice.
public enum Matrix {
  /// I tre punti delle celle di perturbazione: niente eseguito, lotto a metà, tutto eseguito.
  public static let perturbationPoints = [
    CrashPoints.prepared, CrashPoints.point("S06", .acted), CrashPoints.point("S10", .recorded),
  ]

  /// I punti del profilo `smoke`, con le loro strategie.
  public static let smokePoints = [
    CrashPoints.planRecorded, CrashPoints.point("S03", .acted),
    CrashPoints.point("S07", .tempWritten), CrashPoints.point("S10", .recorded),
    CrashPoints.compensationPoint("S05", .intent), "D01",
  ]

  /// Le celle di perturbazione del profilo `smoke`.
  public static let smokePerturbationCells = [
    "S06-b/resume/\(ErrorClass.locked.rawValue)",
    "S06-b/resume/\(ErrorClass.volumeMissing.rawValue)",
  ]

  /// Strategie di un punto: `resume` e `compensate` per l'esecuzione, `compensate` per i punti `K*`
  /// (la direzione viene dal log), la strategia del doppio arresto per `D01` e `D02`.
  public static func strategies(for point: CrashPoint) -> [RecoveryStrategy] {
    switch point.phase {
    case .esecuzione: [.resume, .compensate]
    case .compensazione: [.compensate]
    case .doppio: CrashPoints.composite(point.id).map { [$0.strategy] } ?? []
    }
  }

  /// Le celle del profilo, in quest'ordine: ogni punto con le sue strategie, nell'ordine
  /// dell'elenco; poi le perturbazioni per punto (`X03-prepare`, `S06-b`, `S10-c`), strategia e
  /// classe (`ErrorClass.allCases`). Con la fixture: 98 + 48 celle per `full`, 10 + 2 per `smoke`.
  public static func cells(points: [CrashPoint], profile: MatrixProfile) -> [MatrixCellSpec] {
    var cells = points.flatMap { point in
      strategies(for: point).map { MatrixCellSpec(point: point, strategy: $0) }
    }
    for id in perturbationPoints {
      guard let point = points.first(where: { $0.id == id }) else { continue }
      for strategy in RecoveryStrategy.allCases {
        for errorClass in ErrorClass.allCases {
          cells.append(MatrixCellSpec(point: point, strategy: strategy, perturbation: errorClass))
        }
      }
    }
    switch profile {
    case .full:
      return cells
    case .smoke:
      return cells.filter { cell in
        cell.perturbation == nil
          ? smokePoints.contains(cell.point.id) : smokePerturbationCells.contains(cell.id)
      }
    }
  }

  /// Le celle selezionate, nell'ordine di `cells`.
  ///
  /// - Parameters:
  ///   - patterns: modelli `fnmatch` sull'intero ID di cella (`*` attraversa anche `/`), in OR;
  ///     vuoto per tutte. Un modello che non seleziona nulla è un errore, per non perdere celle
  ///     per un refuso.
  ///   - shard: la parte `k` di `n`, a rotazione: la cella di posizione `i` (da 0) della selezione
  ///     sta nella parte `i % n + 1`. La rotazione distribuisce fra le parti le celle costose.
  public static func select(
    _ cells: [MatrixCellSpec], only patterns: [String], shard: MatrixShard?
  ) throws -> [MatrixCellSpec] {
    var selected = cells
    if !patterns.isEmpty {
      for pattern in patterns where !cells.contains(where: { matches($0.id, pattern) }) {
        throw MatrixError.patternMatchesNothing(pattern)
      }
      selected = cells.filter { cell in patterns.contains { matches(cell.id, $0) } }
    }
    if let shard {
      selected = selected.enumerated()
        .filter { $0.offset % shard.count == shard.index - 1 }
        .map(\.element)
    }
    guard !selected.isEmpty else { throw MatrixError.emptySelection }
    return selected
  }

  static func matches(_ id: String, _ pattern: String) -> Bool {
    fnmatch(pattern, id, 0) == 0
  }

  // MARK: - Oracoli sull'istantanea

  /// Voce dell'istantanea di un percorso relativo a `lotto/`.
  static func batchKey(_ relativePath: String) -> String {
    "\(Snapshot.batchKey)/\(relativePath)"
  }

  /// `@cestino/.DS_Store`, creato e riscritto dal Cestino di sistema.
  static let trashDSStore = "\(Snapshot.trashKey)/.DS_Store"

  /// Voci di primo livello del Cestino che sono file con il digest dato.
  static func trashEntries(withDigest sha256: String, in snapshot: Snapshot) -> [String] {
    snapshot.entries.filter { key, entry in
      key.hasPrefix(Snapshot.trashKey + "/")
        && !key.dropFirst(Snapshot.trashKey.count + 1).contains("/")
        && entry.kind == .file && entry.sha256 == sha256
    }.keys.sorted()
  }

  /// Posizione del file di un passo nell'istantanea, con la regola del piano: dove si trova il file
  /// con il digest del piano. Si contano l'origine, la destinazione e, per un `trash`, ogni voce di
  /// primo livello del Cestino con il digest (il temporaneo di copia non conta): nessuna → `ass`,
  /// una → quella, più d'una → `amb`. Per una copia vale `dest` se la destinazione ha il digest.
  ///
  /// È l'oracolo del banco: non usa il riconoscitore né il log.
  public static func position(of step: PlannedStep, in snapshot: Snapshot) -> FilePosition {
    var positions: [FilePosition] = []
    if snapshot.entries[batchKey(step.source)]?.sha256 == step.sha256 {
      positions.append(.origine)
    }
    if let destination = step.destination,
      snapshot.entries[batchKey(destination)]?.sha256 == step.sha256
    {
      positions.append(.destinazione)
    }
    if step.kind == .trash {
      positions += trashEntries(withDigest: step.sha256, in: snapshot).map { _ in .cestino }
    }
    if step.kind == .copy, positions.contains(.destinazione) { return .destinazione }
    switch positions.count {
    case 0: return .assente
    case 1: return positions[0]
    default: return .ambigua
    }
  }

  /// Il passo dell'immagine (`Fixtures.pairExtensions[0]`) o del sidecar di un'operazione.
  static func member(_ plan: BatchPlan, opId: String, fileExtension: String) -> PlannedStep? {
    plan.steps.first {
      $0.opId == opId && URL(filePath: $0.source).pathExtension == fileExtension
    }
  }

  /// Posizioni di immagine e sidecar di ogni operazione nell'istantanea, in ordine di piano.
  public static func pairPositions(plan: BatchPlan, snapshot: Snapshot) -> [PairPositions] {
    var opIds: [String] = []
    for step in plan.steps where !opIds.contains(step.opId) { opIds.append(step.opId) }
    return opIds.compactMap { opId in
      guard
        let image = member(plan, opId: opId, fileExtension: Fixtures.pairExtensions[0]),
        let sidecar = member(plan, opId: opId, fileExtension: Fixtures.pairExtensions[1])
      else { return nil }
      return PairPositions(
        opId: opId, image: position(of: image, in: snapshot),
        sidecar: position(of: sidecar, in: snapshot))
    }
  }

  /// Le operazioni con immagine e sidecar in posizioni diverse nell'istantanea, in ordine di piano.
  public static func separations(plan: BatchPlan, snapshot: Snapshot) -> [String] {
    pairPositions(plan: plan, snapshot: snapshot).filter(\.isSeparated).map(\.opId)
  }

  /// Confronto fra le separazioni osservate e quelle riferite dal recupero.
  public static func detection(observed: [String], reported: [String]) -> SeparationDetection {
    let observedSet = Set(observed)
    let reportedSet = Set(reported)
    if !observedSet.isSubset(of: reportedSet) { return .nonRilevata }
    if !reportedSet.isSubset(of: observedSet) { return .falsaSegnalazione }
    return observedSet.isEmpty ? .nessuna : .rilevata
  }

  /// Oracolo della compensazione: `Snapshot.diff(pre, post)`, diviso fra gli `mtime` di directory e
  /// tutto il resto.
  public static func compensation(
    pre: Snapshot, post: Snapshot, attempted: Bool
  ) -> CompensationOracle {
    guard attempted else { return .notAttempted }
    let deviations = Snapshot.diff(pre, post)
    let files = deviations.filter { !$0.isDirectoryMtime }
    let directories = deviations.filter(\.isDirectoryMtime)
    return CompensationOracle(
      attempted: true, matchesPre: files.isEmpty && directories.isEmpty, fileDeviations: files,
      directoryMtimeDeviations: directories)
  }

  /// Differenze fra `post` e lo stato atteso del lotto completato, derivato dal piano e da `pre`:
  /// percorsi e digest dei file del lotto, digest dei file del Cestino, insieme delle directory.
  /// Vuoto se coincidono.
  ///
  /// - rinomina e spostamento: il file lascia l'origine e arriva nella destinazione;
  /// - copia: la destinazione si aggiunge, l'origine resta;
  /// - `trash`: il file lascia l'origine e arriva nel Cestino, confrontato per digest perché il
  ///   nome della voce lo sceglie il Cestino;
  /// - le cartelle del piano si aggiungono, e il Cestino se il piano ha un `trash`.
  ///
  /// `@cestino/.DS_Store` è escluso: lo scrive il Cestino di sistema, non il lotto.
  public static func completedMismatches(
    pre: Snapshot, post: Snapshot, plan: BatchPlan
  ) -> [String] {
    var expectedFiles = batchFiles(of: pre)
    var expectedTrash = trashDigests(of: pre)
    var expectedDirectories = directories(of: pre)
    expectedDirectories.formUnion(plan.directoriesToCreate.map(batchKey))
    var mismatches: [String] = []

    for step in plan.steps {
      let source = batchKey(step.source)
      switch step.kind {
      case .trash:
        expectedFiles[source] = nil
        expectedTrash.append(step.sha256)
        expectedDirectories.insert(Snapshot.trashKey)
      case .copy, .rename, .move:
        guard let destination = step.destination else {
          mismatches.append("\(step.id): passo senza destinazione")
          continue
        }
        if step.kind != .copy { expectedFiles[source] = nil }
        expectedFiles[batchKey(destination)] = step.sha256
      }
    }

    let actualFiles = batchFiles(of: post)
    for path in Set(expectedFiles.keys).union(actualFiles.keys).sorted()
    where expectedFiles[path] != actualFiles[path] {
      mismatches.append(
        "\(path): atteso \(expectedFiles[path] ?? "assente"), "
          + "trovato \(actualFiles[path] ?? "assente")")
    }
    let actualTrash = trashDigests(of: post)
    if expectedTrash.sorted() != actualTrash.sorted() {
      mismatches.append(
        "\(Snapshot.trashKey): digest attesi [\(expectedTrash.sorted().joined(separator: ", "))], "
          + "trovati [\(actualTrash.sorted().joined(separator: ", "))]")
    }
    let actualDirectories = directories(of: post)
    for path in expectedDirectories.symmetricDifference(actualDirectories).sorted() {
      mismatches.append(
        "\(path): directory "
          + (expectedDirectories.contains(path) ? "attesa e assente" : "inattesa"))
    }
    return mismatches
  }

  /// File del lotto: percorso → digest.
  private static func batchFiles(of snapshot: Snapshot) -> [String: String] {
    snapshot.entries.reduce(into: [:]) { files, item in
      if item.key.hasPrefix(Snapshot.batchKey + "/"), item.value.kind == .file,
        let digest = item.value.sha256
      {
        files[item.key] = digest
      }
    }
  }

  /// Digest dei file del Cestino, `.DS_Store` escluso.
  private static func trashDigests(of snapshot: Snapshot) -> [String] {
    snapshot.entries.compactMap { key, entry in
      key.hasPrefix(Snapshot.trashKey + "/") && key != trashDSStore && entry.kind == .file
        ? entry.sha256 : nil
    }
  }

  private static func directories(of snapshot: Snapshot) -> Set<String> {
    Set(snapshot.entries.filter { $0.value.kind == .directory }.keys)
  }

  /// Le affermazioni di posizione del recupero smentite dall'istantanea: una riga per file.
  ///
  /// Una posizione `amb` di un passo che finisce `sospeso` per `G-volume-missing` non è
  /// un'affermazione di posizione: il volume non era osservabile, e il recupero lo dichiara.
  static func recognitionErrors(
    _ output: RecoveryOutput, actual: [PairPositions], plan: BatchPlan
  ) -> [String] {
    var errors: [String] = []
    for claim in output.pairs {
      guard let truth = actual.first(where: { $0.opId == claim.opId }) else {
        errors.append("\(claim.opId): coppia riferita ma assente dal piano")
        continue
      }
      let members = [
        ("immagine", claim.image, truth.image, Fixtures.pairExtensions[0]),
        ("sidecar", claim.sidecar, truth.sidecar, Fixtures.pairExtensions[1]),
      ]
      for (name, claimed, observed, fileExtension) in members where claimed != observed.rawValue {
        if claimed == FilePosition.ambigua.rawValue,
          let step = member(plan, opId: claim.opId, fileExtension: fileExtension),
          let reported = output.steps[step.id],
          reported.final == StepState.sospeso(.volumeMissing).name,
          reported.errorClass == ErrorClass.volumeMissing.rawValue
        {
          continue
        }
        errors.append(
          "\(claim.opId) \(name): dichiarata \(claimed), istantanea \(observed.rawValue)")
      }
    }
    return errors
  }

  /// Vero se l'istantanea `pre` del figlio ha gli stessi percorsi, tipi e digest dell'istantanea di
  /// quiete presa prima del figlio, e lo stesso Cestino campo per campo: il ripristino del figlio
  /// ricrea soltanto la cartella di prova. Restituisce i percorsi che differiscono.
  static func preDifferences(quiet: Snapshot, pre: Snapshot) -> [String] {
    var paths: [String] = []
    for path in Set(quiet.entries.keys).union(pre.entries.keys).sorted() {
      let before = quiet.entries[path]
      let after = pre.entries[path]
      let isTrash = path == Snapshot.trashKey || path.hasPrefix(Snapshot.trashKey + "/")
      let same =
        isTrash
        ? before == after : before?.kind == after?.kind && before?.sha256 == after?.sha256
      if !same { paths.append(path) }
    }
    return paths
  }
}

// MARK: - Istantanea assestata

/// Istantanea catturata quando il disco ha smesso di cambiare.
public struct SettledSnapshot: Sendable {
  public let snapshot: Snapshot
  /// Falso se il disco cambiava ancora allo scadere del limite.
  public let settled: Bool
  /// Secondi fra l'inizio della cattura e l'ultimo cambiamento osservato; 0 se nessuno.
  public let lastChangeSeconds: Double
}

extension Snapshot {
  /// Cattura il volume finché `parameters.stableCaptures` catture consecutive, a
  /// `parameters.intervalSeconds` l'una dall'altra, coincidono con la precedente; allo scadere di
  /// `parameters.maxWaitSeconds` restituisce l'ultima cattura con `settled == false`.
  ///
  /// Una cattura che fallisce mentre il disco cambia (una voce scompare fra l'elenco e `lstat`)
  /// conta come un cambiamento; se fallisce anche l'ultima, l'errore si propaga.
  public static func captureSettled(
    volume: WorkVolume, parameters: SettleParameters = .standard
  ) throws -> SettledSnapshot {
    let start = Date()
    var current: Snapshot?
    var lastError: Error?
    var stable = 0
    var lastChange = 0.0

    while true {
      do {
        let next = try capture(volume: volume)
        if let current, next == current {
          stable += 1
        } else {
          if current != nil || lastError != nil { lastChange = Date().timeIntervalSince(start) }
          stable = 0
        }
        current = next
        lastError = nil
      } catch {
        lastError = error
        stable = 0
        lastChange = Date().timeIntervalSince(start)
      }
      if let current, stable >= parameters.stableCaptures {
        return SettledSnapshot(snapshot: current, settled: true, lastChangeSeconds: lastChange)
      }
      guard Date().timeIntervalSince(start) < parameters.maxWaitSeconds else {
        if let lastError { throw lastError }
        if let current {
          return SettledSnapshot(snapshot: current, settled: false, lastChangeSeconds: lastChange)
        }
        return SettledSnapshot(
          snapshot: try capture(volume: volume), settled: false, lastChangeSeconds: lastChange)
      }
      Thread.sleep(forTimeInterval: parameters.intervalSeconds)
    }
  }
}

// MARK: - Output del recupero

/// Una riga `COPPIA` del recupero.
struct ReportedPair: Equatable, Sendable {
  let opId: String
  let image: String
  let sidecar: String
}

/// L'output a formato fisso di `recover` e di `decide`, analizzato riga per riga.
struct RecoveryOutput: Equatable, Sendable {
  /// Da `RECUPERO strategia=<…> direzione=<…>`; assente per `decide abandon`.
  var direction: String?
  var recordTroncato: Bool?
  var divergences: [String] = []
  /// Gli ID delle righe `PASSO`, nell'ordine.
  var stepOrder: [String] = []
  var steps: [String: CellStep] = [:]
  var pairs: [ReportedPair] = []
  var separationsAtStart: [String] = []
  var separationsResidual: [String] = []
  var outcome: OutcomeKind
  var reason: String?
  var trace: [String] = []

  /// `ESITO <kind>[ motivo=<reason>]`.
  var outcomeLine: String {
    "ESITO \(outcome.rawValue)" + (reason.map { " motivo=\($0)" } ?? "")
  }

  /// Analizza le righe stampate; `nil` senza una riga `ESITO` valida. Le righe che non fanno parte
  /// del formato (`DECISIONE`, `DOPPIO-ARRESTO`, …) si ignorano.
  static func parse(_ lines: [String]) -> RecoveryOutput? {
    var direction: String?
    var recordTroncato: Bool?
    var divergences: [String] = []
    var stepOrder: [String] = []
    var steps: [String: CellStep] = [:]
    var pairs: [ReportedPair] = []
    var atStart: [String] = []
    var residual: [String] = []
    var outcome: (kind: OutcomeKind, reason: String?)?
    var trace: [String] = []

    for line in lines {
      let head = line.prefix { $0 != " " }
      let rest = String(line.dropFirst(head.count).drop { $0 == " " })
      let tokens = rest.split(separator: " ").map(String.init)
      switch head {
      case "RECUPERO":
        direction = value("direzione", in: tokens)
      case "RECORD-TRONCATO":
        recordTroncato = rest == "si"
      case "DIVERGENZA":
        divergences.append(rest)
      case "PASSO":
        guard tokens.count >= 4, tokens[2] == "->" else { return nil }
        stepOrder.append(tokens[0])
        steps[tokens[0]] = CellStep(
          start: tokens[1], final: tokens[3], errorClass: value("classe", in: tokens),
          errorScope: value("ambito", in: tokens))
      case "COPPIA":
        guard let opId = tokens.first, let image = value("immagine", in: tokens),
          let sidecar = value("sidecar", in: tokens)
        else { return nil }
        pairs.append(ReportedPair(opId: opId, image: image, sidecar: sidecar))
      case "SEPARAZIONI-ALL-AVVIO":
        atStart = list(rest)
      case "SEPARAZIONI-RESIDUE":
        residual = list(rest)
      case "ESITO":
        guard let first = tokens.first, let kind = OutcomeKind(rawValue: first) else { return nil }
        outcome = (kind, value("motivo", in: tokens))
      case "TRACCIA":
        trace.append(rest)
      default:
        continue
      }
    }
    guard let outcome else { return nil }
    return RecoveryOutput(
      direction: direction, recordTroncato: recordTroncato, divergences: divergences,
      stepOrder: stepOrder, steps: steps, pairs: pairs, separationsAtStart: atStart,
      separationsResidual: residual, outcome: outcome.kind, reason: outcome.reason, trace: trace)
  }

  /// Il valore di `<nome>=<valore>` fra i token.
  static func value(_ name: String, in tokens: [String]) -> String? {
    tokens.first { $0.hasPrefix(name + "=") }.map { String($0.dropFirst(name.count + 1)) }
  }

  /// `OP2,OP5` → `["OP2", "OP5"]`; `nessuna` → `[]`.
  static func list(_ text: String) -> [String] {
    text == "nessuna" || text.isEmpty
      ? [] : text.split(separator: ",").map(String.init)
  }

  /// La classe del primo passo, in ordine, che ne riporta una.
  var firstStepClass: (errorClass: String, scope: String?)? {
    for id in stepOrder {
      if let step = steps[id], let errorClass = step.errorClass {
        return (errorClass, step.errorScope)
      }
    }
    return nil
  }
}

// MARK: - Processi figli

/// Un processo figlio concluso.
struct ChildResult {
  let command: String
  let reason: Process.TerminationReason
  let status: Int32
  let stdout: String
  let stderr: String
  let timedOut: Bool

  var lines: [String] {
    stdout.split(separator: "\n").map(String.init)
  }

  var exitedWithZero: Bool { !timedOut && reason == .exit && status == 0 }

  /// Vero se il figlio è morto per `SIGKILL` dopo aver stampato `ARRESTO <punto>:`.
  func killed(at point: String) -> Bool {
    !timedOut && reason == .uncaughtSignal && status == SIGKILL
      && lines.contains { $0.hasPrefix("ARRESTO \(point):") }
  }

  /// `<comando>: stato 1 | segnale 6 | tempo scaduto; stdout: …; stderr: …`, su una riga.
  var failureDescription: String {
    let termination =
      timedOut ? "tempo scaduto" : reason == .exit ? "stato \(status)" : "segnale \(status)"
    func flat(_ text: String) -> String {
      text.split(separator: "\n").joined(separator: " | ")
    }
    return "\(command): \(termination); stdout: \(flat(stdout)); stderr: \(flat(stderr))"
  }
}

/// Lancia `crashbench` in un processo figlio con la directory dati della matrice.
struct ChildLauncher {
  let executable: URL
  let dataDirectory: URL
  let timeout: TimeInterval

  /// Esegue il figlio e attende che termini; allo scadere di `timeout` lo uccide con `SIGKILL` e
  /// lo dichiara `timedOut`. Le uscite vanno su file temporanei, così nessun pipe pieno può
  /// bloccare il figlio.
  func run(_ arguments: [String]) throws -> ChildResult {
    let fileManager = FileManager.default
    let scratch = fileManager.temporaryDirectory.appending(
      path: "crashbench-matrice-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: scratch) }
    let outURL = scratch.appending(path: "stdout", directoryHint: .notDirectory)
    let errURL = scratch.appending(path: "stderr", directoryHint: .notDirectory)
    fileManager.createFile(atPath: outURL.fileSystemPath, contents: nil)
    fileManager.createFile(atPath: errURL.fileSystemPath, contents: nil)
    let outHandle = try FileHandle(forWritingTo: outURL)
    defer { try? outHandle.close() }
    let errHandle = try FileHandle(forWritingTo: errURL)
    defer { try? errHandle.close() }

    let process = Process()
    process.executableURL = executable
    process.arguments = arguments + ["--data-dir", dataDirectory.fileSystemPath]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = outHandle
    process.standardError = errHandle
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    var timedOut = false
    if finished.wait(timeout: .now() + timeout) == .timedOut {
      timedOut = true
      kill(process.processIdentifier, SIGKILL)
      finished.wait()
    }
    process.waitUntilExit()

    return ChildResult(
      command: "crashbench " + arguments.joined(separator: " "),
      reason: process.terminationReason, status: process.terminationStatus,
      stdout: String(decoding: try Data(contentsOf: outURL), as: UTF8.self),
      stderr: String(decoding: try Data(contentsOf: errURL), as: UTF8.self), timedOut: timedOut)
  }
}

// MARK: - Esecuzione

/// Configurazione di un'esecuzione della matrice.
public struct MatrixConfiguration: Sendable {
  /// L'eseguibile dei figli: `Bundle.main.executableURL` di `crashbench`.
  public var executable: URL
  public var volume: WorkVolume
  public var profile: MatrixProfile
  public var repetitions: Int
  /// Le celle da eseguire, nell'ordine.
  public var cells: [MatrixCellSpec]
  /// La selezione da cui vengono le celle; `nil` per l'intero profilo.
  public var selection: MatrixSelection?
  public var measurementId: String
  public var settle: SettleParameters
  /// Tempo massimo di un figlio.
  public var childTimeout: TimeInterval

  public init(
    executable: URL, volume: WorkVolume, profile: MatrixProfile, repetitions: Int,
    cells: [MatrixCellSpec], selection: MatrixSelection?, measurementId: String,
    settle: SettleParameters = .standard, childTimeout: TimeInterval = 180
  ) {
    self.executable = executable
    self.volume = volume
    self.profile = profile
    self.repetitions = repetitions
    self.cells = cells
    self.selection = selection
    self.measurementId = measurementId
    self.settle = settle
    self.childTimeout = childTimeout
  }
}

/// Esecuzione della matrice.
public enum MatrixRunner {
  /// Esegue le celle della configurazione e restituisce la misura.
  ///
  /// Prima di iniziare monta il volume se non lo è (come `setup`), rimuove una perturbazione
  /// rimasta e, se il Cestino del volume non esiste ancora, lo crea con un lotto completo in un
  /// figlio. Alla fine lascia il volume montato, così l'esecuzione resta ispezionabile.
  ///
  /// - Parameter progress: riceve una riga per cella, e le operazioni preliminari.
  /// - Throws: `MatrixError.benchFailure` se la preparazione o la pulizia fra due ripetizioni
  ///   fallisce; gli errori del volume di lavoro.
  public static func run(
    _ configuration: MatrixConfiguration, progress: (String) -> Void
  ) throws -> MeasurementResult {
    let started = Date()
    let session = try MatrixSession(configuration)
    let preparation = try session.prepare()
    preparation.forEach(progress)

    var cells: [MeasurementCell] = []
    for (index, spec) in configuration.cells.enumerated() {
      let cell = try session.measure(spec)
      cells.append(cell)
      progress(
        "[\(index + 1)/\(configuration.cells.count)] \(cell.cellId): \(progressText(cell))")
    }

    let points = try CrashPoints.fixturePoints()
    return MeasurementResult(
      measurementId: configuration.measurementId,
      spike: MeasurementResult.spikeName,
      host: .current(),
      volume: .workVolume,
      fixtureManifestSha256: try MeasurementResult.fixtureManifestDigest(),
      profile: configuration.profile,
      repetitions: configuration.repetitions,
      startedAt: MeasurementResult.timestamp(started),
      durationSeconds: Date().timeIntervalSince(started),
      points: points,
      settleParameters: configuration.settle,
      selection: configuration.selection,
      preparation: preparation,
      parts: nil,
      coverage: .of(
        present: cells.map(\.cellId),
        expected: Matrix.cells(points: points, profile: configuration.profile).map(\.id)),
      summary: .of(cells),
      cells: cells)
  }

  /// `completato=5 (12.3 s) [nonDeterministica]`, oppure `non applicabile: <motivo>`.
  static func progressText(_ cell: MeasurementCell) -> String {
    let outcomes =
      cell.applicable
      ? (cell.outcomes.isEmpty
        ? "nessun esito"
        : cell.outcomes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
          .joined(separator: " "))
      : "non applicabile: \(cell.notApplicableReason ?? "?")"
    let marks =
      cell.marks + (cell.benchErrors.isEmpty ? [] : ["errori del banco"])
      + (cell.snapshotsNotSettled.isEmpty ? [] : ["istantanee non assestate"])
    return outcomes + String(format: " (%.1f s)", cell.durationSeconds)
      + (marks.isEmpty ? "" : " [\(marks.joined(separator: ", "))]")
  }
}

/// Una ripetizione di una cella, o il ramo `retry` dopo un `bloccato`.
struct Repetition {
  enum Mode: Equatable {
    case measure
    /// Ripetizione nuova dopo un `bloccato`: passi 1-5, `unperturb`, `decide retry`.
    case retryBranch
  }

  let index: Int
  let mode: Mode
  var pointReached = true
  var applicable = true
  var notApplicableReason: String?
  var target: String?
  /// Il recupero che riferisce l'esito della cella.
  var recovery: RecoveryOutput?
  /// `decide abandon` (misura) oppure `decide retry` (ramo `retry`).
  var decision: RecoveryOutput?
  var separationsAtCrash: [String] = []
  var separationsBeforePerturbation: [String]?
  var separationsAtFirstCrash: [String]?
  var pairs: [PairPositions] = []
  var compensation = CompensationOracle.notAttempted
  var resumeMatchesExpected: Bool?
  var resumeMismatches: [String] = []
  var recognitionErrors: [String] = []
  var failures: [ObservedFailure] = []
  var notes: [String] = []
  var unsettled: [String] = []
  var benchErrors: [String] = []
  var settle = SettleStatistics(captures: 0, changed: 0, maxLastChangeSeconds: 0)

  init(index: Int, mode: Mode) {
    self.index = index
    self.mode = mode
  }

  /// `r3`, oppure `r3-retry`.
  var tag: String { mode == .measure ? "r\(index)" : "r\(index)-retry" }

  /// Vera se il punto è stato raggiunto e nessun figlio è uscito in modo inatteso.
  var isValid: Bool { pointReached && benchErrors.isEmpty }

  mutating func pointNotReached(_ child: ChildResult) {
    pointReached = false
    notes.append("\(tag): PUNTO_NON_RAGGIUNTO, \(child.failureDescription)")
  }

  mutating func benchError(_ child: ChildResult) {
    benchErrors.append("\(tag): \(child.failureDescription)")
  }

  /// La classe adottata e il primo fallimento classificato (o, in mancanza, il primo).
  var primaryFailure: ObservedFailure? {
    failures.first { $0.errorClass != nil } ?? failures.first
  }

  /// Valori degli oracoli confrontati fra le ripetizioni, nell'ordine.
  var signature: [(name: String, value: String)] {
    func render(_ list: [String]?) -> String {
      list.map { $0.isEmpty ? "nessuna" : $0.joined(separator: ",") } ?? "-"
    }
    let steps = recovery.map { output in
      output.stepOrder.map { id in
        let step = output.steps[id]
        return "\(id)=\(step?.final ?? "?")" + (step?.errorClass.map { "(\($0))" } ?? "")
      }.joined(separator: " ")
    }
    let compensationValue =
      compensation.attempted
      ? "coincide=\(compensation.matchesPre == true ? "si" : "no") file=["
        + compensation.fileDeviations.map(\.key).joined(separator: ",") + "] mtime=["
        + compensation.directoryMtimeDeviations.map(\.key).joined(separator: ",") + "]"
      : "non tentata"
    let failure = primaryFailure.map {
      "\($0.errorClass ?? "-") \($0.syscall) errno=\($0.errno.map(String.init) ?? "-") "
        + "cocoa=\($0.cocoa ?? "-")"
    }
    return [
      ("applicabile", applicable ? "si" : "no (\(notApplicableReason ?? "?"))"),
      ("bersaglio", target ?? "nessuno"),
      ("esito", recovery?.outcomeLine ?? "-"),
      ("direzione", recovery?.direction ?? "-"),
      ("passi", steps ?? "-"),
      (
        "coppie",
        pairs.map { "\($0.opId)=\($0.image.rawValue)/\($0.sidecar.rawValue)" }
          .joined(separator: " ")
      ),
      ("separazioniAllArresto", render(separationsAtCrash)),
      ("separazioniPrimaDellaPerturbazione", render(separationsBeforePerturbation)),
      ("separazioniAlPrimoArresto", render(separationsAtFirstCrash)),
      ("separazioniRiferite", render(recovery?.separationsAtStart)),
      ("separazioniResidue", render(recovery?.separationsResidual)),
      ("compensazione", compensationValue),
      ("ripresaCoincide", resumeMatchesExpected.map { $0 ? "si" : "no" } ?? "-"),
      ("riconoscimento", recognitionErrors.joined(separator: "; ")),
      ("fallimento", failure ?? "-"),
      ("decisione", decision?.outcomeLine ?? "-"),
    ]
  }
}

/// Lo stato condiviso di un'esecuzione: configurazione, figli e piano di riferimento.
struct MatrixSession {
  let configuration: MatrixConfiguration
  let launcher: ChildLauncher
  /// Il piano di riferimento della fixture, l'oracolo delle posizioni: percorsi e digest dei passi
  /// dalle fixture versionate, non dal log della macchina.
  let plan: BatchPlan

  var volume: WorkVolume { configuration.volume }

  init(_ configuration: MatrixConfiguration) throws {
    self.configuration = configuration
    launcher = ChildLauncher(
      executable: configuration.executable, dataDirectory: configuration.volume.dataDirectory,
      timeout: configuration.childTimeout)
    plan = try CrashPoints.referencePlan(
      definition: BatchDefinition.load(
        from: CrashPaths.fixtures.appending(
          path: Fixtures.batchFileName, directoryHint: .notDirectory)))
  }

  // MARK: Preparazione

  /// Monta il volume se serve, rimuove una perturbazione rimasta e riscalda il Cestino del volume.
  /// Restituisce ciò che ha fatto, una riga per operazione.
  func prepare() throws -> [String] {
    var notes: [String] = []
    if !volume.isMounted {
      try volume.ensureImage()
      try volume.attach()
      try volume.resetBatchFolder()
      notes.append("setup: volume di lavoro montato su \(volume.mountPoint.fileSystemPath)")
    }

    let removal = try launcher.run(["unperturb"])
    guard removal.exitedWithZero else {
      throw MatrixError.benchFailure(removal.failureDescription)
    }
    if let line = removal.lines.first, line != Perturbations.removalLine(nil) {
      notes.append("perturbazione rimasta da un'esecuzione precedente rimossa: \(line)")
    }
    if !volume.isMounted { try volume.attach() }

    if !FileManager.default.fileExists(atPath: volume.trashDirectory.fileSystemPath) {
      let warmUp = try launcher.run(["run"])
      guard warmUp.exitedWithZero, warmUp.lines.contains("ESITO completato") else {
        throw MatrixError.benchFailure("riscaldamento del Cestino: \(warmUp.failureDescription)")
      }
      try volume.resetBatchFolder()
      _ = try Snapshot.captureSettled(volume: volume, parameters: configuration.settle)
      notes.append(
        "riscaldamento del Cestino: lotto completo in un figlio (ESITO completato), poi ripristino;"
          + " \(volume.trashDirectory.fileSystemPath) esiste ed è vuoto")
    }
    return notes
  }

  // MARK: Cella

  /// Esegue tutte le ripetizioni di una cella, con i rami `abandon` e `retry` dopo ogni
  /// `bloccato`, e riassume la cella.
  func measure(_ spec: MatrixCellSpec) throws -> MeasurementCell {
    let started = Date()
    var repetitions: [Repetition] = []
    var retries: [Repetition] = []
    for index in 1...configuration.repetitions {
      let repetition = try execute(spec, index: index, mode: .measure)
      repetitions.append(repetition)
      if repetition.recovery?.outcome == .bloccato {
        retries.append(try execute(spec, index: index, mode: .retryBranch))
      }
    }
    return summarize(
      spec, repetitions: repetitions, retries: retries,
      duration: Date().timeIntervalSince(started))
  }

  /// Una ripetizione: i passi della cella, poi sempre `unperturb` (passo 8). Un errore del banco
  /// dentro i passi si registra nella ripetizione; un errore della pulizia interrompe la matrice.
  func execute(_ spec: MatrixCellSpec, index: Int, mode: Repetition.Mode) throws -> Repetition {
    var repetition = Repetition(index: index, mode: mode)
    do {
      try perform(spec, &repetition)
    } catch {
      repetition.benchErrors.append("\(repetition.tag): \(error)")
    }

    let removal = try launcher.run(["unperturb"])
    guard removal.exitedWithZero else {
      throw MatrixError.benchFailure(removal.failureDescription)
    }
    if !volume.isMounted { try volume.attach() }
    return repetition
  }

  /// I passi 1-7 di una ripetizione. Ritorna in anticipo quando il punto non è raggiunto, la
  /// perturbazione non è applicabile o un figlio esce in modo inatteso.
  func perform(_ spec: MatrixCellSpec, _ repetition: inout Repetition) throws {
    let strategy = spec.strategy.rawValue
    let composite = spec.composite

    // 1-2. Ripristino e quiete in-process, poi arresto nel figlio, verificato: segnale 9 e
    // `ARRESTO <punto>`. Se il Cestino di sistema cambia fra la quiete e la `pre` del figlio,
    // la ripetizione riparte da capo prima che la macchina agisca: è un artefatto del sistema,
    // non della macchina. Se persiste, la `pre` si dichiara non assestata.
    var pre = Snapshot()
    for attempt in 1...Self.preAttempts {
      let quiet = try quietState(&repetition)
      let run = try launcher.run(["run", "--crash-at", spec.point.id])
      guard run.killed(at: composite?.firstCrash ?? spec.point.id) else {
        repetition.pointNotReached(run)
        return
      }
      pre = try Snapshot.load(from: BatchExecutor.preSnapshotURL(in: volume))
      let differing = Matrix.preDifferences(quiet: quiet, pre: pre)
      guard !differing.isEmpty else { break }
      let paths = differing.prefix(5).joined(separator: ", ")
      if attempt < Self.preAttempts {
        repetition.notes.append(
          "\(repetition.tag): pre del figlio diversa dall'istantanea di quiete in \(paths): "
            + "ripetizione ripresa da capo")
      } else {
        repetition.unsettled.append("\(repetition.tag):pre")
        repetition.notes.append(
          "\(repetition.tag): pre del figlio diversa dall'istantanea di quiete in \(paths)")
      }
    }

    // 3. Istantanea all'arresto e separazioni osservate dal banco.
    var start = try capture("arresto", &repetition)
    repetition.separationsAtCrash = Matrix.separations(plan: plan, snapshot: start)

    // 4. Perturbazione, nel figlio.
    if let errorClass = spec.perturbation {
      let perturb = try launcher.run(["perturb", errorClass.rawValue, "--strategy", strategy])
      let tokens = perturb.lines.first { $0.hasPrefix("PERTURBAZIONE ") }?
        .split(separator: " ").map(String.init)
      guard perturb.exitedWithZero, let tokens else {
        repetition.benchError(perturb)
        return
      }
      if tokens.contains("NON-APPLICABILE") {
        repetition.applicable = false
        repetition.notApplicableReason = RecoveryOutput.value("motivo", in: tokens) ?? "?"
        return
      }
      repetition.target = RecoveryOutput.value("bersaglio", in: tokens).flatMap {
        $0 == "nessuno" ? nil : $0
      }
      start = try capture("perturbazione", &repetition)
      repetition.separationsBeforePerturbation = repetition.separationsAtCrash
      repetition.separationsAtCrash = Matrix.separations(plan: plan, snapshot: start)
    }

    // 5. Recupero nel figlio; per D01 e D02 il primo muore al secondo punto.
    if let composite {
      let first = try launcher.run(["recover", "--strategy", strategy])
      guard first.killed(at: composite.secondCrash) else {
        repetition.pointNotReached(first)
        return
      }
      start = try capture("secondo-arresto", &repetition)
      repetition.separationsAtFirstCrash = repetition.separationsAtCrash
      repetition.separationsAtCrash = Matrix.separations(plan: plan, snapshot: start)
    }
    let recover = try launcher.run(["recover", "--strategy", strategy])
    guard recover.exitedWithZero, let output = RecoveryOutput.parse(recover.lines) else {
      repetition.benchError(recover)
      return
    }
    repetition.recovery = output
    repetition.failures = try observedFailures()

    if repetition.mode == .retryBranch {
      try retry(after: output, &repetition)
      return
    }

    // 6. Istantanea dopo il recupero, con il volume montato.
    if !volume.isMounted { try volume.attach() }
    let post = try capture("dopo", &repetition)
    repetition.pairs = Matrix.pairPositions(plan: plan, snapshot: post)
    repetition.compensation = Matrix.compensation(
      pre: pre, post: post, attempted: output.direction == RecoveryDirection.compensate.rawValue)
    if output.outcome == .completato {
      repetition.resumeMismatches = Matrix.completedMismatches(pre: pre, post: post, plan: plan)
      repetition.resumeMatchesExpected = repetition.resumeMismatches.isEmpty
    }
    repetition.recognitionErrors = Matrix.recognitionErrors(
      output, actual: repetition.pairs, plan: plan)

    // 7. Ramo `abandon` su questa ripetizione; il ramo `retry` è una ripetizione nuova.
    if output.outcome == .bloccato {
      let abandon = try launcher.run(["decide", "abandon"])
      guard abandon.exitedWithZero, let decided = RecoveryOutput.parse(abandon.lines) else {
        repetition.benchError(abandon)
        return
      }
      repetition.decision = decided
      repetition.recognitionErrors += Matrix.recognitionErrors(
        decided, actual: repetition.pairs, plan: plan
      ).map { "abandon: \($0)" }
    }
  }

  /// Ramo `retry`: se il recupero è `bloccato`, `unperturb` e poi `decide retry`, nei figli.
  func retry(after output: RecoveryOutput, _ repetition: inout Repetition) throws {
    guard output.outcome == .bloccato else {
      repetition.notes.append(
        "\(repetition.tag): il recupero ha dato \(output.outcomeLine) e non bloccato: "
          + "decide retry non eseguito")
      return
    }
    let removal = try launcher.run(["unperturb"])
    guard removal.exitedWithZero else {
      repetition.benchError(removal)
      return
    }
    let retry = try launcher.run(["decide", "retry"])
    guard retry.exitedWithZero, let decided = RecoveryOutput.parse(retry.lines) else {
      repetition.benchError(retry)
      return
    }
    repetition.decision = decided
  }

  /// Tentativi di una ripetizione la cui `pre` differisce dall'istantanea di quiete.
  static let preAttempts = 3
  /// Ripristini prima di accettare un Cestino non vuoto nell'istantanea di quiete.
  static let quietAttempts = 3

  /// Ripristino in-process e istantanea di quiete assestata. Il ripristino svuota il Cestino del
  /// volume; se il Cestino di sistema lo riscrive durante l'attesa (`.DS_Store`), il ripristino si
  /// ripete, così che ogni ripetizione parta dallo stesso Cestino vuoto.
  func quietState(_ repetition: inout Repetition) throws -> Snapshot {
    var attempt = 1
    while true {
      try volume.resetBatchFolder()
      let quiet = try capture("quiete", &repetition)
      let leftovers = quiet.entries.keys.filter { $0.hasPrefix(Snapshot.trashKey + "/") }.sorted()
      if leftovers.isEmpty || attempt == Self.quietAttempts {
        if !leftovers.isEmpty {
          repetition.notes.append(
            "\(repetition.tag): Cestino non vuoto dopo \(attempt) ripristini: "
              + leftovers.joined(separator: ", "))
        }
        return quiet
      }
      repetition.notes.append(
        "\(repetition.tag): Cestino riscritto dal sistema dopo il ripristino ("
          + leftovers.joined(separator: ", ") + "): ripristino ripetuto")
      attempt += 1
    }
  }

  /// Istantanea assestata, con le statistiche e l'eventuale mancato assestamento registrati nella
  /// ripetizione.
  func capture(_ name: String, _ repetition: inout Repetition) throws -> Snapshot {
    let result = try Snapshot.captureSettled(volume: volume, parameters: configuration.settle)
    repetition.settle.captures += 1
    if result.lastChangeSeconds > 0 {
      repetition.settle.changed += 1
      repetition.settle.maxLastChangeSeconds = max(
        repetition.settle.maxLastChangeSeconds, result.lastChangeSeconds)
    }
    if !result.settled { repetition.unsettled.append("\(repetition.tag):\(name)") }
    return result.snapshot
  }

  /// I record `step-failed` scritti dai recuperi, letti dal log di intenti senza ripararlo.
  func observedFailures() throws -> [ObservedFailure] {
    let records = try IntentLog(volume: volume).read().records
    guard let first = records.firstIndex(where: { $0.kind == .recovery }) else { return [] }
    return records[first...].compactMap { record in
      guard
        case .stepFailed(
          let stepId, let direction, let syscall, let code, let cocoa, let errorClass,
          let scope) = record
      else { return nil }
      return ObservedFailure(
        stepId: stepId, direction: direction.rawValue, syscall: syscall, errno: code,
        cocoa: cocoa, errorClass: errorClass, scope: scope)
    }
  }

  // MARK: Riepilogo

  /// Riassume le ripetizioni di una cella: esiti contati su tutte, oracoli dalla prima valida,
  /// ripetizioni discordanti segnalate con i valori divergenti.
  func summarize(
    _ spec: MatrixCellSpec, repetitions: [Repetition], retries: [Repetition],
    duration: TimeInterval
  ) -> MeasurementCell {
    let valid = repetitions.filter(\.isValid)
    let reference = valid.first ?? repetitions[0]
    var notes = (repetitions + retries).flatMap(\.notes)
    if reference.index != 1 {
      notes.append("r1 non valida: oracoli riportati da \(reference.tag)")
    }

    // Ripetizioni discordanti: ogni oracolo diverso da quello della prima ripetizione valida.
    var nonDeterministic = false
    let referenceSignature = reference.signature
    for repetition in valid where repetition.index != reference.index {
      for (expected, found) in zip(referenceSignature, repetition.signature)
      where expected.value != found.value {
        nonDeterministic = true
        notes.append(
          "\(repetition.tag) \(found.name): \(found.value) (\(reference.tag): \(expected.value))")
      }
    }
    let validRetries = retries.filter(\.isValid)
    if let first = validRetries.first {
      for retry in validRetries.dropFirst()
      where retry.decision?.outcomeLine != first.decision?.outcomeLine {
        nonDeterministic = true
        notes.append(
          "\(retry.tag) decisione: \(retry.decision?.outcomeLine ?? "-") "
            + "(\(first.tag): \(first.decision?.outcomeLine ?? "-"))")
      }
    }

    var outcomes: [String: Int] = [:]
    var reasons: [String: Int] = [:]
    for output in repetitions.compactMap(\.recovery) {
      outcomes[output.outcome.rawValue, default: 0] += 1
      if output.outcome == .nonSupportabile {
        reasons[output.reason ?? "?", default: 0] += 1
      }
    }

    let abandons = repetitions.compactMap(\.decision)
    let decidedRetries = retries.compactMap(\.decision)
    let followUp =
      abandons.isEmpty && retries.isEmpty
      ? nil
      : FollowUp(
        retry: retries.isEmpty ? nil : Self.followUp(decidedRetries),
        abandon: abandons.isEmpty ? nil : Self.followUp(abandons))

    let recovery = reference.recovery
    let primary = reference.primaryFailure
    let errorClass =
      (primary?.errorClass ?? recovery?.firstStepClass?.errorClass).flatMap(ErrorClass.init)
    let all = repetitions + retries
    return MeasurementCell(
      cellId: spec.id,
      point: spec.point.id,
      phase: spec.point.phase,
      strategy: spec.strategy,
      perturbation: spec.perturbation,
      target: reference.target,
      applicable: reference.applicable,
      notApplicableReason: reference.notApplicableReason,
      repetitions: repetitions.count,
      outcomes: outcomes,
      reasons: reasons,
      direction: recovery?.direction,
      recordTroncato: recovery?.recordTroncato,
      divergences: recovery?.divergences ?? [],
      trace: recovery?.trace ?? [],
      steps: recovery?.steps ?? [:],
      pairs: Dictionary(
        reference.pairs.map {
          ($0.opId, CellPair(image: $0.image, sidecar: $0.sidecar, separated: $0.isSeparated))
        }, uniquingKeysWith: { first, _ in first }),
      separationsAtCrash: reference.separationsAtCrash,
      separationsBeforePerturbation: reference.separationsBeforePerturbation,
      separationsAtFirstCrash: reference.separationsAtFirstCrash,
      separationsReported: recovery?.separationsAtStart ?? [],
      separationsResidual: recovery?.separationsResidual ?? [],
      separationDetected: recovery.map {
        Matrix.detection(observed: reference.separationsAtCrash, reported: $0.separationsAtStart)
      },
      compensation: reference.compensation,
      resumeMatchesExpected: reference.resumeMatchesExpected,
      resumeMismatches: reference.resumeMismatches,
      recognitionError: repetitions.contains { !$0.recognitionErrors.isEmpty },
      recognitionErrors: repetitions.flatMap { repetition in
        repetition.recognitionErrors.map { "\(repetition.tag) \($0)" }
      },
      followUp: followUp,
      errorClass: errorClass,
      errorScope: (primary?.scope ?? recovery?.firstStepClass?.scope).flatMap(ErrorScope.init)
        ?? errorClass?.scope,
      errnoObserved: primary?.errno,
      cocoaObserved: primary?.cocoa,
      syscallObserved: primary?.syscall,
      failures: reference.failures,
      nonDeterministic: nonDeterministic,
      repetitionNotes: notes,
      pointReached: all.allSatisfy(\.pointReached),
      snapshotsNotSettled: all.flatMap(\.unsettled),
      settle: SettleStatistics(
        captures: all.map(\.settle.captures).reduce(0, +),
        changed: all.map(\.settle.changed).reduce(0, +),
        maxLastChangeSeconds: all.map(\.settle.maxLastChangeSeconds).max() ?? 0),
      benchErrors: all.flatMap(\.benchErrors),
      durationSeconds: duration)
  }

  /// Esiti di un ramo dopo un `bloccato`.
  static func followUp(_ decisions: [RecoveryOutput]) -> FollowUpResult {
    var outcomes: [String: Int] = [:]
    var reasons: [String: Int] = [:]
    for decision in decisions {
      outcomes[decision.outcome.rawValue, default: 0] += 1
      if decision.outcome == .nonSupportabile {
        reasons[decision.reason ?? "?", default: 0] += 1
      }
    }
    return FollowUpResult(
      repetitions: decisions.count, outcomes: outcomes, reasons: reasons,
      trace: decisions.first?.trace ?? [],
      reportedPairs: Dictionary(
        (decisions.first?.pairs ?? []).map {
          ($0.opId, "immagine=\($0.image) sidecar=\($0.sidecar)")
        }, uniquingKeysWith: { first, _ in first }))
  }
}
