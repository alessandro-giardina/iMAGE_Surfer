// Recupero del lotto in un nuovo processo: riconoscimento dal disco, ripresa o compensazione
// idempotente, separazioni immagine/sidecar ed esito, più la decisione dell'utente su un lotto
// `bloccato`.
//
// Come l'esecutore, il recupero non ha `defer`, né `atexit`, né `catch` che scrivano sul log o sul
// disco in risposta a un arresto: l'unico `catch` dei passi è tipizzato su `StepFailure`, e
// `SimulatedCrash` attraversa il recupero senza scritture. Così un secondo arresto (`D01`, `D02`)
// lascia esattamente lo stato raggiunto.
//
// Politica degli errori, la stessa in ripresa e in compensazione:
// - errore **locale** → `step-failed` con classe e ambito, il passo resta saltato e il recupero
//   prosegue;
// - errore **sistemico** → `step-failed` con classe e ambito, e il recupero si sospende (FR-079).
//   Un passo già `sospeso` al riconoscimento sospende il recupero prima di qualunque azione;
// - errore **non classificato** → `step-failed` senza classe, e il recupero si ferma, come
//   l'esecutore: agire ancora su uno stato che nessuna regola descrive non è sicuro.
//
// L'esito viene sempre dal classificatore degli esiti, sugli stati finali riosservati sul disco.

import Darwin
import Foundation

/// Errori del recupero che non sono un esito.
public enum RecoveryError: Error, Equatable, CustomStringConvertible, LocalizedError {
  /// `decide` richiede che l'ultimo esito del log sia `bloccato`.
  case notBlocked(lastOutcome: String?)

  public var description: String {
    switch self {
    case .notBlocked(let lastOutcome?):
      "decide richiede un lotto bloccato: l'ultimo esito del log è \(lastOutcome)"
    case .notBlocked(nil):
      "decide richiede un lotto bloccato: il log non ha alcun esito"
    }
  }

  public var errorDescription: String? { description }
}

/// Stato di un passo all'avvio del recupero e alla fine.
public struct StepReport: Equatable, Sendable {
  public let stepId: String
  public let start: StepState
  public let final: StepState

  public init(stepId: String, start: StepState, final: StepState) {
    self.stepId = stepId
    self.start = start
    self.final = final
  }

  /// `PASSO <stepId> <stato all'avvio> -> <stato finale>`, seguito da ` classe=<…> ambito=<…>`
  /// se il passo finisce (o, in mancanza, comincia) saltato o sospeso.
  public var line: String {
    "PASSO \(stepId) \(start.name) -> \(final.name)"
      + Recognizer.classSuffix(final.errorClass ?? start.errorClass)
  }
}

/// Fallimento di un passo durante il recupero, con la sua classificazione.
public struct RecoveryFailure: Equatable, Sendable {
  /// Il passo, oppure `Steps.prepareStepId` per la preparazione e la sua compensazione.
  public let stepId: String
  public let direction: StepDirection
  public let failure: StepFailure
  public let classification: Classification

  public init(
    stepId: String, direction: StepDirection, failure: StepFailure,
    classification: Classification
  ) {
    self.stepId = stepId
    self.direction = direction
    self.failure = failure
    self.classification = classification
  }
}

/// Resoconto di un recupero, o di una decisione dell'utente.
public struct RecoveryReport: Equatable, Sendable {
  /// `.retry` o `.abandon` se il resoconto viene da `decide`, altrimenti `.none`.
  public let decision: OutcomeDecision
  /// La strategia del recupero; `nil` per `decide abandon`, che non recupera.
  public let strategy: RecoveryStrategy?
  public let direction: RecoveryDirection
  public let recordTroncato: Bool
  public let tornEvidence: URL?
  public let divergences: [Divergence]
  /// Un passo per riga, in ordine di piano; vuoto senza piano.
  public let steps: [StepReport]
  /// Posizioni di ogni coppia dopo il recupero, in ordine di piano.
  public let pairs: [PairPositions]
  /// Le operazioni separate al riconoscimento, prima di agire.
  public let separationsAtStart: [String]
  /// I fallimenti registrati dal recupero, nell'ordine in cui sono avvenuti.
  public let failures: [RecoveryFailure]
  public let outcome: Outcome

  /// Le operazioni ancora separate dopo il recupero.
  public var residualSeparations: [String] { pairs.filter(\.isSeparated).map(\.opId) }

  /// Righe scritte prima di agire: `DECISIONE <retry|abandon>` (solo da `decide`),
  /// `RECUPERO strategia=<…> direzione=<…>` (non per `abandon`), `RECORD-TRONCATO` e le
  /// `DIVERGENZA`.
  public var headerLines: [String] {
    Self.headerLines(
      decision: decision, strategy: strategy, direction: direction,
      recordTroncato: recordTroncato, divergences: divergences)
  }

  static func headerLines(
    decision: OutcomeDecision, strategy: RecoveryStrategy?, direction: RecoveryDirection,
    recordTroncato: Bool, divergences: [Divergence]
  ) -> [String] {
    var lines: [String] = []
    if decision != .none { lines.append("DECISIONE \(decision.rawValue)") }
    if let strategy {
      lines.append("RECUPERO strategia=\(strategy.rawValue) direzione=\(direction.rawValue)")
    }
    lines.append(Recognizer.tornLine(recordTroncato))
    lines += divergences.map(\.line)
    return lines
  }

  /// Righe scritte dopo il recupero: una `PASSO` per passo, una `COPPIA` per operazione,
  /// `SEPARAZIONI-ALL-AVVIO`, `SEPARAZIONI-RESIDUE`, `ESITO` e una `TRACCIA` per riga della
  /// traccia dell'esito.
  public var resultLines: [String] {
    steps.map(\.line) + pairs.map(\.line) + [
      "SEPARAZIONI-ALL-AVVIO \(Recognizer.separationList(separationsAtStart))",
      "SEPARAZIONI-RESIDUE \(Recognizer.separationList(residualSeparations))",
      outcome.line,
    ] + outcome.trace.map { "TRACCIA \($0)" }
  }

  /// Tutte le righe, nel formato fisso che la matrice analizza.
  public var lines: [String] { headerLines + resultLines }
}

/// Recupero del lotto e decisioni dell'utente.
public enum Recovery {
  /// `syscall` del `step-failed` di un passo che il ricontrollo delle precondizioni ha trovato in
  /// uno stato anomalo: il passo non è stato tentato.
  public static let precheckRefusal = "ricontrollo-passo"

  /// Recupera il lotto del log nella direzione stabilita dal riconoscimento.
  ///
  /// 1. `Recognizer.recognize`, con le separazioni **all'avvio**.
  /// 2. `append(.recovery(strategia, direzione, riassunto))`, poi le righe di testata a `output`.
  /// 3. Senza piano, con direzione `nessuna` o con un passo già `sospeso`, nessuna azione.
  /// 4. **Ripresa.** Se il log non ha un record `prepare`, prima la preparazione delle cartelle e
  ///    il suo record. Poi, per ogni passo `non-fatto` in ordine di piano: ricontrollo delle
  ///    precondizioni del solo passo (volume del piano, stato osservato), intento, `Sxx-a`,
  ///    esecuzione (`Sxx-m` per le copie), `Sxx-b`, fatto, `Sxx-c`.
  /// 5. **Compensazione.** Per ogni passo `fatto`, e per ogni copia interrotta con il temporaneo
  ///    annotato, in ordine inverso: intento di compensazione, `Kxx-a`, compensazione, `Kxx-b`,
  ///    fatto di compensazione. Poi `K00-a`, rimozione delle cartelle che i record `prepare` dicono
  ///    create dal lotto, `K00-b`.
  /// 6. **Stati finali** riosservati sul disco; un passo fallito durante il recupero prende lo stato
  ///    della sua classificazione. Esito dal classificatore degli esiti, poi `append(.outcome)` e
  ///    le righe dei risultati a `output`.
  ///
  /// - Parameters:
  ///   - decision: `.retry` quando il recupero segue `decide retry`; mai `.abandon`, che non
  ///     agisce sui file e passa da `decide(_:log:volume:injector:output:)`.
  ///   - output: riceve ogni riga del formato fisso appena è nota: la testata prima di agire, così
  ///     che un secondo arresto la lasci comunque sullo schermo.
  /// - Throws: `SimulatedCrash` dall'iniettore di prova; gli errori del log di intenti, che sono
  ///   errori del banco.
  @discardableResult
  public static func run(
    strategy: RecoveryStrategy, log: IntentLog, volume: WorkVolume, injector: CrashInjector,
    decision: OutcomeDecision = .none, output: (String) -> Void = { _ in }
  ) throws -> RecoveryReport {
    precondition(decision != .abandon, "decide abandon non esegue un recupero")
    return try perform(
      strategy: strategy, log: log, volume: volume, injector: injector, decision: decision,
      repairedEvidence: nil, output: output)
  }

  /// Registra la decisione dell'utente su un lotto `bloccato`.
  ///
  /// - **`retry`:** `append(.decision(retry))`, poi `run` con la strategia dell'ultimo record
  ///   `recovery` del log (se manca: `compensate` se una compensazione è avviata, altrimenti
  ///   `resume`); la direzione del log prevale comunque sulla strategia.
  /// - **`abandon`:** `append(.decision(abandon))`, nessuna azione sui file, poi il riconoscimento
  ///   per riferire dove è rimasto ogni file, ed esito con la decisione `abandon`: `abbandonato`
  ///   per la regola 3, salvo uno stato non riconoscibile, che resta `NON_SUPPORTABILE` per la
  ///   regola 2. `append(.outcome)`.
  ///
  /// - Throws: `RecoveryError.notBlocked` se l'ultimo esito del log non è `bloccato`, senza
  ///   scrivere nulla; gli errori di `run` e del log di intenti.
  @discardableResult
  public static func decide(
    _ decision: UserDecision, log: IntentLog, volume: WorkVolume, injector: CrashInjector,
    output: (String) -> Void = { _ in }
  ) throws -> RecoveryReport {
    let records = try log.read().records
    let last = Recognizer.lastOutcome(in: records)
    guard last == OutcomeKind.bloccato.rawValue else {
      throw RecoveryError.notBlocked(lastOutcome: last)
    }
    // Una coda troncata va riparata prima di ogni `append`.
    let evidence = try log.repairTornTail()
    let strategy =
      Recognizer.lastRecoveryStrategy(in: records)
      ?? (Recognizer.compensationStarted(in: records) ? .compensate : .resume)

    switch decision {
    case .retry:
      try log.append(.decision(.retry))
      return try perform(
        strategy: strategy, log: log, volume: volume, injector: injector, decision: .retry,
        repairedEvidence: evidence, output: output)

    case .abandon:
      try log.append(.decision(.abandon))
      let state = try Recognizer.recognize(log: log, volume: volume, requestedStrategy: strategy)
      let outcome = OutcomeClassifier.classify(
        outcomeInput(
          state: state, finalStates: state.steps.map(\.state), failures: [], decision: .abandon))
      try log.append(outcome.record)
      let report = RecoveryReport(
        decision: .abandon, strategy: nil, direction: state.direction,
        recordTroncato: evidence != nil || state.recordTroncato,
        tornEvidence: evidence ?? state.tornEvidence, divergences: state.divergences,
        steps: state.steps.map {
          StepReport(stepId: $0.step.id, start: $0.state, final: $0.state)
        },
        pairs: state.pairs, separationsAtStart: state.separations, failures: [], outcome: outcome)
      report.lines.forEach(output)
      return report
    }
  }

  /// Stato riconosciuto per `crashbench status`, senza agire e senza scrivere nel log, salvo la
  /// riparazione di un record troncato, che `RecognizedState.recordTroncato` dichiara. Le anomalie
  /// si classificano nella direzione del log se una compensazione è avviata, altrimenti in avanti.
  public static func status(log: IntentLog, volume: WorkVolume) throws -> RecognizedState {
    try Recognizer.recognize(log: log, volume: volume, requestedStrategy: .resume)
  }

  // MARK: - Recupero

  private static func perform(
    strategy: RecoveryStrategy, log: IntentLog, volume: WorkVolume, injector: CrashInjector,
    decision: OutcomeDecision, repairedEvidence: URL?, output: (String) -> Void
  ) throws -> RecoveryReport {
    // 1. Riconoscimento.
    let state = try Recognizer.recognize(log: log, volume: volume, requestedStrategy: strategy)
    let evidence = repairedEvidence ?? state.tornEvidence

    // 2. Record del recupero e testata.
    try log.append(
      .recovery(
        strategy: strategy.rawValue, direction: state.direction.rawValue, summary: state.summary))
    RecoveryReport.headerLines(
      decision: decision, strategy: strategy, direction: state.direction,
      recordTroncato: evidence != nil, divergences: state.divergences
    ).forEach(output)
    func finish(
      steps: [StepReport], pairs: [PairPositions], failures: [RecoveryFailure], outcome: Outcome
    ) throws -> RecoveryReport {
      try log.append(outcome.record)
      let report = RecoveryReport(
        decision: decision, strategy: strategy, direction: state.direction,
        recordTroncato: evidence != nil, tornEvidence: evidence, divergences: state.divergences,
        steps: steps, pairs: pairs, separationsAtStart: state.separations, failures: failures,
        outcome: outcome)
      report.resultLines.forEach(output)
      return report
    }

    // 3. Senza piano nessuna azione: regola 1.
    guard let plan = state.plan else {
      let outcome = OutcomeClassifier.classify(
        OutcomeInput(
          hasPlan: false, stepStates: [:], direction: strategy.direction, decision: decision))
      return try finish(steps: [], pairs: [], failures: [], outcome: outcome)
    }

    // 4-5. Azione, salvo un passo già sospeso al riconoscimento.
    var failures: [RecoveryFailure] = []
    if !state.steps.contains(where: { $0.state.isSuspended }) {
      switch state.direction {
      case .forward:
        failures = try resume(
          state: state, plan: plan, log: log, volume: volume, injector: injector)
      case .compensate:
        failures = try compensate(
          state: state, plan: plan, log: log, volume: volume, injector: injector)
      case .nessuna:
        break
      }
    }

    // 6. Stati finali dal disco, ed esito.
    let finalScan = Recognizer.scanSteps(
      plan: plan, volume: volume, direction: state.classificationDirection)
    let finalStates = zip(state.steps, finalScan.steps).map { start, final in
      failures.last { $0.stepId == start.step.id }.map {
        Recognizer.state(for: $0.classification)
      } ?? final.state
    }
    let outcome = OutcomeClassifier.classify(
      outcomeInput(state: state, finalStates: finalStates, failures: failures, decision: decision))
    return try finish(
      steps: zip(state.steps, finalStates).map { start, final in
        StepReport(stepId: start.step.id, start: start.state, final: final)
      },
      pairs: Recognizer.pairs(plan: plan, steps: finalScan.steps), failures: failures,
      outcome: outcome)
  }

  /// Ripresa: preparazione mancante, poi ogni passo `non-fatto` in ordine di piano.
  ///
  /// - Returns: i fallimenti registrati; il recupero si è fermato al primo sistemico o non
  ///   classificato.
  private static func resume(
    state: RecognizedState, plan: BatchPlan, log: IntentLog, volume: WorkVolume,
    injector: CrashInjector
  ) throws -> [RecoveryFailure] {
    var failures: [RecoveryFailure] = []

    // Un arresto prima di `X03-prepare` lascia le cartelle da preparare: senza, i passi verso
    // `selezione/` e `consegna/` fallirebbero per una precondizione mai soddisfatta.
    if !state.hasPrepareRecord {
      do {
        let created = try BatchExecutor.prepare(plan: plan, volume: volume)
        try log.append(.prepare(created: created))
      } catch let failure as StepFailure {
        let classification = classifyPrepare(failure, plan: plan, volume: volume)
        guard
          try record(
            failure, classification, direction: .forward, log: log, into: &failures)
        else { return failures }
      }
    }

    for recognition in state.steps where recognition.state == .nonFatto {
      let step = recognition.step
      do {
        // Ricontrollo delle precondizioni del solo passo.
        switch try precheck(step, plan: plan, volume: volume) {
        case .proceed:
          break
        case .alreadyDone:
          continue
        case .refused(let failure, let classification):
          guard
            try record(
              failure, classification, direction: .forward, log: log, into: &failures)
          else { return failures }
          continue
        }

        try log.append(.stepIntent(stepId: step.id, direction: .forward))
        try injector.hit(CrashPoints.point(step.id, .intent))
        let resultPath = try Steps.execute(
          step, plan: plan, volume: volume,
          afterTempWritten: {
            if step.kind == .copy { try injector.hit(CrashPoints.point(step.id, .tempWritten)) }
          })
        try injector.hit(CrashPoints.point(step.id, .acted))
        try log.append(.stepDone(stepId: step.id, direction: .forward, resultPath: resultPath))
        try injector.hit(CrashPoints.point(step.id, .recorded))
      } catch let failure as StepFailure {
        let classification = ErrorClassifier.classify(
          failure: failure, observation: nil, step: step, plan: plan, volume: volume,
          direction: .forward)
        guard
          try record(failure, classification, direction: .forward, log: log, into: &failures)
        else { return failures }
      }
    }
    return failures
  }

  /// Compensazione: ogni passo `fatto`, e ogni copia interrotta, in ordine inverso; poi le cartelle
  /// create dal lotto.
  ///
  /// - Returns: i fallimenti registrati; il recupero si è fermato al primo sistemico o non
  ///   classificato.
  private static func compensate(
    state: RecognizedState, plan: BatchPlan, log: IntentLog, volume: WorkVolume,
    injector: CrashInjector
  ) throws -> [RecoveryFailure] {
    var failures: [RecoveryFailure] = []
    // Il temporaneo di una copia interrotta è un artefatto del banco: la sua compensazione lo
    // rimuove con `unlink`, altrimenti `consegna/` non tornerebbe vuota.
    let pending = state.steps.reversed().filter { $0.state == .fatto || $0.tempPath != nil }
    for recognition in pending {
      let step = recognition.step
      do {
        try log.append(.stepIntent(stepId: step.id, direction: .compensate))
        try injector.hit(CrashPoints.compensationPoint(step.id, .intent))
        let resultPath = try Steps.compensate(step, plan: plan, volume: volume)
        try injector.hit(CrashPoints.compensationPoint(step.id, .acted))
        try log.append(
          .stepDone(stepId: step.id, direction: .compensate, resultPath: resultPath))
      } catch let failure as StepFailure {
        let classification = ErrorClassifier.classify(
          failure: failure, observation: nil, step: step, plan: plan, volume: volume,
          direction: .compensate)
        guard
          try record(
            failure, classification, direction: .compensate, log: log, into: &failures)
        else { return failures }
      }
    }

    try injector.hit(CrashPoints.compensationPoint(Steps.prepareStepId, .intent))
    do {
      try Steps.compensatePrepare(created: state.createdDirectories, volume: volume)
    } catch let failure as StepFailure {
      let classification = classifyPrepare(failure, plan: plan, volume: volume)
      guard
        try record(failure, classification, direction: .compensate, log: log, into: &failures)
      else { return failures }
    }
    try injector.hit(CrashPoints.compensationPoint(Steps.prepareStepId, .acted))
    return failures
  }

  // MARK: - Supporto

  /// Esito del ricontrollo delle precondizioni di un passo prima di agire.
  enum Precheck {
    case proceed
    /// Il passo risulta già fatto: nessuna azione.
    case alreadyDone
    /// Il passo non va tentato: il fallimento da registrare e la sua classificazione.
    case refused(StepFailure, Classification)
  }

  /// Ricontrolla le precondizioni del solo passo: il volume del lotto è quello del piano, e il
  /// passo è osservato `non-fatto` (anche con un temporaneo di copia). Un'anomalia va al
  /// classificatore degli errori, e il passo non viene tentato.
  static func precheck(_ step: PlannedStep, plan: BatchPlan, volume: WorkVolume) throws -> Precheck
  {
    if ErrorClassifier.volumeIsMissing(plan: plan, volume: volume) {
      let failure = StepFailure(
        stepId: step.id, syscall: StepFailure.volumeCheck, errno: nil,
        path: volume.batchRoot.fileSystemPath)
      return .refused(failure, .classified(.volumeMissing))
    }
    let observation = try Steps.observe(step, plan: plan, volume: volume)
    switch observation {
    case .notDone, .partial:
      return .proceed
    case .done:
      return .alreadyDone
    case .anomaly:
      let failure = StepFailure(
        stepId: step.id, syscall: precheckRefusal, errno: nil,
        path: volume.batchURL(step.source).fileSystemPath)
      let classification = ErrorClassifier.classify(
        failure: nil, observation: observation, step: step, plan: plan, volume: volume,
        direction: .forward)
      return .refused(failure, classification)
    }
  }

  /// Classifica un fallimento della preparazione o della sua compensazione, che non hanno un passo
  /// del piano: si applicano, nell'ordine del classificatore degli errori, le regole che non
  /// dipendono dalle posizioni di un file (volume, scrittura della radice del lotto, spazio,
  /// `L-locked`). Ogni altro caso resta non classificato.
  static func classifyPrepare(
    _ failure: StepFailure, plan: BatchPlan, volume: WorkVolume
  ) -> Classification {
    if ErrorClassifier.volumeIsMissing(plan: plan, volume: volume) {
      return .classified(.volumeMissing)
    }
    if access(volume.batchRoot.fileSystemPath, W_OK) != 0 {
      let code = errno
      if code != ENOENT, code != ENOTDIR { return .classified(.folderReadonly) }
    }
    if let code = failure.errno, code == ENOSPC || code == EDQUOT {
      return .classified(.spaceExhausted)
    }
    if ErrorClassifier.isLocked(failure) { return .classified(.locked) }
    return .nonClassificato("\(failure.stepId); \(failure)")
  }

  /// Registra il fallimento nel log (`step-failed`, con classe e ambito se classificato) e lo
  /// aggiunge a `failures`.
  ///
  /// - Returns: vero se il recupero prosegue, cioè se l'errore è locale.
  private static func record(
    _ failure: StepFailure, _ classification: Classification, direction: StepDirection,
    log: IntentLog, into failures: inout [RecoveryFailure]
  ) throws -> Bool {
    switch classification {
    case .classified(let errorClass):
      try log.append(
        .failed(
          failure, direction: direction, errorClass: errorClass.rawValue,
          scope: errorClass.scope.rawValue))
    case .nonClassificato:
      try log.append(.failed(failure, direction: direction))
    }
    failures.append(
      RecoveryFailure(
        stepId: failure.stepId, direction: direction, failure: failure,
        classification: classification))
    return classification.scope == .locale
  }

  /// Ingresso del classificatore degli esiti dagli stati finali e dai fallimenti del recupero.
  ///
  /// Le classi sistemiche e locali vengono dagli stati finali e dai fallimenti della preparazione,
  /// senza ripetizioni. La traccia di un passo `non-riconoscibile` va in `unclassified` se nasce da
  /// un fallimento non classificato del recupero, altrimenti in `unrecognized`.
  static func outcomeInput(
    state: RecognizedState, finalStates: [StepState], failures: [RecoveryFailure],
    decision: OutcomeDecision
  ) -> OutcomeInput {
    var systemic: [ErrorClass] = []
    var local: [ErrorClass] = []
    var unrecognized: [String] = []
    var unclassified: [String] = []
    func add(_ errorClass: ErrorClass, to list: inout [ErrorClass]) {
      if !list.contains(errorClass) { list.append(errorClass) }
    }

    for (recognition, final) in zip(state.steps, finalStates) {
      switch final {
      case .saltato(let errorClass): add(errorClass, to: &local)
      case .sospeso(let errorClass): add(errorClass, to: &systemic)
      case .nonRiconoscibile(let trace):
        let fromFailure = failures.contains {
          $0.stepId == recognition.step.id && $0.classification.errorClass == nil
        }
        if fromFailure { unclassified.append(trace) } else { unrecognized.append(trace) }
      case .fatto, .nonFatto:
        break
      }
    }
    for failure in failures where failure.stepId == Steps.prepareStepId {
      switch failure.classification {
      case .classified(let errorClass) where errorClass.scope == .locale:
        add(errorClass, to: &local)
      case .classified(let errorClass): add(errorClass, to: &systemic)
      case .nonClassificato(let trace): unclassified.append(trace)
      }
    }

    var states: [String: StepState] = [:]
    for (recognition, final) in zip(state.steps, finalStates) {
      states[recognition.step.id] = final
    }
    return OutcomeInput(
      hasPlan: state.plan != nil, stepStates: states, direction: state.classificationDirection,
      unresolvedSystemic: systemic, localSkips: local, unrecognized: unrecognized,
      unclassified: unclassified, decision: decision)
  }
}

extension StepState {
  /// Vero per un passo sospeso da un errore sistemico.
  var isSuspended: Bool {
    if case .sospeso = self { true } else { false }
  }
}
