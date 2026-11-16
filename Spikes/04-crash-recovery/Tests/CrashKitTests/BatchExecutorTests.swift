import Darwin
import Foundation
import Testing

@testable import CrashKit

private func fixtureDefinition() throws -> BatchDefinition {
  try BatchDefinition.load(
    from: CrashPaths.fixtures.appending(path: Fixtures.batchFileName, directoryHint: .notDirectory))
}

/// File della cartella del lotto nell'istantanea: percorso → digest.
private func batchFiles(_ snapshot: Snapshot) -> [String: String] {
  snapshot.entries.reduce(into: [:]) { files, item in
    if item.key.hasPrefix(Snapshot.batchKey + "/"), item.value.kind == .file {
      files[item.key] = item.value.sha256
    }
  }
}

/// Percorso della voce di un file del lotto nell'istantanea: `lotto/<relativo a lotto/>`.
private func batchKey(_ relativePath: String) -> String {
  "\(Snapshot.batchKey)/\(relativePath)"
}

/// Record del log, per i test: l'ultimo record completo e la coda troncata.
private func readLog(_ log: IntentLog) -> (records: [IntentLog.Record], tornTail: String?) {
  do {
    return try log.read()
  } catch {
    Issue.record("lettura del log fallita: \(error)")
    return ([], nil)
  }
}

/// Macchina a stati del lotto sul volume di lavoro, in-process: l'iniettore lancia
/// `SimulatedCrash` al posto di `SIGKILL`, e ogni test monta un proprio volume.
@Suite("Macchina a stati del lotto: log prima dell'azione, ricontrollo e annullamento", .serialized)
struct BatchExecutorTests {
  @Test("senza arresto il lotto si chiude completato, con il log nell'ordine delle fasi")
  func fullRunIsCompletedWithOrderedLog() throws {
    let test = try TestVolume(name: "executor-completo")
    defer { test.close() }
    let volume = test.volume
    let log = IntentLog(volume: volume)
    let plan = try BatchPlan.make(definition: fixtureDefinition(), volume: volume)
    var seen: [String] = []
    let injector = CrashInjector(target: nil, mode: .throwForTest, observer: { seen.append($0) })

    let result = try BatchExecutor.run(plan: plan, volume: volume, log: log, injector: injector)

    #expect(result == .finished(Outcome(kind: .completato)))
    #expect(result.line == "ESITO completato")
    let (records, tornTail) = try log.read()
    #expect(tornTail == nil)
    let pairs = [IntentLog.Record.Kind](repeating: .stepIntent, count: plan.steps.count)
      .flatMap { [$0, .stepDone] }
    try #require(records.map(\.kind) == [.plan, .recheck, .prepare] + pairs + [.outcome])
    #expect(records[0] == .plan(plan))
    #expect(records[1] == .recheck(ok: true))
    #expect(records[2] == .prepare(created: ["selezione", "consegna"]))
    for (index, step) in plan.steps.enumerated() {
      #expect(records[3 + 2 * index] == .stepIntent(stepId: step.id, direction: .forward))
      guard case .stepDone(let id, .forward, let resultPath) = records[4 + 2 * index] else {
        Issue.record("record \(4 + 2 * index) non è uno step-done in avanti")
        continue
      }
      #expect(id == step.id)
      if let destination = step.destination {
        #expect(resultPath == batchKey(destination))
      } else {
        // Il Cestino sceglie il nome della voce: conta che sia nel Cestino del volume.
        #expect(resultPath.hasPrefix(".Trashes/\(getuid())/"))
      }
    }
    #expect(records.last == .outcome(outcome: "completato"))

    // Ogni punto di esecuzione dell'elenco, salvo i record troncati, è raggiunto nell'ordine.
    let points = CrashPoints.enumerate(plan)
    #expect(
      seen
        == points.filter { $0.phase == .esecuzione && !CrashPoints.tornPoints.contains($0.id) }
        .map(\.id))

    // L'elenco di `list-points`, ricavato senza volume, è quello del piano costruito sul volume.
    let reference = try CrashPoints.referencePlan(definition: fixtureDefinition())
    #expect(reference.steps == plan.steps)
    #expect(reference.directoriesToCreate == plan.directoriesToCreate)
    #expect(try CrashPoints.fixturePoints() == points)
  }

  @Test("l'intento precede l'azione: a Sxx-a il file è in origine, a Sxx-b il fatto manca ancora")
  func intentPrecedesAction() throws {
    let test = try TestVolume(name: "executor-intento")
    defer { test.close() }
    let volume = test.volume
    let log = IntentLog(volume: volume)
    let plan = try BatchPlan.make(definition: fixtureDefinition(), volume: volume)
    var checkedIntents: [String] = []
    var checkedActions: [String] = []

    let observer: (String) -> Void = { id in
      guard let step = plan.steps.first(where: { id.hasPrefix($0.id + "-") }) else { return }
      let lastRecord = readLog(log).records.last
      do {
        let snapshot = try Snapshot.capture(volume: volume)
        let source = snapshot.entries[batchKey(step.source)]
        switch id {
        case CrashPoints.point(step.id, .intent):
          // L'intento è sul disco, e il file del passo è ancora nella posizione di origine.
          #expect(lastRecord == .stepIntent(stepId: step.id, direction: .forward), "\(id)")
          #expect(source?.sha256 == step.sha256, "\(id): file non più in origine")
          if let destination = step.destination {
            #expect(snapshot.entries[batchKey(destination)] == nil, "\(id): arrivo occupato")
          }
          checkedIntents.append(step.id)
        case CrashPoints.point(step.id, .acted):
          // L'azione è eseguita, e il log ha ancora l'intento come ultimo record.
          #expect(lastRecord == .stepIntent(stepId: step.id, direction: .forward), "\(id)")
          if let destination = step.destination {
            #expect(snapshot.entries[batchKey(destination)]?.sha256 == step.sha256, "\(id)")
          }
          if step.kind != .copy {
            #expect(source == nil, "\(id): file ancora in origine")
          }
          checkedActions.append(step.id)
        default:
          break
        }
      } catch {
        Issue.record("istantanea fallita al punto \(id): \(error)")
      }
    }

    let result = try BatchExecutor.run(
      plan: plan, volume: volume, log: log,
      injector: CrashInjector(target: nil, mode: .throwForTest, observer: observer))

    #expect(result.kind == "completato")
    #expect(checkedIntents == plan.steps.map(\.id))
    #expect(checkedActions == plan.steps.map(\.id))
  }

  @Test("un ricontrollo divergente interrompe prima di agire, e nessun file si muove (FR-080)")
  func divergentRecheckInterruptsBeforeActing() throws {
    let test = try TestVolume(name: "executor-ricontrollo")
    defer { test.close() }
    let volume = test.volume
    let log = IntentLog(volume: volume)
    let plan = try BatchPlan.make(definition: fixtureDefinition(), volume: volume)
    var seen: [String] = []
    var afterChange: Snapshot?

    let result = try BatchExecutor.run(
      plan: plan, volume: volume, log: log,
      injector: CrashInjector(target: nil, mode: .throwForTest, observer: { seen.append($0) }),
      beforeRecheck: {
        // Un byte di IMG_0002.jpg cambia fra la registrazione del piano e il ricontrollo.
        let handle = try FileHandle(forUpdating: volume.batchURL("IMG_0002.jpg"))
        try handle.seek(toOffset: 100)
        let byte = try handle.read(upToCount: 1) ?? Data([0])
        try handle.seek(toOffset: 100)
        try handle.write(contentsOf: Data([byte[byte.startIndex] ^ 0xFF]))
        try handle.close()
        afterChange = try Snapshot.capture(volume: volume)
      })

    guard case .interruptedBeforeActing(let divergences) = result else {
      Issue.record("atteso interrotto-prima-di-agire, ottenuto \(result)")
      return
    }
    #expect(result.line == "ESITO interrotto-prima-di-agire")
    #expect(divergences.count == 1)
    #expect(divergences.first?.hasPrefix("S03: atteso non-fatto, osservata anomalia") == true)
    #expect(
      try log.read().records == [
        .plan(plan), .recheck(ok: false, divergences: divergences),
        .outcome(outcome: BatchExecutor.interruptedBeforeActing, trace: divergences),
      ])
    #expect(seen == [CrashPoints.planRecorded])

    // Nessun file si è mosso e nessuna cartella è stata creata: il disco è quello del gancio.
    let after = try Snapshot.capture(volume: volume)
    let changed = try #require(afterChange)
    let deviations = Snapshot.diff(changed, after)
    #expect(deviations.isEmpty, "scostamenti: \(deviations)")
    #expect(after.entries[batchKey("selezione")] == nil)
    #expect(after.entries[batchKey("consegna")] == nil)
  }

  @Test("con l'annullamento e senza arresto l'esito finale è compensato")
  func undoAfterCompletionIsCompensated() throws {
    let test = try TestVolume(name: "executor-annullamento")
    defer { test.close() }
    let volume = test.volume
    let log = IntentLog(volume: volume)
    let pre = try Snapshot.capture(volume: volume)
    let plan = try BatchPlan.make(definition: fixtureDefinition(), volume: volume)
    var seen: [String] = []

    let result = try BatchExecutor.run(
      plan: plan, volume: volume, log: log,
      injector: CrashInjector(target: nil, mode: .throwForTest, observer: { seen.append($0) }),
      undoAfter: true)

    #expect(result == .finished(Outcome(kind: .compensato)))
    let records = try log.read().records
    guard let completed = records.firstIndex(of: .outcome(outcome: "completato")) else {
      Issue.record("manca l'esito completato prima dell'annullamento: \(records)")
      return
    }
    let undo = Array(records[(completed + 1)...])
    #expect(undo.first == .undoRequested)
    #expect(undo.last == .outcome(outcome: "compensato"))
    let intents = undo.compactMap { record -> String? in
      if case .stepIntent(let id, .compensate) = record { id } else { nil }
    }
    let dones = undo.compactMap { record -> String? in
      if case .stepDone(let id, .compensate, _) = record { id } else { nil }
    }
    #expect(intents == plan.steps.reversed().map(\.id))
    #expect(dones == intents)
    #expect(undo.count == 1 + 2 * plan.steps.count + 1)

    // I punti di compensazione sono raggiunti nell'ordine dell'elenco.
    let compensation = CrashPoints.enumerate(plan).filter { $0.phase == .compensazione }.map(\.id)
    #expect(Array(seen.suffix(compensation.count)) == compensation)

    // Ogni file del lotto è tornato in origine con il suo digest; le cartelle create sono rimosse.
    let post = try Snapshot.capture(volume: volume)
    #expect(batchFiles(post) == batchFiles(pre))
    #expect(post.entries[batchKey("selezione")] == nil)
    #expect(post.entries[batchKey("consegna")] == nil)
  }

  @Test(
    "l'arresto simulato lascia log e disco nello stato del punto",
    arguments: ["X00-plan-torn", "X01-plan", "S03-b", "S05-torn", "S07-m", "S09-b", "K05-a"])
  func simulatedCrashLeavesTheDeclaredState(point: String) throws {
    let test = try TestVolume(name: "executor-arresto-\(point)")
    defer { test.close() }
    let volume = test.volume
    let log = IntentLog(volume: volume)
    let pre = try Snapshot.capture(volume: volume)
    let plan = try BatchPlan.make(definition: fixtureDefinition(), volume: volume)
    let phase = try #require(CrashPoints.enumerate(plan).first { $0.id == point }?.phase)

    #expect(throws: SimulatedCrash(point)) {
      try BatchExecutor.run(
        plan: plan, volume: volume, log: log,
        injector: CrashInjector(target: point, mode: .throwForTest),
        undoAfter: phase == .compensazione)
    }

    let (records, tornTail) = try log.read()
    let files = batchFiles(try Snapshot.capture(volume: volume))
    switch point {
    case "X00-plan-torn":
      #expect(records.isEmpty)
      #expect(tornTail?.hasPrefix("{\"plan\":") == true)
      #expect(files == batchFiles(pre))
    case "X01-plan":
      #expect(records == [.plan(plan)])
      #expect(tornTail == nil)
      #expect(files == batchFiles(pre))
    case "S03-b":
      #expect(records.last == .stepIntent(stepId: "S03", direction: .forward))
      #expect(files[batchKey("selezione/IMG_0002.jpg")] == plan.step("S03")?.sha256)
      #expect(files[batchKey("IMG_0002.jpg")] == nil)
    case "S05-torn":
      #expect(records.last == .stepIntent(stepId: "S05", direction: .forward))
      #expect(tornTail?.hasPrefix("{\"direction\":\"forward\"") == true)
      #expect(files[batchKey("selezione/2026-08-24_evento_003.jpg")] == plan.step("S05")?.sha256)
    case "S07-m":
      #expect(records.last == .stepIntent(stepId: "S07", direction: .forward))
      let temp = try #require(
        plan.step("S07").flatMap { Steps.tempURL(for: $0, plan: plan, volume: volume) })
      #expect(files[batchKey("consegna/\(temp.lastPathComponent)")] == plan.step("S07")?.sha256)
      #expect(files[batchKey("consegna/IMG_0004.jpg")] == nil)
    case "S09-b":
      #expect(records.last == .stepIntent(stepId: "S09", direction: .forward))
      #expect(files[batchKey("IMG_0005.jpg")] == nil)
      let step = try #require(plan.step("S09"))
      #expect(
        try Steps.trashEntries(withDigest: step.sha256, stepId: step.id, volume: volume).count == 1)
    case "K05-a":
      #expect(records.last == .stepIntent(stepId: "S05", direction: .compensate))
      let completed = try #require(records.firstIndex(of: .outcome(outcome: "completato")))
      #expect(records[completed + 1] == .undoRequested)
      // S06 è già compensato, S05 non ancora.
      #expect(files[batchKey("IMG_0003.xmp")] == plan.step("S06")?.sha256)
      #expect(files[batchKey("selezione/2026-08-24_evento_003.jpg")] == plan.step("S05")?.sha256)
    default:
      Issue.record("punto senza attese: \(point)")
    }
  }
}
