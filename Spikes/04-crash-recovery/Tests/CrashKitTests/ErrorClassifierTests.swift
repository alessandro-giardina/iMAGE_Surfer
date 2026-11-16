import Darwin
import Foundation
import Testing

@testable import CrashKit

private func fixtureDefinition() throws -> BatchDefinition {
  try BatchDefinition.load(
    from: CrashPaths.fixtures.appending(path: Fixtures.batchFileName, directoryHint: .notDirectory))
}

/// Lotto di prova su un volume dedicato, nello stato lasciato da un arresto: piano registrato nel
/// log, cartelle preparate e i primi `executed` passi eseguiti (0 equivale a `X03-prepare`, 6 a
/// `S06-b`, 10 a `S10-c`).
private struct Batch {
  let volume: WorkVolume
  let plan: BatchPlan
  let log: IntentLog

  init(volume: WorkVolume, executed: Int) throws {
    self.volume = volume
    log = IntentLog(volume: volume)
    plan = try BatchPlan.make(definition: fixtureDefinition(), volume: volume)
    try log.append(.plan(plan))
    for directory in plan.directoriesToCreate {
      try FileManager.default.createDirectory(
        at: volume.batchURL(directory), withIntermediateDirectories: false)
    }
    try log.append(.prepare(created: plan.directoriesToCreate))
    try execute(through: executed)
  }

  /// Esegue in avanti i passi fino all'`executed`-esimo compreso; quelli già fatti non cambiano.
  func execute(through executed: Int) throws {
    for step in plan.steps.prefix(executed) {
      try Steps.execute(step, plan: plan, volume: volume)
    }
  }

  func step(_ id: String) throws -> PlannedStep {
    try #require(plan.step(id))
  }

  func target(_ errorClass: ErrorClass, _ strategy: RecoveryStrategy) throws -> PerturbationTarget {
    try Perturbations.target(errorClass, strategy: strategy, plan: plan, log: log, volume: volume)
  }

  func apply(_ errorClass: ErrorClass, _ strategy: RecoveryStrategy) throws -> PerturbationRecord {
    try Perturbations.apply(errorClass, strategy: strategy, plan: plan, log: log, volume: volume)
  }

  func classify(
    _ failure: StepFailure?, observation: StepObservation? = nil, _ step: PlannedStep,
    _ direction: StepDirection
  ) -> Classification {
    ErrorClassifier.classify(
      failure: failure, observation: observation, step: step, plan: plan, volume: volume,
      direction: direction)
  }

  func observe(_ step: PlannedStep) throws -> StepObservation {
    try Steps.observe(step, plan: plan, volume: volume)
  }
}

/// `st_flags` del file in un percorso relativo al punto di montaggio.
private func flags(_ volumeRelativePath: String, on volume: WorkVolume) throws -> UInt32 {
  var info = stat()
  try #require(lstat(volume.volumeURL(volumeRelativePath).fileSystemPath, &info) == 0)
  return info.st_flags
}

/// Scostamenti fra due istantanee esclusa la `mtime` delle directory, l'unico ammesso.
private func deviationsBeyondDirectoryMtime(_ before: Snapshot, _ after: Snapshot) -> [Deviation] {
  Snapshot.diff(before, after).filter { !$0.isDirectoryMtime }
}

/// Classificazione per ambito su errori reali del volume di lavoro, prodotti dalle otto
/// perturbazioni: ogni test monta un proprio volume ed è eseguito in serie.
@Suite("Classificazione degli errori per ambito e perturbazioni reversibili", .serialized)
struct ErrorClassifierTests {
  @Test("le otto classi hanno l'ambito adottato: le tre G sistemiche, le cinque L locali")
  func everyClassHasAnAdoptedScope() {
    #expect(
      ErrorClass.allCases.map(\.rawValue) == [
        "G-volume-missing", "G-folder-readonly", "G-space-exhausted", "L-locked", "L-collision",
        "L-modified", "L-trash-emptied", "L-missing",
      ])
    for errorClass in ErrorClass.allCases {
      let expected: ErrorScope = errorClass.rawValue.hasPrefix("G-") ? .sistemico : .locale
      #expect(errorClass.scope == expected, "\(errorClass.rawValue)")
      #expect(Classification.classified(errorClass).scope == expected)
    }
    #expect(Classification.nonClassificato("x").errorClass == nil)
    #expect(
      Classification.classified(.missing).description == "classe=L-missing ambito=locale")
  }

  @Test(
    "ENOENT a volume montato è L-missing, lo stesso ENOENT dopo l'espulsione è G-volume-missing")
  func enoentIsClassifiedByScopeNotByErrno() throws {
    let test = try TestVolume(name: "classi-enoent")
    defer { test.close() }
    let volume = test.volume
    let batch = try Batch(volume: volume, executed: 0)
    let s01 = try batch.step("S01")

    // File in quarantena, volume montato.
    let missing = try batch.apply(.missing, .resume)
    #expect(missing.line == "PERTURBAZIONE L-missing bersaglio=S01 ambito=locale")
    #expect(
      FileManager.default.fileExists(
        atPath: volume.quarantine.appending(path: "IMG_0001.jpg").fileSystemPath))
    let fileGone = try #require(throws: StepFailure.self) {
      try Steps.execute(s01, plan: batch.plan, volume: volume)
    }
    #expect(fileGone.errno == ENOENT)
    #expect(batch.classify(fileGone, s01, .forward) == .classified(.missing))
    #expect(batch.classify(fileGone, s01, .forward).scope == .locale)
    // Dalla sola anomalia osservata, come farà il riconoscitore del recupero.
    #expect(
      batch.classify(nil, observation: try batch.observe(s01), s01, .forward)
        == .classified(.missing))
    #expect(try Perturbations.remove(volume: volume) == missing)
    #expect(try batch.observe(s01) == .notDone)

    // Volume espulso: il punto di montaggio è una directory vuota dell'ospite.
    let ejected = try batch.apply(.volumeMissing, .resume)
    #expect(ejected.line == "PERTURBAZIONE G-volume-missing bersaglio=nessuno ambito=sistemico")
    #expect(!volume.isMounted)
    let volumeGone = try #require(throws: StepFailure.self) {
      try Steps.execute(s01, plan: batch.plan, volume: volume)
    }
    #expect(volumeGone.syscall == fileGone.syscall)
    #expect(volumeGone.errno == ENOENT)
    #expect(batch.classify(volumeGone, s01, .forward) == .classified(.volumeMissing))
    #expect(batch.classify(volumeGone, s01, .forward).scope == .sistemico)

    #expect(try Perturbations.remove(volume: volume) == ejected)
    #expect(volume.isMounted)
    #expect(try batch.observe(s01) == .notDone)
  }

  @Test(
    "volume pieno: la copia S07 dà ENOSPC, G-space-exhausted sistemico; la rinomina S01 riesce")
  func fullVolumeStopsCopiesOnly() throws {
    let test = try TestVolume(name: "classi-spazio")
    defer { test.close() }
    let volume = test.volume
    let batch = try Batch(volume: volume, executed: 0)

    let filled = try batch.apply(.spaceExhausted, .resume)
    #expect(filled.line == "PERTURBAZIONE G-space-exhausted bersaglio=S07 ambito=sistemico")
    // Il riempimento occupa quasi tutto il volume da 64 MB. Lo spazio libero dichiarato dal file
    // system non è un oracolo: APFS ne riporta ancora circa 1,8 MB quando anche 1 byte è rifiutato.
    let filler = try FileManager.default.attributesOfItem(
      atPath: Perturbations.fillerURL(in: volume).fileSystemPath)
    let fillerSize = try #require(filler[.size] as? NSNumber).int64Value
    #expect(fillerSize > 32 << 20, "riempimento di \(fillerSize) byte")

    let s07 = try batch.step("S07")
    let noSpace = try #require(throws: StepFailure.self) {
      try Steps.execute(s07, plan: batch.plan, volume: volume)
    }
    #expect(noSpace.syscall == "copyfile")
    #expect(noSpace.errno == ENOSPC)
    #expect(batch.classify(noSpace, s07, .forward) == .classified(.spaceExhausted))
    #expect(batch.classify(noSpace, s07, .forward).scope == .sistemico)

    let s01 = try batch.step("S01")
    let renamed = try Steps.execute(s01, plan: batch.plan, volume: volume)
    #expect(try batch.observe(s01) == .done(resultPath: renamed))

    #expect(try Perturbations.remove(volume: volume) == filled)
    #expect(
      !FileManager.default.fileExists(atPath: Perturbations.fillerURL(in: volume).fileSystemPath))
  }

  @Test(
    "Cestino svuotato: la compensazione di S09 dopo la sua esecuzione è L-trash-emptied, locale")
  func emptiedTrashIsLocal() throws {
    let test = try TestVolume(name: "classi-cestino")
    defer { test.close() }
    let volume = test.volume
    let batch = try Batch(volume: volume, executed: 9)
    let s09 = try batch.step("S09")
    let trashed = try batch.observe(s09)
    guard case .done = trashed else {
      Issue.record("S09 non risulta eseguito: \(trashed)")
      return
    }

    let emptied = try batch.apply(.trashEmptied, .compensate)
    #expect(emptied.line == "PERTURBAZIONE L-trash-emptied bersaglio=S09 ambito=locale")
    let notFound = try #require(throws: StepFailure.self) {
      try Steps.compensate(s09, plan: batch.plan, volume: volume)
    }
    #expect(notFound.syscall == StepFailure.trashLookup)
    #expect(batch.classify(notFound, s09, .compensate) == .classified(.trashEmptied))
    #expect(batch.classify(notFound, s09, .compensate).scope == .locale)
    #expect(
      batch.classify(nil, observation: try batch.observe(s09), s09, .compensate)
        == .classified(.trashEmptied))
    // In avanti lo stesso disco è un file mancante: il Cestino svuotato vale solo in compensazione.
    #expect(
      batch.classify(nil, observation: try batch.observe(s09), s09, .forward)
        == .classified(.missing))

    #expect(try Perturbations.remove(volume: volume) == emptied)
    #expect(try batch.observe(s09) == trashed)
  }

  @Test("file bloccato: EPERM della rinomina ed errore Cocoa 513 del Cestino sono L-locked, locale")
  func lockedFileIsLocalForRenameAndTrash() throws {
    let test = try TestVolume(name: "classi-bloccato")
    defer { test.close() }
    let volume = test.volume
    let batch = try Batch(volume: volume, executed: 0)

    // Rinomina: errno EPERM.
    let lockedRename = try batch.apply(.locked, .resume)
    #expect(lockedRename.line == "PERTURBAZIONE L-locked bersaglio=S01 ambito=locale")
    #expect(try flags("lotto/IMG_0001.jpg", on: volume) & UInt32(UF_IMMUTABLE) != 0)
    let s01 = try batch.step("S01")
    let denied = try #require(throws: StepFailure.self) {
      try Steps.execute(s01, plan: batch.plan, volume: volume)
    }
    #expect(denied.errno == EPERM)
    #expect(batch.classify(denied, s01, .forward) == .classified(.locked))
    try Perturbations.remove(volume: volume)
    #expect(try flags("lotto/IMG_0001.jpg", on: volume) & UInt32(UF_IMMUTABLE) == 0)

    // Cestino, a lotto a metà: la regola del bersaglio sceglie S09, il primo `trash` non eseguito.
    try batch.execute(through: 6)
    let lockedTrash = try batch.apply(.locked, .resume)
    #expect(lockedTrash.line == "PERTURBAZIONE L-locked bersaglio=S09 ambito=locale")
    let s09 = try batch.step("S09")
    let refused = try #require(throws: StepFailure.self) {
      try Steps.execute(s09, plan: batch.plan, volume: volume)
    }
    #expect(refused.errno == nil)
    #expect(refused.cocoa?.hasPrefix("NSCocoaErrorDomain 513") == true, "\(refused)")
    #expect(batch.classify(refused, s09, .forward) == .classified(.locked))
    #expect(batch.classify(refused, s09, .forward).scope == .locale)
    try Perturbations.remove(volume: volume)
    #expect(try flags("lotto/IMG_0005.jpg", on: volume) & UInt32(UF_IMMUTABLE) == 0)
  }

  @Test(
    "collisione: un file estraneo all'arrivo è L-collision in ripresa e in compensazione"
  )
  func collisionIsLocalInBothDirections() throws {
    let test = try TestVolume(name: "classi-collisione")
    defer { test.close() }
    let volume = test.volume
    let batch = try Batch(volume: volume, executed: 0)
    let foreignDigest = Fixtures.sha256Hex(of: Data(Perturbations.foreignContent.utf8))

    // Ripresa: il file estraneo occupa la destinazione di S01.
    let onDestination = try batch.apply(.collision, .resume)
    #expect(onDestination.line == "PERTURBAZIONE L-collision bersaglio=S01 ambito=locale")
    #expect(
      try Fixtures.sha256Hex(ofFileAt: volume.batchURL("2026-08-24_evento_001.jpg"))
        == foreignDigest)
    let s01 = try batch.step("S01")
    #expect(
      batch.classify(nil, observation: try batch.observe(s01), s01, .forward)
        == .classified(.collision))
    let exists = try #require(throws: StepFailure.self) {
      try Steps.execute(s01, plan: batch.plan, volume: volume)
    }
    #expect(exists.errno == EEXIST)
    #expect(batch.classify(exists, s01, .forward) == .classified(.collision))
    try Perturbations.remove(volume: volume)
    #expect(try batch.observe(s01) == .notDone)

    // Compensazione: il file estraneo occupa l'origine di S06, l'ultimo passo eseguito.
    try batch.execute(through: 6)
    let onOrigin = try batch.apply(.collision, .compensate)
    #expect(onOrigin.line == "PERTURBAZIONE L-collision bersaglio=S06 ambito=locale")
    let s06 = try batch.step("S06")
    let occupied = try #require(throws: StepFailure.self) {
      try Steps.compensate(s06, plan: batch.plan, volume: volume)
    }
    #expect(occupied.errno == EEXIST)
    #expect(batch.classify(occupied, s06, .compensate) == .classified(.collision))
    #expect(batch.classify(occupied, s06, .compensate).scope == .locale)
    try Perturbations.remove(volume: volume)
    guard case .done = try batch.observe(s06) else {
      Issue.record("S06 non risulta più eseguito dopo la rimozione")
      return
    }
  }

  @Test("file modificato: un digest diverso dal piano nella posizione attesa è L-modified, locale")
  func modifiedFileIsLocal() throws {
    let test = try TestVolume(name: "classi-modificato")
    defer { test.close() }
    let volume = test.volume
    let batch = try Batch(volume: volume, executed: 0)

    let source = try batch.apply(.modified, .resume)
    #expect(source.line == "PERTURBAZIONE L-modified bersaglio=S01 ambito=locale")
    let s01 = try batch.step("S01")
    let foreign = try #require(throws: StepFailure.self) {
      try Steps.execute(s01, plan: batch.plan, volume: volume)
    }
    #expect(foreign.syscall == StepFailure.digestCheck)
    #expect(batch.classify(foreign, s01, .forward) == .classified(.modified))
    #expect(
      batch.classify(nil, observation: try batch.observe(s01), s01, .forward)
        == .classified(.modified))
    try Perturbations.remove(volume: volume)
    #expect(try batch.observe(s01) == .notDone)

    try batch.execute(through: 6)
    let destination = try batch.apply(.modified, .compensate)
    #expect(destination.line == "PERTURBAZIONE L-modified bersaglio=S06 ambito=locale")
    let s06 = try batch.step("S06")
    let changed = try #require(throws: StepFailure.self) {
      try Steps.compensate(s06, plan: batch.plan, volume: volume)
    }
    #expect(changed.syscall == StepFailure.digestCheck)
    #expect(batch.classify(changed, s06, .compensate) == .classified(.modified))
    #expect(batch.classify(changed, s06, .compensate).scope == .locale)
    try Perturbations.remove(volume: volume)
  }

  @Test(
    "sola lettura: EACCES è G-folder-readonly, sistemico; senza la precondizione non ha classe")
  func readOnlyFolderIsSystemic() throws {
    let test = try TestVolume(name: "classi-sola-lettura")
    defer { test.close() }
    let volume = test.volume
    let batch = try Batch(volume: volume, executed: 6)

    let readOnly = try batch.apply(.folderReadonly, .resume)
    #expect(readOnly.line == "PERTURBAZIONE G-folder-readonly bersaglio=nessuno ambito=sistemico")
    let s07 = try batch.step("S07")
    let denied = try #require(throws: StepFailure.self) {
      try Steps.execute(s07, plan: batch.plan, volume: volume)
    }
    #expect(denied.errno == EACCES)
    #expect(batch.classify(denied, s07, .forward) == .classified(.folderReadonly))
    #expect(batch.classify(denied, s07, .forward).scope == .sistemico)
    try Perturbations.remove(volume: volume)

    // Nessun ricorso a errno «simili»: senza la sua precondizione, EACCES non ha una classe.
    let unexplained = StepFailure(
      stepId: "S07", syscall: "copyfile", errno: EACCES,
      path: volume.batchURL("IMG_0004.jpg").fileSystemPath)
    guard case .nonClassificato = batch.classify(unexplained, s07, .forward) else {
      Issue.record("EACCES senza cartella in sola lettura è stato classificato")
      return
    }
    // Nulla da classificare: nessun fallimento e un passo nello stato atteso.
    guard case .nonClassificato = batch.classify(nil, observation: .notDone, s07, .forward) else {
      Issue.record("un passo non eseguito senza fallimento è stato classificato")
      return
    }
  }

  @Test(
    "regola del bersaglio: primo passo non eseguito in ripresa, ultimo eseguito in compensazione"
  )
  func targetRuleFollowsObservedSteps() throws {
    let test = try TestVolume(name: "classi-bersaglio")
    defer { test.close() }
    let volume = test.volume
    let batch = try Batch(volume: volume, executed: 0)
    func targetId(_ errorClass: ErrorClass, _ strategy: RecoveryStrategy) throws -> String {
      switch try batch.target(errorClass, strategy) {
      case .step(let step): step.id
      case .noFileTarget: "nessuno"
      case .nonApplicabile(let reason): "non-applicabile:\(reason)"
      }
    }
    let reason = Perturbations.Reason.self

    // `X03-prepare`: nulla eseguito.
    for errorClass in [ErrorClass.missing, .locked, .collision, .modified] {
      #expect(try targetId(errorClass, .resume) == "S01", "\(errorClass.rawValue)")
      #expect(
        try targetId(errorClass, .compensate) == "non-applicabile:\(reason.noExecutedStep)",
        "\(errorClass.rawValue)")
    }
    #expect(try targetId(.spaceExhausted, .resume) == "S07")
    #expect(
      try targetId(.spaceExhausted, .compensate) == "non-applicabile:\(reason.copiesOnResumeOnly)")
    #expect(
      try targetId(.trashEmptied, .resume)
        == "non-applicabile:\(reason.executedTrashCompensationOnly)")
    #expect(try targetId(.trashEmptied, .compensate) == "non-applicabile:\(reason.noExecutedStep)")
    for strategy in RecoveryStrategy.allCases {
      #expect(try targetId(.volumeMissing, strategy) == "nessuno")
      #expect(try targetId(.folderReadonly, strategy) == "nessuno")
    }

    // `S06-b`: S01…S06 eseguiti.
    try batch.execute(through: 6)
    #expect(try targetId(.locked, .resume) == "S09")
    for errorClass in [ErrorClass.missing, .collision, .modified, .spaceExhausted] {
      #expect(try targetId(errorClass, .resume) == "S07", "\(errorClass.rawValue)")
    }
    for errorClass in [ErrorClass.missing, .locked, .collision, .modified] {
      #expect(try targetId(errorClass, .compensate) == "S06", "\(errorClass.rawValue)")
    }
    #expect(try targetId(.trashEmptied, .compensate) == "non-applicabile:\(reason.noExecutedStep)")

    // `S10-c`: tutto eseguito.
    try batch.execute(through: 10)
    for errorClass in [ErrorClass.missing, .locked, .collision, .modified] {
      #expect(
        try targetId(errorClass, .resume) == "non-applicabile:\(reason.noPendingStep)",
        "\(errorClass.rawValue)")
    }
    #expect(try targetId(.spaceExhausted, .resume) == "non-applicabile:\(reason.noPendingStep)")
    for errorClass in [ErrorClass.missing, .locked, .collision, .modified, .trashEmptied] {
      #expect(try targetId(errorClass, .compensate) == "S10", "\(errorClass.rawValue)")
    }

    // Senza bersaglio non si applica nulla e non si salva nulla.
    let before = try Snapshot.capture(volume: volume)
    let notApplied = try batch.apply(.spaceExhausted, .compensate)
    #expect(!notApplied.isApplied)
    #expect(notApplied.target == nil)
    #expect(
      notApplied.line
        == "PERTURBAZIONE G-space-exhausted NON-APPLICABILE motivo=\(reason.copiesOnResumeOnly)")
    #expect(try Perturbations.active(volume: volume) == nil)
    #expect(Snapshot.diff(before, try Snapshot.capture(volume: volume)).isEmpty)

    // Una sola perturbazione alla volta.
    let applied = try batch.apply(.locked, .compensate)
    #expect(throws: PerturbationError.alreadyActive(.locked)) {
      try batch.apply(.missing, .compensate)
    }
    #expect(try Perturbations.remove(volume: volume) == applied)

    // Un log senza il piano: nessun recupero conoscerebbe il lotto.
    let emptyLog = IntentLog(
      url: volume.stateDirectory.appending(path: "vuoto.jsonl", directoryHint: .notDirectory))
    #expect(
      try Perturbations.target(
        .missing, strategy: .compensate, plan: batch.plan, log: emptyLog, volume: volume)
        == .nonApplicabile(reason.planNotInLog))
  }

  @Test(
    "rimozione: remove riporta l'istantanea precedente, salvo la mtime delle directory",
    arguments: ErrorClass.allCases)
  func removalRestoresSnapshot(errorClass: ErrorClass) throws {
    let test = try TestVolume(name: "classi-rimozione-\(errorClass.rawValue)")
    defer { test.close() }
    let volume = test.volume
    let strategy: RecoveryStrategy = errorClass == .trashEmptied ? .compensate : .resume
    let batch = try Batch(volume: volume, executed: errorClass == .trashEmptied ? 9 : 6)

    let before = try Snapshot.capture(volume: volume)
    let record = try batch.apply(errorClass, strategy)
    #expect(record.isApplied, "\(record.line)")
    #expect(try Perturbations.active(volume: volume) == record)
    switch errorClass {
    case .spaceExhausted:
      #expect(
        FileManager.default.fileExists(atPath: Perturbations.fillerURL(in: volume).fileSystemPath))
    case .volumeMissing:
      #expect(!volume.isMounted)
    default:
      #expect(!Snapshot.diff(before, try Snapshot.capture(volume: volume)).isEmpty)
    }

    #expect(try Perturbations.remove(volume: volume) == record)
    #expect(volume.isMounted)
    let after = try Snapshot.capture(volume: volume)
    #expect(deviationsBeyondDirectoryMtime(before, after) == [])
    #expect(try Perturbations.active(volume: volume) == nil)
    #expect(
      !FileManager.default.fileExists(atPath: Perturbations.fillerURL(in: volume).fileSystemPath))

    // Una seconda rimozione non trova nulla e non cambia nulla.
    #expect(try Perturbations.remove(volume: volume) == nil)
    #expect(Snapshot.diff(after, try Snapshot.capture(volume: volume)).isEmpty)
  }

  @Test(
    "rimozione: il file torna dalla quarantena anche se la compensazione ha rimosso la cartella")
  func removalRecreatesFolderRemovedByCompensation() throws {
    let test = try TestVolume(name: "classi-rimozione-cartella")
    defer { test.close() }
    let volume = test.volume
    // Il caso rilevato dalla matrice: S06-b, L-missing in compensazione sul sidecar di OP3.
    let batch = try Batch(volume: volume, executed: 6)
    let s06 = try batch.step("S06")
    let destination = try #require(s06.destination)
    let record = try batch.apply(.missing, .compensate)
    #expect(record.target == "S06")

    // La compensazione riporta S05…S01 all'origine e rimuove `selezione/`, ormai vuota.
    for id in ["S05", "S04", "S03", "S02", "S01"] {
      try Steps.compensate(try batch.step(id), plan: batch.plan, volume: volume)
    }
    let kept = try Steps.compensatePrepare(created: batch.plan.directoriesToCreate, volume: volume)
    #expect(kept.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: volume.batchURL("selezione").fileSystemPath))

    #expect(try Perturbations.remove(volume: volume) == record)
    #expect(try Steps.digest(of: volume.batchURL(destination), stepId: "S06") == s06.sha256)
    #expect(try Perturbations.active(volume: volume) == nil)
  }

  @Test(
    "perturb e unperturb dal binario: la rimozione funziona da un altro processo ed è idempotente")
  func commandLineAppliesAndRemovesAcrossProcesses() throws {
    let test = try TestVolume(name: "classi-cli")
    defer { test.close() }
    let volume = test.volume
    _ = try Batch(volume: volume, executed: 0)
    let before = try Snapshot.capture(volume: volume)

    let applied = try crashbench(["perturb", "L-locked", "--strategy", "resume"], test)
    #expect(applied.status == 0, "\(applied.stderr)")
    #expect(applied.stdout == "PERTURBAZIONE L-locked bersaglio=S01 ambito=locale\n")
    #expect(try flags("lotto/IMG_0001.jpg", on: volume) & UInt32(UF_IMMUTABLE) != 0)

    let removed = try crashbench(["unperturb"], test)
    #expect(removed.status == 0, "\(removed.stderr)")
    #expect(removed.stdout == "RIMOZIONE L-locked bersaglio=S01\n")
    let again = try crashbench(["unperturb"], test)
    #expect(again.status == 0, "\(again.stderr)")
    #expect(again.stdout == "RIMOZIONE nessuna\n")
    #expect(deviationsBeyondDirectoryMtime(before, try Snapshot.capture(volume: volume)) == [])

    let notApplicable = try crashbench(
      ["perturb", "G-space-exhausted", "--strategy", "compensate"], test)
    #expect(notApplicable.status == 0, "\(notApplicable.stderr)")
    #expect(
      notApplicable.stdout
        == "PERTURBAZIONE G-space-exhausted NON-APPLICABILE motivo=solo-copie-in-ripresa\n")

    let unknown = try crashbench(["perturb", "L-sconosciuta", "--strategy", "resume"], test)
    #expect(unknown.status == 2)
  }
}

/// Esegue il binario `crashbench` costruito insieme alla suite, con la directory dati del volume di
/// prova, e ne raccoglie stato e output.
private func crashbench(
  _ arguments: [String], _ test: TestVolume
) throws -> (status: Int32, stdout: String, stderr: String) {
  let binary = CrashPaths.packageRoot.appending(
    path: ".build/debug/crashbench", directoryHint: .notDirectory)
  try #require(FileManager.default.isExecutableFile(atPath: binary.fileSystemPath))
  let process = Process()
  process.executableURL = binary
  process.arguments = arguments + ["--data-dir", test.dataDirectory.fileSystemPath]
  let stdout = Pipe()
  let stderr = Pipe()
  process.standardOutput = stdout
  process.standardError = stderr
  try process.run()
  process.waitUntilExit()
  let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  return (process.terminationStatus, out, err)
}
