import Darwin
import Foundation
import Testing

@testable import CrashKit

/// Lotto della fixture sul volume di un test, interrotto in un punto dall'esecutore con
/// l'iniettore di prova: al posto di `SIGKILL` l'iniettore lancia `SimulatedCrash`, e l'esecutore
/// non ha pulizie che scrivano sul log o sul disco, quindi il disco resta quello dell'arresto.
///
/// Usato da `RecognizerTests` e da `RecoveryScenarioTests`.
struct CrashedBatch {
  let volume: WorkVolume
  let log: IntentLog
  let plan: BatchPlan
  /// Istantanea presa prima del lotto, dopo `beforeBatch`.
  let pre: Snapshot

  /// - Parameters:
  ///   - point: un punto della fase di esecuzione, per esempio `S03-b` o `X00-plan-torn`.
  ///   - beforeBatch: modifica il volume prima dell'istantanea `pre` e del piano.
  init(
    volume: WorkVolume, crashAt point: String, beforeBatch: () throws -> Void = {}
  ) throws {
    try beforeBatch()
    let log = IntentLog(volume: volume)
    let pre = try Snapshot.capture(volume: volume)
    let plan = try BatchPlan.make(
      definition: BatchDefinition.load(
        from: CrashPaths.fixtures.appending(
          path: Fixtures.batchFileName, directoryHint: .notDirectory)),
      volume: volume)
    let crash = try #require(throws: SimulatedCrash.self) {
      try BatchExecutor.run(
        plan: plan, volume: volume, log: log,
        injector: CrashInjector(target: point, mode: .throwForTest))
    }
    try #require(crash.pointId == point, "arresto a \(crash.pointId), atteso a \(point)")
    self.volume = volume
    self.log = log
    self.plan = plan
    self.pre = pre
  }

  func step(_ id: String) throws -> PlannedStep {
    try #require(plan.step(id), "passo \(id) assente dal piano")
  }

  /// Riconoscimento dal disco, come lo fa il recupero all'avvio.
  func recognize(_ strategy: RecoveryStrategy = .resume) throws -> RecognizedState {
    try Recognizer.recognize(log: log, volume: volume, requestedStrategy: strategy)
  }

  /// Copia un file del volume, con percorsi relativi al punto di montaggio.
  func copy(_ from: String, to: String) throws {
    try FileManager.default.copyItem(at: volume.volumeURL(from), to: volume.volumeURL(to))
  }
}

/// Oracolo delle posizioni calcolato dal banco sull'istantanea, senza il riconoscitore: la
/// posizione di un file è dove si trova il file con il digest del piano.
///
/// Regola dichiarata in TASK-06: si contano l'origine, la destinazione e, per un `trash`, ogni voce
/// di primo livello del Cestino con il digest; nessuna → `ass`, una → quella, più d'una → `amb`.
/// Per una copia vale `dest` se la destinazione ha il digest. Le righe sono formattate qui, non con
/// `PairPositions.line`, così che anche il formato stampato sia verificato.
enum SnapshotOracle {
  /// Voce dell'istantanea per un percorso relativo a `lotto/`.
  static func batchKey(_ relativePath: String) -> String {
    "\(Snapshot.batchKey)/\(relativePath)"
  }

  /// Voci di primo livello del Cestino che sono file con il digest dato, ordinate.
  static func trashKeys(withDigest sha256: String, in snapshot: Snapshot) -> [String] {
    snapshot.entries.filter { key, entry in
      key.hasPrefix(Snapshot.trashKey + "/")
        && !key.dropFirst(Snapshot.trashKey.count + 1)
          .contains("/")
        && entry.kind == .file && entry.sha256 == sha256
    }.keys.sorted()
  }

  /// `orig`, `dest`, `cest`, `ass` o `amb`.
  static func position(of step: PlannedStep, in snapshot: Snapshot) -> String {
    var positions: [String] = []
    if snapshot.entries[batchKey(step.source)]?.sha256 == step.sha256 { positions.append("orig") }
    if let destination = step.destination,
      snapshot.entries[batchKey(destination)]?.sha256 == step.sha256
    {
      positions.append("dest")
    }
    if step.kind == .trash {
      positions += trashKeys(withDigest: step.sha256, in: snapshot).map { _ in "cest" }
    }
    if step.kind == .copy, positions.contains("dest") { return "dest" }
    switch positions.count {
    case 0: return "ass"
    case 1: return positions[0]
    default: return "amb"
    }
  }

  /// `COPPIA <op> immagine=<pos> sidecar=<pos>[ SEPARATA]` per ogni operazione, in ordine di piano.
  static func pairLines(_ snapshot: Snapshot, plan: BatchPlan) -> [String] {
    var opIds: [String] = []
    for step in plan.steps where !opIds.contains(step.opId) { opIds.append(step.opId) }
    return opIds.compactMap { opId in
      let members = plan.steps.filter { $0.opId == opId }
      guard
        let image = members.first(where: { $0.source.hasSuffix(".jpg") }),
        let sidecar = members.first(where: { $0.source.hasSuffix(".xmp") })
      else { return nil }
      let imagePosition = position(of: image, in: snapshot)
      let sidecarPosition = position(of: sidecar, in: snapshot)
      return "COPPIA \(opId) immagine=\(imagePosition) sidecar=\(sidecarPosition)"
        + (imagePosition == sidecarPosition ? "" : " SEPARATA")
    }
  }
}

/// Riconoscimento dello stato dal disco dopo un arresto: ogni stato è prodotto dall'esecutore
/// interrotto con l'iniettore di prova, poi modificato a mano sul disco. Ogni test monta un proprio
/// volume, in serie.
@Suite(
  "Riconoscimento dal disco: il disco prevale sul log, posizioni e record troncato", .serialized)
struct RecognizerTests {
  @Test("il disco prevale sul log: a S03-b il passo è fatto, con la divergenza dal log")
  func diskPrevailsOverLog() throws {
    let test = try TestVolume(name: "riconoscitore-disco")
    defer { test.close() }
    let batch = try CrashedBatch(volume: test.volume, crashAt: "S03-b")
    let s03 = try batch.step("S03")

    // L'oracolo: il file è già nella destinazione, e il log ha l'intento ma non il fatto.
    let snapshot = try Snapshot.capture(volume: batch.volume)
    try #require(
      snapshot.entries[SnapshotOracle.batchKey("selezione/IMG_0002.jpg")]?.sha256 == s03.sha256)
    try #require(snapshot.entries[SnapshotOracle.batchKey("IMG_0002.jpg")] == nil)
    try #require(
      try batch.log.read().records.last == .stepIntent(stepId: "S03", direction: .forward))

    let state = try batch.recognize()
    #expect(state.step("S03")?.state == .fatto)
    #expect(state.step("S04")?.state == .nonFatto)
    #expect(state.divergences == [Divergence(stepId: "S03", log: "non-fatto", disk: "fatto")])
    #expect(state.statusLines.contains("DIVERGENZA S03 log=non-fatto disco=fatto"))
    #expect(state.statusLines.contains("PASSO S03 fatto"))
    #expect(state.direction == .forward)
    #expect(!state.recordTroncato)
  }

  @Test("un file in due posizioni con lo stesso digest rende S03 non riconoscibile")
  func fileInTwoPositionsIsUnrecognizable() throws {
    let test = try TestVolume(name: "riconoscitore-due-posizioni")
    defer { test.close() }
    let batch = try CrashedBatch(volume: test.volume, crashAt: "S03-c")
    let s03 = try batch.step("S03")
    try batch.copy("lotto/selezione/IMG_0002.jpg", to: "lotto/IMG_0002.jpg")

    let snapshot = try Snapshot.capture(volume: batch.volume)
    try #require(snapshot.entries[SnapshotOracle.batchKey("IMG_0002.jpg")]?.sha256 == s03.sha256)
    try #require(
      snapshot.entries[SnapshotOracle.batchKey("selezione/IMG_0002.jpg")]?.sha256 == s03.sha256)

    let state = try batch.recognize()
    let recognition = try #require(state.step("S03"))
    guard case .nonRiconoscibile(let trace) = recognition.state else {
      Issue.record("S03 atteso non-riconoscibile, riconosciuto \(recognition.state)")
      return
    }
    let digest = String(s03.sha256.prefix(12))
    #expect(trace.contains("lotto/IMG_0002.jpg=\(digest)"), "traccia: \(trace)")
    #expect(trace.contains("lotto/selezione/IMG_0002.jpg=\(digest)"), "traccia: \(trace)")
    #expect(recognition.position == .ambigua)
    #expect(SnapshotOracle.position(of: s03, in: snapshot) == "amb")
    #expect(state.statusLines.contains("PASSO S03 non-riconoscibile"))
    // Nessuna divergenza per un passo che non è né fatto né non fatto.
    #expect(!state.divergences.contains { $0.stepId == "S03" })
  }

  @Test("collisione nel Cestino: a S09-b il passo è fatto, nella voce con il digest e il suffisso")
  func trashCollisionFindsTheEntryByDigest() throws {
    let test = try TestVolume(name: "riconoscitore-cestino")
    defer { test.close() }
    let volume = test.volume
    let foreign = Data("contenuto estraneo, non quello del piano".utf8)
    let batch = try CrashedBatch(
      volume: volume, crashAt: "S09-b",
      beforeBatch: {
        // Una voce IMG_0005.jpg di contenuto diverso, già nel Cestino del volume prima del lotto.
        let file = volume.quarantine.appending(path: "IMG_0005.jpg", directoryHint: .notDirectory)
        try foreign.write(to: file)
        var result: NSURL?
        try FileManager.default.trashItem(at: file, resultingItemURL: &result)
        try #require((result as URL?)?.lastPathComponent == "IMG_0005.jpg")
      })
    let s09 = try batch.step("S09")

    let state = try batch.recognize()
    let recognition = try #require(state.step("S09"))
    #expect(recognition.state == .fatto)
    #expect(recognition.position == .cestino)
    guard case .done(let resultPath) = recognition.observation else {
      Issue.record("S09 atteso fatto, osservato \(String(describing: recognition.observation))")
      return
    }
    let name = URL(filePath: resultPath).lastPathComponent
    #expect(resultPath.hasPrefix(".Trashes/\(getuid())/"))
    #expect(name != "IMG_0005.jpg")
    #expect(name.hasPrefix("IMG_0005"), "voce trovata: \(name)")
    #expect(name.contains(#/\d{2}-\d{2}-\d{2}/#), "voce senza suffisso orario: \(name)")

    // L'oracolo dell'istantanea: due voci IMG_0005, una sola con il digest del piano, ed è quella.
    let snapshot = try Snapshot.capture(volume: volume)
    let trashKey = "\(Snapshot.trashKey)/"
    #expect(SnapshotOracle.trashKeys(withDigest: s09.sha256, in: snapshot) == [trashKey + name])
    #expect(
      snapshot.entries[trashKey + "IMG_0005.jpg"]?.sha256 == Fixtures.sha256Hex(of: foreign))
    #expect(SnapshotOracle.position(of: s09, in: snapshot) == "cest")
  }

  @Test("due voci del Cestino con lo stesso digest rendono S09 non riconoscibile")
  func twoTrashEntriesWithTheDigestAreUnrecognizable() throws {
    let test = try TestVolume(name: "riconoscitore-due-voci")
    defer { test.close() }
    let batch = try CrashedBatch(volume: test.volume, crashAt: "S09-b")
    let s09 = try batch.step("S09")
    let entries = try Steps.trashEntries(
      withDigest: s09.sha256, stepId: s09.id, volume: batch.volume)
    let entry = try #require(entries.first)
    try #require(entries.count == 1)
    let copy = entry.deletingLastPathComponent().appending(
      path: "IMG_0005 copia.jpg", directoryHint: .notDirectory)
    try FileManager.default.copyItem(at: entry, to: copy)

    let snapshot = try Snapshot.capture(volume: batch.volume)
    try #require(SnapshotOracle.trashKeys(withDigest: s09.sha256, in: snapshot).count == 2)

    let state = try batch.recognize()
    let recognition = try #require(state.step("S09"))
    guard case .nonRiconoscibile(let trace) = recognition.state else {
      Issue.record("S09 atteso non-riconoscibile, riconosciuto \(recognition.state)")
      return
    }
    #expect(trace.contains(batch.volume.volumeRelativePath(of: entry)), "traccia: \(trace)")
    #expect(trace.contains(batch.volume.volumeRelativePath(of: copy)), "traccia: \(trace)")
    #expect(recognition.position == .ambigua)
    #expect(SnapshotOracle.position(of: s09, in: snapshot) == "amb")
    #expect(state.step("S10")?.state == .nonFatto)
  }

  @Test("separazione: a S03-c l'immagine di OP2 è nella destinazione, il sidecar in origine")
  func separationAtS03cIsDetected() throws {
    let test = try TestVolume(name: "riconoscitore-separazione")
    defer { test.close() }
    let batch = try CrashedBatch(volume: test.volume, crashAt: "S03-c")

    let state = try batch.recognize()
    let expected = "COPPIA OP2 immagine=dest sidecar=orig SEPARATA"
    #expect(state.pairs.map(\.line).contains(expected), "\(state.pairs.map(\.line))")
    #expect(state.separations == ["OP2"])
    #expect(state.separationsLine == "SEPARAZIONI-ALL-AVVIO OP2")
    #expect(state.divergences.isEmpty)

    // Le posizioni riferite coincidono con quelle dell'istantanea, per ogni coppia.
    let snapshot = try Snapshot.capture(volume: batch.volume)
    let oracle = SnapshotOracle.pairLines(snapshot, plan: batch.plan)
    #expect(oracle.contains(expected), "\(oracle)")
    #expect(state.pairs.map(\.line) == oracle)
  }

  @Test("record troncato: a X00-plan-torn il frammento è salvato in state/torn-*.txt, senza piano")
  func tornPlanRecordIsRepairedAndNoPlan() throws {
    let test = try TestVolume(name: "riconoscitore-troncato")
    defer { test.close() }
    let batch = try CrashedBatch(volume: test.volume, crashAt: "X00-plan-torn")
    let before = try batch.log.read()
    try #require(before.records.isEmpty)
    let fragment = try #require(before.tornTail)

    let state = try batch.recognize()
    #expect(state.recordTroncato)
    #expect(state.isNoPlan)
    #expect(state.steps.isEmpty)
    #expect(state.pairs.isEmpty)
    #expect(state.direction == .nessuna)
    #expect(state.recordTroncatoLine == "RECORD-TRONCATO si")

    // Il frammento è conservato byte per byte, e il log è riparato.
    let evidence = try #require(state.tornEvidence)
    let stateDirectory = batch.volume.stateDirectory.standardizedFileURL.fileSystemPath
    #expect(
      evidence.deletingLastPathComponent().standardizedFileURL.fileSystemPath == stateDirectory)
    let tornFiles = try FileManager.default.contentsOfDirectory(atPath: stateDirectory)
      .filter { $0.hasPrefix("torn-") && $0.hasSuffix(".txt") }
    #expect(tornFiles == [evidence.lastPathComponent])
    #expect(try String(contentsOf: evidence, encoding: .utf8) == fragment)
    let after = try batch.log.read()
    #expect(after.records.isEmpty)
    #expect(after.tornTail == nil)
  }
}
