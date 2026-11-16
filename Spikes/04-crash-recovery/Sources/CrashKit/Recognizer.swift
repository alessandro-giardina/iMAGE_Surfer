// Riconoscimento dello stato del lotto dal disco, in un nuovo processo.
//
// Il log dice cosa si voleva fare, il disco cosa è accaduto. Il riconoscitore legge del log solo
// ciò che il disco non può dire: il piano (posizioni e digest attesi), le cartelle create dal
// lotto e la direzione già intrapresa. Lo stato di ogni passo viene invece osservato sul disco con
// `Steps.observe`, e quando log e disco divergono la divergenza viene riferita e **vale il disco**.
//
// Il riconoscitore non legge mai `pre-snapshot.json`: è l'oracolo del banco, non conoscenza della
// macchina sotto test.

import Darwin
import Foundation

/// Posizione di un file della coppia osservata sul disco: dove si trova il file con il digest del
/// piano.
public enum FilePosition: String, Codable, Sendable, CaseIterable {
  /// Nell'origine del piano.
  case origine = "orig"
  /// Nella destinazione del piano. Per una copia vale `dest` se la copia esiste, anche con
  /// l'originale ancora al suo posto.
  case destinazione = "dest"
  /// Nel Cestino del volume, in una voce trovata per digest.
  case cestino = "cest"
  /// In nessuna delle posizioni attese.
  case assente = "ass"
  /// In più di una posizione (anche due voci del Cestino), oppure non osservabile perché la radice
  /// del lotto manca o non è sul volume del piano.
  case ambigua = "amb"
}

/// Posizioni di immagine e sidecar di un'operazione.
public struct PairPositions: Equatable, Sendable {
  public let opId: String
  public let image: FilePosition
  public let sidecar: FilePosition

  public init(opId: String, image: FilePosition, sidecar: FilePosition) {
    self.opId = opId
    self.image = image
    self.sidecar = sidecar
  }

  /// Vero se immagine e sidecar sono in posizioni diverse.
  public var isSeparated: Bool { image != sidecar }

  /// `COPPIA <opId> immagine=<pos> sidecar=<pos>`, seguito da ` SEPARATA` se separata.
  public var line: String {
    "COPPIA \(opId) immagine=\(image.rawValue) sidecar=\(sidecar.rawValue)"
      + (isSeparated ? " SEPARATA" : "")
  }
}

/// Direzione adottata dal recupero.
public enum RecoveryDirection: String, Codable, Sendable, CaseIterable {
  /// Ripresa: i passi non fatti si eseguono.
  case forward
  /// Compensazione: i passi fatti si riportano all'origine, in ordine inverso.
  case compensate
  /// Nessuna azione: il lotto si era interrotto prima di agire.
  case nessuna
}

/// Divergenza fra lo stato di un passo secondo il log e quello osservato sul disco.
public struct Divergence: Equatable, Sendable {
  public let stepId: String
  /// Stato secondo il log: `fatto` se l'ultimo `step-done` del passo è in avanti, altrimenti
  /// `non-fatto`.
  public let log: String
  /// Stato osservato sul disco, che è quello che vale.
  public let disk: String

  public init(stepId: String, log: String, disk: String) {
    self.stepId = stepId
    self.log = log
    self.disk = disk
  }

  /// `DIVERGENZA <stepId> log=<stato> disco=<stato>`.
  public var line: String { "DIVERGENZA \(stepId) log=\(log) disco=\(disk)" }
}

/// Stato riconosciuto di un passo.
public struct StepRecognition: Equatable, Sendable {
  public let step: PlannedStep
  public let state: StepState
  /// Lo stato osservato; `nil` se il passo non è stato osservato (volume assente) o se
  /// l'osservazione è fallita.
  public let observation: StepObservation?
  /// Posizione del file del passo.
  public let position: FilePosition
  /// Classificazione dell'anomalia o dell'osservazione fallita; `nil` per uno stato atteso.
  public let classification: Classification?

  public init(
    step: PlannedStep, state: StepState, observation: StepObservation?, position: FilePosition,
    classification: Classification?
  ) {
    self.step = step
    self.state = state
    self.observation = observation
    self.position = position
    self.classification = classification
  }

  /// Il temporaneo di una copia interrotta, relativo al punto di montaggio: il passo è `non-fatto`
  /// e il temporaneo è annotato.
  public var tempPath: String? {
    if case .partial(let tempPath) = observation { tempPath } else { nil }
  }

  /// `PASSO <stepId> <stato>`, seguito da ` classe=<…> ambito=<…>` per un passo saltato o sospeso.
  public var statusLine: String {
    "PASSO \(step.id) \(state.name)" + Recognizer.classSuffix(state.errorClass)
  }
}

extension StepState {
  /// La classe di un passo saltato o sospeso.
  public var errorClass: ErrorClass? {
    switch self {
    case .saltato(let errorClass), .sospeso(let errorClass): errorClass
    case .fatto, .nonFatto, .nonRiconoscibile: nil
    }
  }
}

/// Stato del lotto riconosciuto dal disco, con quanto il log aggiunge: piano, cartelle create,
/// direzione già intrapresa.
public struct RecognizedState: Sendable {
  /// Strategia chiesta con `--strategy`.
  public let requestedStrategy: RecoveryStrategy
  /// Prefisso valido del log, letto prima di ogni scrittura del recupero.
  public let records: [IntentLog.Record]
  /// Vero se il log terminava con un record troncato, ora riparato.
  public let recordTroncato: Bool
  /// Il file di evidenza del record troncato, `state/torn-<ISO8601>.txt`.
  public let tornEvidence: URL?
  /// Il piano del log; `nil` se il log non ha un record `plan` completo (stato `noPlan`).
  public let plan: BatchPlan?
  /// Falso se la radice del lotto manca o non è sul volume del piano: allora ogni passo è
  /// `sospeso(G-volume-missing)` e non si osserva altro. Senza piano dice solo se la radice esiste.
  public let volumePresent: Bool
  /// Stato di ogni passo, in ordine di piano.
  public let steps: [StepRecognition]
  /// Divergenze fra log e disco, in ordine di piano.
  public let divergences: [Divergence]
  /// Posizioni di ogni coppia, in ordine di piano.
  public let pairs: [PairPositions]
  /// Direzione adottata: quella del log se una compensazione è già avviata, `nessuna` dopo
  /// `interrotto-prima-di-agire`, altrimenti quella della strategia chiesta. `nessuna` anche senza
  /// piano.
  public let direction: RecoveryDirection

  /// Stato `noPlan`: nessun piano completo nel log.
  public var isNoPlan: Bool { plan == nil }

  /// Le operazioni con immagine e sidecar separati, in ordine di piano.
  public var separations: [String] { pairs.filter(\.isSeparated).map(\.opId) }

  /// Direzione con cui si classificano le anomalie: quella adottata, o quella della strategia
  /// chiesta se la direzione è `nessuna`.
  public var classificationDirection: StepDirection {
    Recognizer.stepDirection(direction, requested: requestedStrategy)
  }

  /// Vero se il log ha un record `prepare`.
  public var hasPrepareRecord: Bool {
    records.contains { $0.kind == .prepare }
  }

  /// Cartelle che i record `prepare` dicono create dal lotto, relative a `lotto/`, senza
  /// ripetizioni: solo queste la compensazione può rimuovere.
  public var createdDirectories: [String] {
    var created: [String] = []
    for case .prepare(let directories) in records {
      for directory in directories where !created.contains(directory) {
        created.append(directory)
      }
    }
    return created
  }

  /// Il tipo dell'ultimo record `outcome` del log.
  public var lastOutcome: String? { Recognizer.lastOutcome(in: records) }

  /// Lo stato riconosciuto del passo dato.
  public func step(_ id: String) -> StepRecognition? {
    steps.first { $0.step.id == id }
  }

  /// `RECORD-TRONCATO <si|no>`.
  public var recordTroncatoLine: String { Recognizer.tornLine(recordTroncato) }

  /// `SEPARAZIONI-ALL-AVVIO <opId,opId|nessuna>`.
  public var separationsLine: String {
    "SEPARAZIONI-ALL-AVVIO \(Recognizer.separationList(separations))"
  }

  /// Le righe di `crashbench status`: `RECORD-TRONCATO`, le `DIVERGENZA`, una `PASSO` per passo
  /// (senza freccia: nessuna azione), una `COPPIA` per operazione e `SEPARAZIONI-ALL-AVVIO`.
  public var statusLines: [String] {
    [recordTroncatoLine] + divergences.map(\.line) + steps.map(\.statusLine) + pairs.map(\.line)
      + [separationsLine]
  }

  /// Riassunto per il record `recovery` del log, su una riga.
  public var summary: String {
    let torn = "record-troncato=\(recordTroncato ? "si" : "no")"
    guard let plan else { return "nessun piano completo nel log; \(torn)" }
    let names = ["fatto", "non-fatto", "saltato", "sospeso", "non-riconoscibile"]
    let counts = names.map { name in
      "\(name)=\(steps.filter { $0.state.name == name }.count)"
    }
    let divergent = divergences.map(\.stepId)
    return "piano \(plan.planId.uuidString); passi \(counts.joined(separator: " ")); "
      + "divergenze=\(divergent.isEmpty ? "nessuna" : divergent.joined(separator: ",")); "
      + "separazioni=\(Recognizer.separationList(separations)); \(torn)"
  }
}

/// Riconoscitore dello stato del lotto dal disco.
public enum Recognizer {
  /// Riconosce dal disco lo stato raggiunto da ogni file del lotto.
  ///
  /// 1. **Log.** Legge il prefisso valido; una coda troncata viene riparata con `repairTornTail()`
  ///    e annotata con il file di evidenza.
  /// 2. **Piano.** Senza un record `plan` completo lo stato è `noPlan`, e il riconoscimento finisce
  ///    qui.
  /// 3. **Volume.** Se la radice del lotto manca, o il suo UUID non è quello del piano, ogni passo è
  ///    `sospeso(G-volume-missing)` con posizione `amb`, e non si osserva altro.
  /// 4. **Passi.** `observe`: `.done` → `fatto`; `.notDone` e `.partial` → `non-fatto` (con il
  ///    temporaneo annotato); `.anomaly` → classificatore degli errori: classe locale →
  ///    `saltato`, sistemica → `sospeso`, non classificata → `non-riconoscibile` con la traccia
  ///    delle posizioni ispezionate e dei digest trovati.
  /// 5. **Divergenze** fra log e disco per i passi `fatto` o `non-fatto`: vale il disco.
  /// 6. **Posizioni** di immagine e sidecar per ogni operazione.
  /// 7. **Direzione**: `compensate` se il log ha `undo-requested` o uno `step-intent` di
  ///    compensazione, qualunque sia la strategia chiesta; `nessuna` se l'ultimo esito è
  ///    `interrotto-prima-di-agire`; altrimenti quella della strategia.
  ///
  /// - Throws: gli errori del log di intenti (log corrotto, riparazione fallita), che sono errori
  ///   del banco.
  public static func recognize(
    log: IntentLog, volume: WorkVolume, requestedStrategy: RecoveryStrategy
  ) throws -> RecognizedState {
    // 1. Log.
    let content = try log.read()
    let evidence = content.tornTail == nil ? nil : try log.repairTornTail()
    let records = content.records

    // 2. Piano.
    guard let plan = plan(in: records) else {
      return RecognizedState(
        requestedStrategy: requestedStrategy, records: records, recordTroncato: evidence != nil,
        tornEvidence: evidence, plan: nil, volumePresent: batchRootExists(volume), steps: [],
        divergences: [], pairs: [], direction: .nessuna)
    }

    // 7. Direzione, prima delle osservazioni: decide la direzione con cui classificare.
    let direction = direction(records: records, requested: requestedStrategy)

    // 3-4. Volume e passi.
    let scan = scanSteps(
      plan: plan, volume: volume, direction: stepDirection(direction, requested: requestedStrategy))

    // 5. Divergenze: vale il disco.
    let logStates = logStates(in: records)
    var divergences: [Divergence] = []
    for recognition in scan.steps
    where recognition.state == .fatto || recognition.state == .nonFatto {
      let logState = logStates[recognition.step.id] ?? .nonFatto
      if logState != recognition.state {
        divergences.append(
          Divergence(
            stepId: recognition.step.id, log: logState.name, disk: recognition.state.name))
      }
    }

    // 6. Posizioni.
    return RecognizedState(
      requestedStrategy: requestedStrategy, records: records, recordTroncato: evidence != nil,
      tornEvidence: evidence, plan: plan, volumePresent: scan.volumePresent, steps: scan.steps,
      divergences: divergences, pairs: pairs(plan: plan, steps: scan.steps), direction: direction)
  }

  // MARK: - Passi

  /// Vero se la radice del lotto esiste. Serve solo senza piano, quando non c'è un UUID con cui
  /// confrontare il volume: dopo un'espulsione il punto di montaggio è una directory vuota
  /// dell'ospite.
  private static func batchRootExists(_ volume: WorkVolume) -> Bool {
    var info = stat()
    return lstat(volume.batchRoot.fileSystemPath, &info) == 0
  }

  /// Stato di ogni passo osservato sul disco, in ordine di piano. Se il volume del lotto manca,
  /// ogni passo è `sospeso(G-volume-missing)` senza osservazione.
  static func scanSteps(
    plan: BatchPlan, volume: WorkVolume, direction: StepDirection
  ) -> (volumePresent: Bool, steps: [StepRecognition]) {
    guard !ErrorClassifier.volumeIsMissing(plan: plan, volume: volume) else {
      let steps = plan.steps.map { step in
        StepRecognition(
          step: step, state: .sospeso(.volumeMissing), observation: nil, position: .ambigua,
          classification: .classified(.volumeMissing))
      }
      return (false, steps)
    }
    return (
      true, plan.steps.map { recognizeStep($0, plan: plan, volume: volume, direction: direction) }
    )
  }

  /// Stato di un passo osservato sul disco.
  static func recognizeStep(
    _ step: PlannedStep, plan: BatchPlan, volume: WorkVolume, direction: StepDirection
  ) -> StepRecognition {
    let observation: StepObservation
    do {
      observation = try Steps.observe(step, plan: plan, volume: volume)
    } catch {
      // `Steps.observe` lancia solo `StepFailure`: una lettura fallita va al classificatore come
      // un fallimento, e senza osservazione la posizione non è nota.
      let classification =
        if let failure = error as? StepFailure {
          ErrorClassifier.classify(
            failure: failure, observation: nil, step: step, plan: plan, volume: volume,
            direction: direction)
        } else {
          Classification.nonClassificato("\(step.id) \(direction.rawValue); \(error)")
        }
      return StepRecognition(
        step: step, state: state(for: classification), observation: nil, position: .ambigua,
        classification: classification)
    }

    let position = position(of: step, observation: observation, volume: volume)
    switch observation {
    case .done:
      return StepRecognition(
        step: step, state: .fatto, observation: observation, position: position,
        classification: nil)
    case .notDone, .partial:
      return StepRecognition(
        step: step, state: .nonFatto, observation: observation, position: position,
        classification: nil)
    case .anomaly:
      let classification = ErrorClassifier.classify(
        failure: nil, observation: observation, step: step, plan: plan, volume: volume,
        direction: direction)
      return StepRecognition(
        step: step, state: state(for: classification), observation: observation,
        position: position, classification: classification)
    }
  }

  /// Stato di un passo dalla classificazione del suo errore: classe locale → `saltato`,
  /// sistemica → `sospeso`, non classificato → `non-riconoscibile` con la traccia.
  static func state(for classification: Classification) -> StepState {
    switch classification {
    case .classified(let errorClass) where errorClass.scope == .locale: .saltato(errorClass)
    case .classified(let errorClass): .sospeso(errorClass)
    case .nonClassificato(let trace): .nonRiconoscibile(trace: trace)
    }
  }

  // MARK: - Posizioni

  /// Posizione del file del passo: dove si trova il file con il digest del piano.
  ///
  /// `.notDone` e `.partial` → `orig`; `.done` → `dest`, o `cest` per un `trash`. In un'anomalia
  /// si contano le posizioni con il digest del piano (origine, destinazione, ogni voce del Cestino
  /// per un `trash`; il temporaneo di copia non è una posizione): una → quella, nessuna → `ass`,
  /// più di una → `amb`. Per una copia vale `dest` se la copia esiste.
  static func position(
    of step: PlannedStep, observation: StepObservation, volume: WorkVolume
  ) -> FilePosition {
    switch observation {
    case .notDone, .partial:
      return .origine
    case .done:
      return step.kind == .trash ? .cestino : .destinazione
    case .anomaly(let found):
      let sourceKey = volume.volumeRelativePath(of: volume.batchURL(step.source))
      let destinationKey = step.destination.map {
        volume.volumeRelativePath(of: volume.batchURL($0))
      }
      var positions: [FilePosition] = []
      for (key, digest) in found.sorted(by: { $0.key < $1.key }) where digest == step.sha256 {
        if key == sourceKey {
          positions.append(.origine)
        } else if key == destinationKey {
          positions.append(.destinazione)
        } else if step.kind == .trash {
          positions.append(.cestino)
        }
      }
      if step.kind == .copy, positions.contains(.destinazione) { return .destinazione }
      switch positions.count {
      case 0: return .assente
      case 1: return positions[0]
      default: return .ambigua
      }
    }
  }

  /// Posizioni di immagine e sidecar per ogni operazione, in ordine di piano. L'immagine è il
  /// passo con l'estensione `Fixtures.pairExtensions[0]`, il sidecar quello con la seconda.
  static func pairs(plan: BatchPlan, steps: [StepRecognition]) -> [PairPositions] {
    var opIds: [String] = []
    for step in plan.steps where !opIds.contains(step.opId) { opIds.append(step.opId) }
    func member(_ opId: String, _ fileExtension: String) -> StepRecognition? {
      steps.first {
        $0.step.opId == opId && URL(filePath: $0.step.source).pathExtension == fileExtension
      }
    }
    return opIds.compactMap { opId in
      guard let image = member(opId, Fixtures.pairExtensions[0]),
        let sidecar = member(opId, Fixtures.pairExtensions[1])
      else { return nil }
      return PairPositions(opId: opId, image: image.position, sidecar: sidecar.position)
    }
  }

  // MARK: - Log

  /// Il primo record `plan` del log.
  static func plan(in records: [IntentLog.Record]) -> BatchPlan? {
    for case .plan(let plan) in records { return plan }
    return nil
  }

  /// Il tipo dell'ultimo record `outcome`.
  static func lastOutcome(in records: [IntentLog.Record]) -> String? {
    for case .outcome(let outcome, _, _) in records.reversed() { return outcome }
    return nil
  }

  /// La strategia dell'ultimo record `recovery`.
  static func lastRecoveryStrategy(in records: [IntentLog.Record]) -> RecoveryStrategy? {
    for case .recovery(let strategy, _, _) in records.reversed() {
      return RecoveryStrategy(rawValue: strategy)
    }
    return nil
  }

  /// Vero se il log mostra una compensazione avviata: `undo-requested`, o uno `step-intent` di
  /// compensazione.
  static func compensationStarted(in records: [IntentLog.Record]) -> Bool {
    records.contains { record in
      switch record {
      case .undoRequested, .stepIntent(stepId: _, direction: .compensate): true
      default: false
      }
    }
  }

  /// Direzione del recupero: una compensazione avviata non si rovescia mai in silenzio.
  static func direction(
    records: [IntentLog.Record], requested: RecoveryStrategy
  ) -> RecoveryDirection {
    if compensationStarted(in: records) { return .compensate }
    if lastOutcome(in: records) == BatchExecutor.interruptedBeforeActing { return .nessuna }
    return requested == .resume ? .forward : .compensate
  }

  /// Direzione dei passi per una direzione del recupero; `nessuna` vale come la strategia chiesta.
  static func stepDirection(
    _ direction: RecoveryDirection, requested: RecoveryStrategy
  ) -> StepDirection {
    switch direction {
    case .forward: .forward
    case .compensate: .compensate
    case .nessuna: requested.direction
    }
  }

  /// Stato di ogni passo secondo il log: `fatto` se il suo ultimo `step-done` è in avanti,
  /// `non-fatto` se è di compensazione; i passi senza `step-done` mancano.
  static func logStates(in records: [IntentLog.Record]) -> [String: StepState] {
    var states: [String: StepState] = [:]
    for case .stepDone(let stepId, let direction, _) in records {
      states[stepId] = direction == .forward ? .fatto : .nonFatto
    }
    return states
  }

  // MARK: - Formato

  /// `OP2,OP5`, oppure `nessuna`.
  static func separationList(_ opIds: [String]) -> String {
    opIds.isEmpty ? "nessuna" : opIds.joined(separator: ",")
  }

  /// `RECORD-TRONCATO <si|no>`.
  static func tornLine(_ torn: Bool) -> String {
    "RECORD-TRONCATO \(torn ? "si" : "no")"
  }

  /// ` classe=<…> ambito=<…>`, oppure la stringa vuota senza classe.
  static func classSuffix(_ errorClass: ErrorClass?) -> String {
    errorClass.map { " classe=\($0.rawValue) ambito=\($0.scope.rawValue)" } ?? ""
  }
}
