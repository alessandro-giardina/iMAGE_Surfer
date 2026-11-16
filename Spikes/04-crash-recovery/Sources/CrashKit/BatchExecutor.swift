// Macchina a stati del lotto: piano → ricontrollo → preparazione → passi → esito, con
// l'annullamento dell'utente (FR-083) dopo un lotto completato.
//
// Ogni fase si chiude con un record del log di intenti, e ogni passo scrive il proprio intento
// **prima** dell'azione. Fra un record e l'azione l'esecutore chiama l'iniettore nel punto
// dell'elenco enumerato (`CrashPoints`), così che un arresto cada esattamente lì.
//
// Perché nessuna pulizia. Un arresto deve lasciare esattamente lo stato raggiunto, come lo
// lascerebbe la caduta del processo: l'esecutore non ha `defer`, né `atexit`, né `catch` che
// scrivano sul log o sul disco in risposta a un arresto. L'unico `catch` dei passi è tipizzato su
// `StepFailure` e registra il fallimento come prescrive il piano; `SimulatedCrash` e ogni altro
// errore attraversano l'esecutore senza scritture.

import Darwin
import Foundation

/// Risultato di un'esecuzione del lotto che non si è arrestata.
public enum BatchRunResult: Equatable, Sendable {
  /// Il ricontrollo delle precondizioni ha trovato divergenze dal piano: nessuna azione eseguita
  /// (FR-080). Non è uno dei cinque esiti.
  case interruptedBeforeActing(divergences: [String])
  /// L'esito registrato per ultimo nel log, deciso dal classificatore degli esiti.
  case finished(Outcome)

  /// `interrotto-prima-di-agire`, oppure il tipo dell'esito.
  public var kind: String {
    switch self {
    case .interruptedBeforeActing: BatchExecutor.interruptedBeforeActing
    case .finished(let outcome): outcome.kind.rawValue
    }
  }

  /// Le divergenze del ricontrollo, oppure la traccia dell'esito.
  public var trace: [String] {
    switch self {
    case .interruptedBeforeActing(let divergences): divergences
    case .finished(let outcome): outcome.trace
    }
  }

  /// `ESITO <kind>`, seguito da ` motivo=<reason>` per `NON_SUPPORTABILE`.
  public var line: String {
    switch self {
    case .interruptedBeforeActing: "ESITO \(kind)"
    case .finished(let outcome): outcome.line
    }
  }
}

/// Esecutore del lotto attraverso la macchina a stati.
public enum BatchExecutor {
  /// Esito registrato quando il ricontrollo delle precondizioni diverge dal piano (FR-080).
  public static let interruptedBeforeActing = "interrotto-prima-di-agire"
  /// Nome dell'istantanea presa da `crashbench run` prima del lotto: è l'oracolo del banco, e il
  /// recupero non la legge mai.
  public static let preSnapshotFileName = "pre-snapshot.json"

  /// `<data>/state/pre-snapshot.json`.
  public static func preSnapshotURL(in volume: WorkVolume) -> URL {
    volume.stateDirectory.appending(path: preSnapshotFileName, directoryHint: .notDirectory)
  }

  /// Esegue il lotto del piano e ne registra ogni fase nel log.
  ///
  /// 1. **Piano.** `append(.plan)`, poi `X01-plan`; per `X00-plan-torn` metà del record, poi
  ///    l'arresto.
  /// 2. **Ricontrollo.** Ogni passo deve risultare non fatto, il volume deve essere quello del piano
  ///    e le cartelle esistenti scrivibili. Una divergenza registra `recheck(ok: false)` e l'esito
  ///    `interrotto-prima-di-agire`, senza toccare il disco; altrimenti `recheck(ok: true)`, poi
  ///    `X02-recheck`.
  /// 3. **Preparazione.** Crea le cartelle assenti di `directoriesToCreate`, poi
  ///    `append(.prepare(created))` e `X03-prepare`.
  /// 4. **Passi**, in ordine: intento, `Sxx-a`, azione (`Sxx-m` fra temporaneo e pubblicazione
  ///    delle copie), `Sxx-b`, fatto (per `S05-torn` metà del record, poi l'arresto), `Sxx-c`.
  ///    Un fallimento passa al classificatore degli errori: un errore locale registra `step-failed`
  ///    e il lotto prosegue; un errore sistemico registra `step-failed` e l'esito `bloccato`, e il
  ///    lotto si sospende (FR-079); un errore non classificato registra `step-failed` e l'esito
  ///    `NON_SUPPORTABILE`, e il lotto si ferma.
  /// 5. **Esito**, dal classificatore degli esiti.
  /// 6. **Annullamento**, con `undoAfter` e solo dopo `completato`: `undo-requested`, poi per ogni
  ///    passo in ordine inverso intento di compensazione, `Kxx-a`, compensazione, `Kxx-b`, fatto;
  ///    poi `K00-a`, rimozione delle cartelle create dal lotto, `K00-b` ed esito.
  ///
  /// - Parameters:
  ///   - undoAfter: annulla il lotto dopo un esito `completato`, come farebbe l'utente.
  ///   - beforeRecheck: gancio di sola prova, chiamato fra `X01-plan` e il ricontrollo.
  /// - Throws: `SimulatedCrash` dall'iniettore di prova; gli errori del log di intenti; gli errori
  ///   di preparazione e di annullamento, che sono errori del banco.
  @discardableResult
  public static func run(
    plan: BatchPlan, volume: WorkVolume, log: IntentLog, injector: CrashInjector,
    undoAfter: Bool = false, beforeRecheck: (() throws -> Void)? = nil
  ) throws -> BatchRunResult {
    // 1. Piano.
    if injector.hitTorn(CrashPoints.planTorn) {
      try log.appendTorn(.plan(plan))
      try injector.hit(CrashPoints.planTorn)
    } else {
      try log.append(.plan(plan))
      try injector.hit(CrashPoints.planRecorded)
    }

    // 2. Ricontrollo delle precondizioni (FR-080).
    try beforeRecheck?()
    let divergences = try recheck(plan: plan, volume: volume)
    guard divergences.isEmpty else {
      try log.append(.recheck(ok: false, divergences: divergences))
      try log.append(.outcome(outcome: interruptedBeforeActing, trace: divergences))
      return .interruptedBeforeActing(divergences: divergences)
    }
    try log.append(.recheck(ok: true))
    try injector.hit(CrashPoints.recheckDone)

    // 3. Preparazione.
    let created = try prepare(plan: plan, volume: volume)
    try log.append(.prepare(created: created))
    try injector.hit(CrashPoints.prepared)

    // 4. Passi.
    var states: [String: StepState] = [:]
    var localSkips: [ErrorClass] = []
    for (index, step) in plan.steps.enumerated() {
      try log.append(.stepIntent(stepId: step.id, direction: .forward))
      try injector.hit(CrashPoints.point(step.id, .intent))

      let resultPath: String
      do {
        resultPath = try Steps.execute(
          step, plan: plan, volume: volume,
          afterTempWritten: {
            if step.kind == .copy { try injector.hit(CrashPoints.point(step.id, .tempWritten)) }
          })
      } catch let failure as StepFailure {
        let classification = ErrorClassifier.classify(
          failure: failure, observation: nil, step: step, plan: plan, volume: volume,
          direction: .forward)
        let pending = plan.steps[(index + 1)...].map { ($0.id, StepState.nonFatto) }
        switch classification {
        case .classified(let errorClass) where errorClass.scope == .locale:
          try log.append(
            .failed(
              failure, direction: .forward, errorClass: errorClass.rawValue,
              scope: errorClass.scope.rawValue))
          states[step.id] = .saltato(errorClass)
          localSkips.append(errorClass)
          continue
        case .classified(let errorClass):
          // Sospensione di FR-079: il lotto non prosegue.
          try log.append(
            .failed(
              failure, direction: .forward, errorClass: errorClass.rawValue,
              scope: errorClass.scope.rawValue))
          states[step.id] = .sospeso(errorClass)
          states.merge(pending) { current, _ in current }
          return try finish(
            OutcomeInput(
              hasPlan: true, stepStates: states, direction: .forward,
              unresolvedSystemic: [errorClass], localSkips: localSkips),
            log: log)
        case .nonClassificato(let trace):
          try log.append(.failed(failure, direction: .forward))
          states[step.id] = .nonRiconoscibile(trace: trace)
          states.merge(pending) { current, _ in current }
          return try finish(
            OutcomeInput(
              hasPlan: true, stepStates: states, direction: .forward, localSkips: localSkips,
              unclassified: [trace]),
            log: log)
        }
      }
      try injector.hit(CrashPoints.point(step.id, .acted))

      let done = IntentLog.Record.stepDone(
        stepId: step.id, direction: .forward, resultPath: resultPath)
      let torn = CrashPoints.tornPoint(step.id)
      if injector.hitTorn(torn) {
        try log.appendTorn(done)
        try injector.hit(torn)
      } else {
        try log.append(done)
      }
      try injector.hit(CrashPoints.point(step.id, .recorded))
      states[step.id] = .fatto
    }

    // 5. Esito.
    let result = try finish(
      OutcomeInput(
        hasPlan: true, stepStates: states, direction: .forward, localSkips: localSkips),
      log: log)

    // 6. Annullamento dell'utente (FR-083), solo dopo un lotto completato.
    guard undoAfter, case .finished(let outcome) = result, outcome.kind == .completato else {
      return result
    }
    try log.append(.undoRequested)
    var undone: [String: StepState] = [:]
    for step in plan.steps.reversed() {
      try log.append(.stepIntent(stepId: step.id, direction: .compensate))
      try injector.hit(CrashPoints.compensationPoint(step.id, .intent))
      let resultPath = try Steps.compensate(step, plan: plan, volume: volume)
      try injector.hit(CrashPoints.compensationPoint(step.id, .acted))
      try log.append(.stepDone(stepId: step.id, direction: .compensate, resultPath: resultPath))
      undone[step.id] = .nonFatto
    }
    try injector.hit(CrashPoints.compensationPoint(Steps.prepareStepId, .intent))
    try Steps.compensatePrepare(created: created, volume: volume)
    try injector.hit(CrashPoints.compensationPoint(Steps.prepareStepId, .acted))
    return try finish(
      OutcomeInput(hasPlan: true, stepStates: undone, direction: .compensate), log: log)
  }

  // MARK: - Fasi

  /// Divergenze del disco dal piano prima di agire; vuoto se il lotto può partire.
  ///
  /// Il volume del lotto deve essere quello del piano (altrimenti nessun'altra osservazione è
  /// affidabile), ogni passo deve risultare `.notDone` e la radice del lotto e le cartelle di
  /// destinazione esistenti devono essere scrivibili.
  static func recheck(plan: BatchPlan, volume: WorkVolume) throws -> [String] {
    if ErrorClassifier.volumeIsMissing(plan: plan, volume: volume) {
      return ["volume del lotto assente o diverso da quello del piano (\(plan.volumeUUID))"]
    }
    var divergences: [String] = []
    var readOnlyFolders: [String] = []
    for step in plan.steps {
      do {
        let observation = try Steps.observe(step, plan: plan, volume: volume)
        if observation != .notDone {
          divergences.append("\(step.id): atteso non-fatto, \(describe(observation))")
        }
      } catch let failure as StepFailure {
        divergences.append("\(step.id): osservazione fallita: \(failure)")
      }
      if let folder = ErrorClassifier.readOnlyFolder(for: step, volume: volume),
        !readOnlyFolders.contains(folder)
      {
        readOnlyFolders.append(folder)
      }
    }
    for folder in readOnlyFolders {
      divergences.append(
        "cartella non scrivibile: \(volume.volumeRelativePath(of: URL(filePath: folder)))")
    }
    return divergences
  }

  /// Crea le cartelle di `directoriesToCreate` che mancano, nell'ordine del piano, e restituisce
  /// quelle create dal lotto: solo queste la compensazione potrà rimuovere.
  static func prepare(plan: BatchPlan, volume: WorkVolume) throws -> [String] {
    var created: [String] = []
    for directory in plan.directoriesToCreate {
      let path = volume.batchURL(directory).fileSystemPath
      if mkdir(path, 0o755) == 0 {
        created.append(directory)
        continue
      }
      let code = errno
      guard code == EEXIST else {
        throw StepFailure(stepId: Steps.prepareStepId, syscall: "mkdir", errno: code, path: path)
      }
    }
    return created
  }

  /// Classifica l'esito, lo registra e lo restituisce.
  private static func finish(_ input: OutcomeInput, log: IntentLog) throws -> BatchRunResult {
    let outcome = OutcomeClassifier.classify(input)
    try log.append(outcome.record)
    return .finished(outcome)
  }

  /// `osservato fatto in <percorso>`, `osservata anomalia <posizioni>`, …
  private static func describe(_ observation: StepObservation) -> String {
    switch observation {
    case .notDone: "osservato non-fatto"
    case .done(let resultPath): "osservato fatto in \(resultPath)"
    case .partial(let tempPath): "osservato temporaneo di copia \(tempPath)"
    case .anomaly(let found): "osservata anomalia \(ErrorClassifier.describe(found))"
    }
  }
}
