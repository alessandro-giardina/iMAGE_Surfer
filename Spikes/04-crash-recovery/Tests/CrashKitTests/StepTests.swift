import Darwin
import Foundation
import Testing

@testable import CrashKit

/// Piano della fixture sul volume di prova, con le cartelle da creare già create come le crea la
/// preparazione del lotto.
private func preparedPlan(_ volume: WorkVolume) throws -> BatchPlan {
  let plan = try BatchPlan.make(definition: fixtureDefinition(), volume: volume)
  for directory in plan.directoriesToCreate {
    try FileManager.default.createDirectory(
      at: volume.batchURL(directory), withIntermediateDirectories: false)
  }
  return plan
}

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

/// SHA-256 del file in un percorso relativo al punto di montaggio.
private func digest(_ volumeRelativePath: String, on volume: WorkVolume) throws -> String {
  try Fixtures.sha256Hex(ofFileAt: volume.volumeURL(volumeRelativePath))
}

/// Errore del gancio `afterTempWritten`, al posto dell'arresto del punto `Sxx-m`.
private struct HookStop: Error {}

/// Istantanea presa quando il Cestino del volume si è assestato.
///
/// Dopo uno spostamento nel Cestino i servizi di sistema aggiornano `.Trashes/<uid>` in modo
/// asincrono: `UF_HIDDEN` e `com.apple.FinderInfo` sulla cartella circa 0,3 s dopo la prima voce,
/// una nuova `mtime` di `.DS_Store` circa 0,2 s dopo le voci successive (misurati a riposo; sotto
/// carico più tardi). Con le suite in parallelo questi aggiornamenti cadevano fra le due istantanee
/// del confronto d'idempotenza (TASK-07). L'istantanea si prende quando quattro catture
/// consecutive, a 0,25 s l'una dall'altra, coincidono; al più 10 s.
private func settledSnapshot(_ volume: WorkVolume) throws -> Snapshot {
  var snapshot = try Snapshot.capture(volume: volume)
  var stable = 0
  var attempts = 0
  while stable < 4, attempts < 40 {
    Thread.sleep(forTimeInterval: 0.25)
    let next = try Snapshot.capture(volume: volume)
    stable = next == snapshot ? stable + 1 : 0
    snapshot = next
    attempts += 1
  }
  return snapshot
}

/// Passi reali sul volume di lavoro: ogni test monta un proprio volume ed è eseguito in serie.
@Suite("Piano del lotto e passi idempotenti con compensazione", .serialized)
struct StepTests {
  @Test("il piano espande le cinque operazioni in dieci passi, prima l'immagine e poi il sidecar")
  func planExpandsBatchIntoTenSteps() throws {
    let test = try TestVolume(name: "steps-piano")
    defer { test.close() }
    let volume = test.volume
    let plan = try BatchPlan.make(definition: fixtureDefinition(), volume: volume)

    #expect(plan.batchId == "lotto-di-prova")
    #expect(plan.volumeUUID == (try WorkVolume.volumeUUID(of: volume.batchRoot)))
    #expect(plan.directoriesToCreate == ["selezione", "consegna"])
    #expect(plan.steps.map(\.id) == (1...10).map { String(format: "S%02d", $0) })
    #expect(
      plan.steps.map(\.opId) == [
        "OP1", "OP1", "OP2", "OP2", "OP3", "OP3", "OP4", "OP4", "OP5", "OP5",
      ])
    #expect(
      plan.steps.map(\.kind) == [
        .rename, .rename, .move, .move, .move, .move, .copy, .copy, .trash, .trash,
      ])
    #expect(
      plan.steps.map(\.source).prefix(4) == [
        "IMG_0001.jpg", "IMG_0001.xmp", "IMG_0002.jpg", "IMG_0002.xmp",
      ])
    #expect(
      plan.steps.map(\.destination) == [
        "2026-08-24_evento_001.jpg", "2026-08-24_evento_001.xmp",
        "selezione/IMG_0002.jpg", "selezione/IMG_0002.xmp",
        "selezione/2026-08-24_evento_003.jpg", "selezione/2026-08-24_evento_003.xmp",
        "consegna/IMG_0004.jpg", "consegna/IMG_0004.xmp", nil, nil,
      ])

    // Digest e dimensione di ogni sorgente sono quelli del manifest delle fixture.
    let manifest = try JSONDecoder().decode(
      FixtureManifest.self,
      from: Data(
        contentsOf: CrashPaths.fixtures.appending(
          path: Fixtures.manifestFileName, directoryHint: .notDirectory)))
    for step in plan.steps {
      let entry = try #require(
        manifest.files.first { $0.path == "\(Fixtures.folderName)/\(step.source)" })
      #expect(step.sha256 == entry.sha256, "digest di \(step.id)")
      #expect(step.size == entry.size, "dimensione di \(step.id)")
    }

    // Tutto è `Codable`: il piano rilegge se stesso.
    let data = try JSONEncoder().encode(plan)
    #expect(try JSONDecoder().decode(BatchPlan.self, from: data) == plan)
  }

  @Test(
    "execute e compensate ripetuti agiscono una volta sola, e compensate riporta i file all'origine",
    arguments: OperationKind.allCases)
  func stepsAreIdempotentAndCompensable(kind: OperationKind) throws {
    let test = try TestVolume(name: "steps-\(kind.rawValue)")
    defer { test.close() }
    let volume = test.volume
    let plan = try preparedPlan(volume)
    let start = try Snapshot.capture(volume: volume)
    let steps = plan.steps.filter { $0.kind == kind }
    #expect(!steps.isEmpty)

    for step in steps {
      #expect(try Steps.observe(step, plan: plan, volume: volume) == .notDone, "\(step.id)")

      // Esecuzione: la prima agisce, la seconda non cambia l'istantanea.
      let beforeExecute = try Snapshot.capture(volume: volume)
      let result = try Steps.execute(step, plan: plan, volume: volume)
      // `trash` agisce sul Cestino: il confronto parte dal Cestino assestato.
      let afterExecute =
        try kind == .trash ? settledSnapshot(volume) : Snapshot.capture(volume: volume)
      #expect(!Snapshot.diff(beforeExecute, afterExecute).isEmpty, "\(step.id): nessuna azione")
      #expect(try digest(result, on: volume) == step.sha256, "\(step.id)")
      #expect(
        try Steps.observe(step, plan: plan, volume: volume) == .done(resultPath: result),
        "\(step.id)")
      #expect(try Steps.execute(step, plan: plan, volume: volume) == result, "\(step.id)")
      let afterSecondExecute = try Snapshot.capture(volume: volume)
      #expect(Snapshot.diff(afterExecute, afterSecondExecute).isEmpty, "\(step.id)")

      switch kind {
      case .rename, .move:
        #expect(result == "lotto/\(try #require(step.destination))")
      case .copy:
        #expect(result == "lotto/\(try #require(step.destination))")
        #expect(try digest("lotto/\(step.source)", on: volume) == step.sha256)
      case .trash:
        #expect(result.hasPrefix(".Trashes/\(getuid())/"), "\(step.id): \(result)")
      }

      // Compensazione: la prima agisce, la seconda non cambia l'istantanea.
      let compensated = try Steps.compensate(step, plan: plan, volume: volume)
      // La compensazione di `copy` e di `trash` agisce sul Cestino.
      let afterCompensate =
        try kind == .copy || kind == .trash
        ? settledSnapshot(volume) : Snapshot.capture(volume: volume)
      #expect(!Snapshot.diff(afterSecondExecute, afterCompensate).isEmpty, "\(step.id)")
      #expect(try Steps.observe(step, plan: plan, volume: volume) == .notDone, "\(step.id)")
      let compensatedAgain = try Steps.compensate(step, plan: plan, volume: volume)
      let afterSecondCompensate = try Snapshot.capture(volume: volume)
      #expect(Snapshot.diff(afterCompensate, afterSecondCompensate).isEmpty, "\(step.id)")

      if kind == .copy {
        // La copia va nel Cestino del volume, mai eliminata (NFR-A1).
        #expect(compensated.hasPrefix(".Trashes/\(getuid())/"), "\(step.id): \(compensated)")
        #expect(try digest(compensated, on: volume) == step.sha256, "\(step.id)")
      } else {
        #expect(compensated == "lotto/\(step.source)", "\(step.id)")
      }
      #expect(compensatedAgain == "lotto/\(step.source)", "\(step.id)")

      // Percorsi e digest dei file del lotto tornano quelli di partenza.
      #expect(batchFiles(afterCompensate) == batchFiles(start), "\(step.id)")
    }
  }

  @Test("copia interrotta: execute rimuove il temporaneo e completa la copia")
  func interruptedCopyIsCompleted() throws {
    let test = try TestVolume(name: "steps-copia-interrotta")
    defer { test.close() }
    let volume = test.volume
    let plan = try preparedPlan(volume)
    let consegna = volume.batchURL("consegna").fileSystemPath

    // Temporaneo creato a mano: metà della sorgente.
    let image = try #require(plan.step("S07"))
    let imageTemp = try #require(Steps.tempURL(for: image, plan: plan, volume: volume))
    #expect(imageTemp.lastPathComponent == ".IMG_0004.jpg.partial-\(plan.planId.uuidString)")
    let content = try Data(contentsOf: volume.batchURL(image.source))
    try content.prefix(content.count / 2).write(to: imageTemp)
    #expect(
      try Steps.observe(image, plan: plan, volume: volume)
        == .partial(tempPath: volume.volumeRelativePath(of: imageTemp)))

    let result = try Steps.execute(image, plan: plan, volume: volume)
    #expect(result == "lotto/consegna/IMG_0004.jpg")
    #expect(try digest(result, on: volume) == image.sha256)
    #expect(!FileManager.default.fileExists(atPath: imageTemp.fileSystemPath))
    #expect(try Steps.observe(image, plan: plan, volume: volume) == .done(resultPath: result))
    #expect(try FileManager.default.contentsOfDirectory(atPath: consegna) == ["IMG_0004.jpg"])

    // Temporaneo lasciato dal gancio fra scrittura e pubblicazione (punto `Sxx-m`).
    let sidecar = try #require(plan.step("S08"))
    let sidecarTemp = try #require(Steps.tempURL(for: sidecar, plan: plan, volume: volume))
    #expect(throws: HookStop.self) {
      try Steps.execute(sidecar, plan: plan, volume: volume, afterTempWritten: { throw HookStop() })
    }
    #expect(try Fixtures.sha256Hex(ofFileAt: sidecarTemp) == sidecar.sha256)
    #expect(
      try Steps.observe(sidecar, plan: plan, volume: volume)
        == .partial(tempPath: volume.volumeRelativePath(of: sidecarTemp)))
    let sidecarResult = try Steps.execute(sidecar, plan: plan, volume: volume)
    #expect(sidecarResult == "lotto/consegna/IMG_0004.xmp")
    #expect(!FileManager.default.fileExists(atPath: sidecarTemp.fileSystemPath))
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: consegna).sorted() == [
        "IMG_0004.jpg", "IMG_0004.xmp",
      ])
  }

  @Test("collisione nel Cestino: observe trova la voce giusta per digest, non per nome")
  func trashCollisionIsResolvedByDigest() throws {
    let test = try TestVolume(name: "steps-collisione-cestino")
    defer { test.close() }
    let volume = test.volume
    let plan = try preparedPlan(volume)
    let step = try #require(plan.step("S09"))

    // Una voce `IMG_0005.jpg` di contenuto diverso, già nel Cestino del volume.
    let decoyFolder = volume.mountPoint.appending(path: "esca", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: decoyFolder, withIntermediateDirectories: false)
    let decoyContent = Data("contenuto diverso\n".utf8)
    let decoy = decoyFolder.appending(path: "IMG_0005.jpg", directoryHint: .notDirectory)
    try decoyContent.write(to: decoy)
    var decoyResult: NSURL?
    try FileManager.default.trashItem(at: decoy, resultingItemURL: &decoyResult)
    try FileManager.default.removeItem(at: decoyFolder)
    let decoyPath = volume.volumeRelativePath(of: try #require(decoyResult) as URL)
    #expect(decoyPath == ".Trashes/\(getuid())/IMG_0005.jpg")
    #expect(try Steps.observe(step, plan: plan, volume: volume) == .notDone)

    let result = try Steps.execute(step, plan: plan, volume: volume)
    #expect(result != decoyPath)
    #expect(result.hasPrefix(".Trashes/\(getuid())/"), "\(result)")
    #expect(try Steps.observe(step, plan: plan, volume: volume) == .done(resultPath: result))
    #expect(try digest(result, on: volume) == step.sha256)
    #expect(try digest(decoyPath, on: volume) == Fixtures.sha256Hex(of: decoyContent))

    // La compensazione riprende la voce trovata per digest e lascia l'esca nel Cestino.
    #expect(try Steps.compensate(step, plan: plan, volume: volume) == "lotto/IMG_0005.jpg")
    #expect(try digest("lotto/IMG_0005.jpg", on: volume) == step.sha256)
    #expect(try digest(decoyPath, on: volume) == Fixtures.sha256Hex(of: decoyContent))
    #expect(!FileManager.default.fileExists(atPath: volume.volumeURL(result).fileSystemPath))
    #expect(try Steps.observe(step, plan: plan, volume: volume) == .notDone)
  }

  @Test("Cestino fuori volume: un passo trash su un altro volume fallisce e il file resta dov'è")
  func trashRefusesSourceOutsidePlanVolume() throws {
    let test = try TestVolume(name: "steps-fuori-volume")
    defer { test.close() }
    let planVolumeUUID = try WorkVolume.volumeUUID(of: test.volume.batchRoot)

    // Directory dati mai montata, nella directory temporanea dell'ospite: la sua cartella del
    // lotto sta sul volume ospite.
    let hostData = FileManager.default.temporaryDirectory
      .appending(path: "spike04-fuori-volume-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer {
      do {
        try FileManager.default.removeItem(at: hostData)
      } catch {
        Issue.record("rimozione della directory sull'ospite fallita: \(error)")
      }
    }
    let host = WorkVolume(dataDirectory: hostData)
    try FileManager.default.createDirectory(at: host.batchRoot, withIntermediateDirectories: true)
    let source = host.batchURL("IMG_0005.jpg")
    try FileManager.default.copyItem(
      at: CrashPaths.fixtureFolder.appending(path: "IMG_0005.jpg", directoryHint: .notDirectory),
      to: source)
    let sourceDigest = try Fixtures.sha256Hex(ofFileAt: source)
    #expect(try WorkVolume.volumeUUID(of: source) != planVolumeUUID)

    let step = PlannedStep(
      id: "S09", opId: "OP5", kind: .trash, source: "IMG_0005.jpg", destination: nil,
      sha256: sourceDigest, size: Int64(try Data(contentsOf: source).count))
    let plan = BatchPlan(
      planId: UUID(), batchId: "fuori-volume", volumeUUID: planVolumeUUID, steps: [step],
      directoriesToCreate: [])
    #expect(try Steps.observe(step, plan: plan, volume: host) == .notDone)

    let failure = try #require(throws: StepFailure.self) {
      try Steps.execute(step, plan: plan, volume: host)
    }
    #expect(failure.stepId == "S09")
    #expect(failure.syscall == StepFailure.volumeCheck)
    #expect(failure.errno == nil)
    #expect(failure.path == source.fileSystemPath)
    #expect(try Fixtures.sha256Hex(ofFileAt: source) == sourceDigest)
    #expect(!FileManager.default.fileExists(atPath: host.trashDirectory.fileSystemPath))
    #expect(try Steps.observe(step, plan: plan, volume: host) == .notDone)
  }

  @Test("compensatePrepare rimuove solo le cartelle create e vuote, e mantiene le altre")
  func compensatePrepareKeepsNonEmptyFolders() throws {
    let test = try TestVolume(name: "steps-preparazione")
    defer { test.close() }
    let volume = test.volume
    let plan = try preparedPlan(volume)
    #expect(plan.directoriesToCreate == ["selezione", "consegna"])
    let estranea = volume.batchURL("estranea")
    try FileManager.default.createDirectory(at: estranea, withIntermediateDirectories: false)
    try Steps.execute(try #require(plan.step("S07")), plan: plan, volume: volume)

    let kept = try Steps.compensatePrepare(created: plan.directoriesToCreate, volume: volume)
    #expect(kept == ["consegna"])
    #expect(!FileManager.default.fileExists(atPath: volume.batchURL("selezione").fileSystemPath))
    #expect(FileManager.default.fileExists(atPath: volume.batchURL("consegna").fileSystemPath))
    // Una cartella che il lotto non ha creato non viene toccata, anche se vuota.
    #expect(FileManager.default.fileExists(atPath: estranea.fileSystemPath))

    // Ripetuta, non cambia nulla: la cartella già rimossa conta come rimossa.
    let before = try Snapshot.capture(volume: volume)
    #expect(try Steps.compensatePrepare(created: plan.directoriesToCreate, volume: volume) == kept)
    #expect(Snapshot.diff(before, try Snapshot.capture(volume: volume)).isEmpty)
  }

  @Test(
    "su uno stato anomalo il passo riporta l'errore reale come StepFailure e non tocca file estranei"
  )
  func anomalousStepsReportRawFailures() throws {
    let test = try TestVolume(name: "steps-anomalie")
    defer { test.close() }
    let volume = test.volume
    let plan = try preparedPlan(volume)
    let quarantine = volume.quarantine

    // Sorgente spostata altrove: `renamex_np` fallisce con ENOENT.
    let s01 = try #require(plan.step("S01"))
    let moved = quarantine.appending(path: s01.source, directoryHint: .notDirectory)
    try FileManager.default.moveItem(at: volume.batchURL(s01.source), to: moved)
    let missing = try #require(throws: StepFailure.self) {
      try Steps.execute(s01, plan: plan, volume: volume)
    }
    #expect(missing.syscall == "renamex_np")
    #expect(missing.errno == ENOENT)
    try FileManager.default.moveItem(at: moved, to: volume.batchURL(s01.source))

    // File estraneo nella destinazione: `RENAME_EXCL` fallisce con EEXIST e non sovrascrive.
    let foreign = Data("estraneo".utf8)
    let s02 = try #require(plan.step("S02"))
    let s02Destination = volume.batchURL(try #require(s02.destination))
    try foreign.write(to: s02Destination)
    let collision = try #require(throws: StepFailure.self) {
      try Steps.execute(s02, plan: plan, volume: volume)
    }
    #expect(collision.syscall == "renamex_np")
    #expect(collision.errno == EEXIST)
    #expect(try Data(contentsOf: s02Destination) == foreign)
    #expect(try digest("lotto/\(s02.source)", on: volume) == s02.sha256)

    // Sorgente con un digest diverso dal piano: rifiuto, nessuna chiamata, file al suo posto.
    let s03 = try #require(plan.step("S03"))
    let s03Source = volume.batchURL(s03.source)
    let handle = try FileHandle(forWritingTo: s03Source)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data([0x00]))
    try handle.close()
    let modified = try #require(throws: StepFailure.self) {
      try Steps.execute(s03, plan: plan, volume: volume)
    }
    #expect(modified.syscall == StepFailure.digestCheck)
    #expect(modified.errno == nil)
    #expect(FileManager.default.fileExists(atPath: s03Source.fileSystemPath))
    #expect(
      !FileManager.default.fileExists(
        atPath: volume.batchURL(try #require(s03.destination)).fileSystemPath))

    // `trashItem` su un file immutabile: errore Cocoa senza errno (baseline).
    let s09 = try #require(plan.step("S09"))
    let s09Source = volume.batchURL(s09.source).fileSystemPath
    #expect(chflags(s09Source, UInt32(UF_IMMUTABLE)) == 0)
    let locked = try #require(throws: StepFailure.self) {
      try Steps.execute(s09, plan: plan, volume: volume)
    }
    #expect(locked.syscall == "trashItem")
    #expect(locked.errno == nil)
    #expect(locked.cocoa == "NSCocoaErrorDomain 513 / NSOSStatusErrorDomain -5000")
    #expect(try Steps.observe(s09, plan: plan, volume: volume) == .notDone)
    #expect(chflags(s09Source, 0) == 0)
  }
}
