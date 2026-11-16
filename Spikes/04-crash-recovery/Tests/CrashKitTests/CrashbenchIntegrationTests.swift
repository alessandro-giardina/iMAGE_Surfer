import Darwin
import Foundation
import Testing

@testable import CrashKit

/// Integrazione sul binario `crashbench` reale.
///
/// Ogni test lancia il binario come processo figlio e osserva dal padre motivo e stato della
/// terminazione: un arresto vale solo se il figlio è morto davvero per `SIGKILL`. Le asserzioni
/// cadono sul log e sul disco, letti dal padre dopo la fine del figlio, e sul JSON prodotto, non
/// soltanto sulle righe stampate. Le posizioni attese vengono dal piano di riferimento delle
/// fixture e dall'istantanea del volume, mai dal log scritto dal binario.
///
/// Ogni test ha una propria directory dati, `.data/tests/integration-<UUID>`, preparata con
/// `crashbench setup` e chiusa con `crashbench teardown`, garantito da `defer`.
@Suite(
  "Integrazione sul binario reale: SIGKILL osservato dal padre, recupero, matrice smoke",
  .serialized, .timeLimit(.minutes(10)))
struct CrashbenchIntegrationTests {
  /// Righe `COPPIA` del lotto mai toccato: ogni file nella sua origine.
  static let untouchedPairs = (1...5).map { "COPPIA OP\($0) immagine=orig sidecar=orig" }

  /// Righe `COPPIA` del lotto completato: rinomina, spostamenti e copia a destinazione, `OP5` nel
  /// Cestino del volume.
  static let completedPairs =
    (1...4).map { "COPPIA OP\($0) immagine=dest sidecar=dest" }
    + ["COPPIA OP5 immagine=cest sidecar=cest"]

  @Test(
    "run --crash-at: il figlio muore per SIGKILL nel punto e lascia log e disco dichiarati",
    arguments: ["X01-plan", "S03-b", "S07-m", "S09-b", "K05-a"])
  func realKillLeavesDeclaredState(point: String) throws {
    let bench = try IntegrationBench()
    defer { bench.close() }
    let run = try bench.crashbench(["run", "--crash-at", point])
    try expectKilled(run, at: point)

    let reference = try referencePlan()
    let (records, plan) = try loggedRecords(bench.log)
    #expect(plan.steps == reference.steps, "piano registrato diverso da quello delle fixture")
    let disk = try bench.snapshot()

    switch point {
    case "X01-plan":
      #expect(records == [.plan(plan)], "ultimo record: \(String(describing: records.last))")
      // Nessun file mosso e nessuna cartella creata: il disco è quello salvato prima del lotto.
      let pre = try Snapshot.load(from: BatchExecutor.preSnapshotURL(in: bench.volume))
      #expect(Snapshot.diff(pre, disk) == [])
      #expect(SnapshotOracle.pairLines(disk, plan: reference) == Self.untouchedPairs)

    case "S03-b":
      #expect(records.last == .stepIntent(stepId: "S03", direction: .forward))
      let s03 = try #require(reference.step("S03"))
      #expect(disk.entries[SnapshotOracle.batchKey("selezione/IMG_0002.jpg")]?.sha256 == s03.sha256)
      #expect(disk.entries[SnapshotOracle.batchKey("IMG_0002.jpg")] == nil)

    case "S07-m":
      #expect(records.last == .stepIntent(stepId: "S07", direction: .forward))
      let s07 = try #require(reference.step("S07"))
      let delivery = try FileManager.default.contentsOfDirectory(
        atPath: bench.volume.batchURL("consegna").fileSystemPath)
      let partials = delivery.filter { $0.hasPrefix(".IMG_0004.jpg.partial-") }
      #expect(partials == [".IMG_0004.jpg.partial-\(plan.planId.uuidString)"], "\(delivery)")
      // Il temporaneo è già completo: manca solo la pubblicazione.
      for partial in partials {
        #expect(disk.entries[SnapshotOracle.batchKey("consegna/\(partial)")]?.sha256 == s07.sha256)
      }
      #expect(!delivery.contains("IMG_0004.jpg"))

    case "S09-b":
      #expect(records.last == .stepIntent(stepId: "S09", direction: .forward))
      let s09 = try #require(reference.step("S09"))
      #expect(
        !FileManager.default.fileExists(
          atPath: bench.volume.batchURL("IMG_0005.jpg").fileSystemPath))
      let trash = bench.volume.mountPoint.appending(
        path: ".Trashes/\(getuid())", directoryHint: .isDirectory)
      let entries = try FileManager.default.contentsOfDirectory(
        at: trash, includingPropertiesForKeys: [.isRegularFileKey])
      let withDigest = try entries.filter { entry in
        try entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
          && Fixtures.sha256Hex(ofFileAt: entry) == s09.sha256
      }
      #expect(withDigest.count == 1, "voci del Cestino: \(entries.map(\.lastPathComponent))")

    case "K05-a":
      #expect(records.last == .stepIntent(stepId: "S05", direction: .compensate))
      let completed = try #require(
        records.firstIndex { record in
          if case .outcome(let outcome, _, _) = record {
            outcome == OutcomeKind.completato.rawValue
          } else {
            false
          }
        }, "nessun outcome completato nel log")
      #expect(records.indices.contains(completed + 1) && records[completed + 1] == .undoRequested)
      // S06 è già compensato, S05 no: il sidecar di OP3 è tornato in origine, l'immagine no.
      let s05 = try #require(reference.step("S05"))
      let s06 = try #require(reference.step("S06"))
      #expect(SnapshotOracle.position(of: s05, in: disk) == "dest")
      #expect(SnapshotOracle.position(of: s06, in: disk) == "orig")

    default:
      Issue.record("punto senza attese: \(point)")
    }
  }

  @Test(
    "record troncato del piano: il recupero esce con 0 e riferisce NON_SUPPORTABILE, non bloccato")
  func tornPlanRecordIsNotSupportable() throws {
    let bench = try IntegrationBench()
    defer { bench.close() }
    try expectKilled(
      try bench.crashbench(["run", "--crash-at", "X00-plan-torn"]), at: "X00-plan-torn")

    let raw = try Data(contentsOf: bench.log.url)
    #expect(!raw.isEmpty, "log vuoto dopo l'arresto")
    #expect(raw.last != UInt8(ascii: "\n"), "l'ultimo frammento termina con un a capo")
    #expect(!raw.contains(UInt8(ascii: "\n")), "righe complete prima del piano troncato")
    let torn = try bench.log.read()
    #expect(torn.records.isEmpty)
    #expect(torn.tornTail == String(decoding: raw, as: UTF8.self))

    let recovery = try bench.crashbench(["recover", "--strategy", "resume"])
    expectExited(recovery)
    let printed = lines(recovery.stdout)
    #expect(
      printed == [
        "RECUPERO strategia=resume direzione=nessuna",
        "RECORD-TRONCATO si",
        "SEPARAZIONI-ALL-AVVIO nessuna",
        "SEPARAZIONI-RESIDUE nessuna",
        "ESITO NON_SUPPORTABILE motivo=nessun-esito-applicabile",
        "TRACCIA \(OutcomeClassifier.noPlanTrace)",
      ])
    #expect(!printed.contains { $0.hasPrefix("ESITO bloccato") })

    // Il frammento è conservato come evidenza nella directory di stato, e il log è riparato.
    let prefix = "record troncato riparato: evidenza in "
    let declared = try #require(lines(recovery.stderr).first { $0.hasPrefix(prefix) })
    let evidence = URL(filePath: String(declared.dropFirst(prefix.count)))
    #expect(
      evidence.deletingLastPathComponent().fileSystemPath
        == bench.volume.stateDirectory.fileSystemPath)
    #expect(try Data(contentsOf: evidence) == raw)
    let repaired = try bench.log.read()
    #expect(repaired.tornTail == nil)
    #expect(repaired.records.map(\.kind) == [.recovery, .outcome])
    #expect(
      repaired.records.last
        == .outcome(
          outcome: OutcomeKind.nonSupportabile.rawValue,
          reason: OutcomeReason.nessunEsitoApplicabile.rawValue,
          trace: [OutcomeClassifier.noPlanTrace]))
    #expect(
      SnapshotOracle.pairLines(try bench.snapshot(), plan: try referencePlan())
        == Self.untouchedPairs)
  }

  @Test("ripresa in un nuovo processo dopo S03-b: completato, cinque coppie riunite come sul disco")
  func resumeInNewProcessCompletes() throws {
    let bench = try IntegrationBench()
    defer { bench.close() }
    try expectKilled(try bench.crashbench(["run", "--crash-at", "S03-b"]), at: "S03-b")
    let reference = try referencePlan()
    let atCrash = SnapshotOracle.pairLines(try bench.snapshot(), plan: reference)
    #expect(separations(atCrash) == ["OP2"], "\(atCrash)")

    let recovery = try bench.crashbench(["recover", "--strategy", "resume"])
    expectExited(recovery)
    let printed = lines(recovery.stdout)
    #expect(printed.first == "RECUPERO strategia=resume direzione=forward")
    #expect(
      printed.contains("SEPARAZIONI-ALL-AVVIO \(separations(atCrash).joined(separator: ","))"))
    #expect(printed.contains("ESITO completato"))
    let pairs = printed.filter { $0.hasPrefix("COPPIA ") }
    #expect(pairs.count == 5)
    #expect(!pairs.contains { $0.contains("SEPARATA") })

    // Le posizioni stampate sono quelle del disco dopo il recupero, e sono quelle del lotto
    // completato.
    let after = SnapshotOracle.pairLines(try bench.snapshot(), plan: reference)
    #expect(pairs == after)
    #expect(after == Self.completedPairs)
    #expect(
      try loggedRecords(bench.log).records.last
        == .outcome(outcome: OutcomeKind.completato.rawValue, reason: nil, trace: []))
  }

  @Test("compensazione dopo S03-c: la separazione di OP2 è riferita all'avvio e non resta")
  func compensationReportsAndHealsSeparation() throws {
    let bench = try IntegrationBench()
    defer { bench.close() }
    try expectKilled(try bench.crashbench(["run", "--crash-at", "S03-c"]), at: "S03-c")
    let reference = try referencePlan()
    let atCrash = SnapshotOracle.pairLines(try bench.snapshot(), plan: reference)
    #expect(atCrash.contains("COPPIA OP2 immagine=dest sidecar=orig SEPARATA"), "\(atCrash)")
    #expect(separations(atCrash) == ["OP2"])

    let recovery = try bench.crashbench(["recover", "--strategy", "compensate"])
    expectExited(recovery)
    let printed = lines(recovery.stdout)
    #expect(printed.first == "RECUPERO strategia=compensate direzione=compensate")
    #expect(printed.contains("SEPARAZIONI-ALL-AVVIO OP2"))
    #expect(printed.contains("ESITO compensato"))
    #expect(printed.contains("SEPARAZIONI-RESIDUE nessuna"))

    let disk = try bench.snapshot()
    let after = SnapshotOracle.pairLines(disk, plan: reference)
    #expect(printed.filter { $0.hasPrefix("COPPIA ") } == after)
    #expect(after == Self.untouchedPairs)
    // Lo stato dopo la compensazione coincide con quello prima del lotto, salvo l'mtime della
    // cartella `lotto`, che ha visto creare e rimuovere `selezione/` e `consegna/`.
    let pre = try Snapshot.load(from: BatchExecutor.preSnapshotURL(in: bench.volume))
    let deviations = Snapshot.diff(pre, disk)
    #expect(deviations.filter { !$0.isDirectoryMtime } == [], "\(deviations)")
    #expect(deviations.allSatisfy { $0.path == Snapshot.batchKey }, "\(deviations)")
    #expect(
      try loggedRecords(bench.log).records.last
        == .outcome(outcome: OutcomeKind.compensato.rawValue, reason: nil, trace: []))
  }

  @Test("doppio arresto D01: il primo recupero muore per SIGKILL a S08-b, il secondo completa")
  func doubleCrashThenCompletes() throws {
    let bench = try IntegrationBench()
    defer { bench.close() }
    let pending = CompositeCrash.pendingURL(in: bench.volume).fileSystemPath
    let doubleLine = "DOPPIO-ARRESTO D01 primo=S03-b secondo=S08-b strategia=resume"

    let first = try bench.crashbench(["run", "--crash-at", "D01"])
    try expectKilled(first, at: "S03-b")
    #expect(lines(first.stdout).first == doubleLine)
    #expect(FileManager.default.fileExists(atPath: pending))

    let interrupted = try bench.crashbench(["recover", "--strategy", "resume"])
    try expectKilled(interrupted, at: "S08-b")
    #expect(
      Array(lines(interrupted.stdout).prefix(2))
        == [doubleLine, "RECUPERO strategia=resume direzione=forward"])
    #expect(!FileManager.default.fileExists(atPath: pending), "secondo arresto non consumato")
    // Il secondo arresto è caduto dopo l'azione di S08 e prima del suo fatto.
    #expect(
      try loggedRecords(bench.log).records.last == .stepIntent(stepId: "S08", direction: .forward))
    let reference = try referencePlan()
    let s08 = try #require(reference.step("S08"))
    #expect(
      try bench.snapshot().entries[SnapshotOracle.batchKey("consegna/IMG_0004.xmp")]?.sha256
        == s08.sha256)

    let resumed = try bench.crashbench(["recover", "--strategy", "resume"])
    expectExited(resumed)
    let printed = lines(resumed.stdout)
    #expect(printed.first == "RECUPERO strategia=resume direzione=forward")
    #expect(printed.contains("ESITO completato"))
    let after = SnapshotOracle.pairLines(try bench.snapshot(), plan: reference)
    #expect(printed.filter { $0.hasPrefix("COPPIA ") } == after)
    #expect(after == Self.completedPairs)
  }

  @Test("run-matrix --profile smoke: JSON conforme allo schema, ogni punto raggiunto")
  func smokeMatrixWritesConformingMeasurement() throws {
    let bench = try IntegrationBench()
    defer { bench.close() }
    // `--out` come directory: il binario nomina il file con il `measurementId` della misura.
    let output = bench.dataDirectory.appending(path: "smoke", directoryHint: .isDirectory)
    let matrix = try bench.crashbench(
      ["run-matrix", "--profile", "smoke", "--out", output.fileSystemPath + "/"])
    expectExited(matrix)

    let files = try FileManager.default.contentsOfDirectory(
      at: output, includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "json" }
    let file = try #require(files.count == 1 ? files.first : nil, "JSON scritti: \(files)")
    let fileName = file.lastPathComponent
    #expect(lines(matrix.stdout).contains("JSON \(output.fileSystemPath)/\(fileName)"))
    let data = try Data(contentsOf: file)
    let result = try JSONDecoder().decode(MeasurementResult.self, from: data)
    // Nessuna chiave fuori schema: la ricodifica canonica riproduce il file byte per byte.
    #expect(try result.jsonData() == data)

    #expect(result.measurementId == file.deletingPathExtension().lastPathComponent)
    #expect(MeasurementResult.isValidMeasurementId(result.measurementId))
    #expect(result.spike == MeasurementResult.spikeName)
    #expect(result.profile == .smoke)
    #expect(result.repetitions == MatrixProfile.smoke.defaultRepetitions)
    #expect(result.fixtureManifestSha256 == (try MeasurementResult.fixtureManifestDigest()))
    let points = try CrashPoints.fixturePoints()
    #expect(result.points.count == 61)
    #expect(result.points == points)
    #expect(result.cells.map(\.cellId) == Matrix.cells(points: points, profile: .smoke).map(\.id))
    #expect(result.coverage.complete)
    #expect(result.summary.pointNotReachedCells == 0)
    #expect(result.summary.benchErrorCells == 0)

    for cell in result.cells where cell.applicable {
      #expect(cell.repetitions == result.repetitions, "\(cell.cellId)")
      #expect(cell.outcomes.values.reduce(0, +) == result.repetitions, "\(cell.cellId)")
      #expect(cell.pointReached, "\(cell.cellId)")
      #expect(cell.benchErrors.isEmpty, "\(cell.cellId): \(cell.benchErrors)")
    }
    #expect(result.cells.contains { $0.compensation.attempted })
    #expect(result.cells.contains { !$0.separationsAtCrash.isEmpty })
  }
}

// MARK: - Aiuti

/// Directory dati di un test sul binario, `.data/tests/integration-<UUID>`, con il volume montato
/// da `crashbench setup`. Chi la apre chiama `defer { bench.close() }`.
private struct IntegrationBench {
  let dataDirectory: URL
  /// Gli stessi percorsi che il binario usa con questa directory dati, per leggere log e disco
  /// dal processo padre.
  let volume: WorkVolume

  init() throws {
    dataDirectory = CrashPaths.defaultDataDirectory
      .appending(path: "tests/integration-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    volume = WorkVolume(dataDirectory: dataDirectory)
    do {
      let setup = try crashbench(["setup"])
      try #require(
        setup.reason == .exit && setup.status == 0, "crashbench setup: \(setup.stderr)")
      try #require(volume.isMounted, "volume non montato dopo crashbench setup")
    } catch {
      close()
      throw error
    }
  }

  var log: IntentLog { IntentLog(volume: volume) }

  func crashbench(_ args: [String]) throws -> CrashbenchResult {
    try runCrashbench(args, dataDir: dataDirectory)
  }

  func snapshot() throws -> Snapshot {
    try Snapshot.capture(volume: volume)
  }

  /// `crashbench teardown`, poi rimozione della directory dati. Se il volume resta montato la
  /// directory non viene rimossa, perché la rimozione scenderebbe nel volume, e il test fallisce.
  func close() {
    do {
      let teardown = try crashbench(["teardown"])
      if teardown.reason != .exit || teardown.status != 0 {
        Issue.record("crashbench teardown: stato \(teardown.status): \(teardown.stderr)")
      }
    } catch {
      Issue.record("crashbench teardown non eseguito: \(error)")
    }
    guard !volume.isMounted else {
      Issue.record("volume di prova ancora montato: \(volume.mountPoint.fileSystemPath)")
      return
    }
    do {
      try FileManager.default.removeItem(at: dataDirectory)
    } catch {
      Issue.record("rimozione della directory dati di prova fallita: \(error)")
    }
  }
}

/// Piano di riferimento delle fixture, costruito senza volume e senza il log.
private func referencePlan() throws -> BatchPlan {
  try CrashPoints.referencePlan(
    definition: BatchDefinition.load(
      from: CrashPaths.fixtures.appending(
        path: Fixtures.batchFileName, directoryHint: .notDirectory)))
}

/// Righe non vuote di un'uscita.
private func lines(_ text: String) -> [String] {
  text.split(separator: "\n").map(String.init)
}

/// Operazioni delle righe `COPPIA … SEPARATA`, in ordine.
private func separations(_ pairLines: [String]) -> [String] {
  pairLines.filter { $0.hasSuffix(" SEPARATA") }.map {
    String($0.split(separator: " ")[1])
  }
}

/// Il figlio è morto per `SIGKILL` nel punto `point`, osservato dal padre, con la riga
/// `ARRESTO <point>: <descrizione>` per ultima e nessuna riga `ESITO`.
private func expectKilled(
  _ result: CrashbenchResult, at point: String,
  sourceLocation: SourceLocation = #_sourceLocation
) throws {
  #expect(
    result.reason == .uncaughtSignal,
    "motivo \(result.reason.rawValue), stato \(result.status), stderr: \(result.stderr)",
    sourceLocation: sourceLocation)
  #expect(result.status == SIGKILL, sourceLocation: sourceLocation)
  let description = try #require(
    try CrashPoints.fixturePoints().first { $0.id == point }?.description,
    "punto sconosciuto: \(point)", sourceLocation: sourceLocation)
  let printed = lines(result.stdout)
  #expect(
    printed.last == "ARRESTO \(point): \(description)", "\(printed)",
    sourceLocation: sourceLocation)
  #expect(
    !printed.contains { $0.hasPrefix("ESITO ") }, "\(printed)", sourceLocation: sourceLocation)
}

/// Il figlio è uscito da sé con stato 0.
private func expectExited(
  _ result: CrashbenchResult, sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(
    result.reason == .exit && result.status == 0,
    "motivo \(result.reason.rawValue), stato \(result.status), stderr: \(result.stderr)",
    sourceLocation: sourceLocation)
}

/// I record del log letti dal padre, con il piano del primo record. Il log non ha code troncate,
/// e ogni `step-done` segue subito il proprio `step-intent`: l'intento è scritto prima
/// dell'azione.
private func loggedRecords(
  _ log: IntentLog, sourceLocation: SourceLocation = #_sourceLocation
) throws -> (records: [IntentLog.Record], plan: BatchPlan) {
  let (records, tornTail) = try log.read()
  #expect(tornTail == nil, "coda troncata: \(tornTail ?? "")", sourceLocation: sourceLocation)
  guard case .plan(let plan)? = records.first else {
    Issue.record("il primo record del log non è il piano", sourceLocation: sourceLocation)
    throw IntegrationError.missingPlan
  }
  for (index, record) in records.enumerated() {
    guard case .stepDone(let stepId, let direction, _) = record else { continue }
    #expect(
      index > 0 && records[index - 1] == .stepIntent(stepId: stepId, direction: direction),
      "step-done di \(stepId) (\(direction.rawValue)) senza il proprio intento subito prima",
      sourceLocation: sourceLocation)
  }
  return (records, plan)
}

private enum IntegrationError: Error {
  case missingPlan
}
