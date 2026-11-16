import Foundation
import Testing

@testable import CrashKit

/// Log di intenti in una directory temporanea nuova del volume ospite.
private struct LogDirectory {
  let directory: URL
  let log: IntentLog

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appending(path: "spike04-intent-log-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    log = IntentLog(
      url: directory.appending(path: IntentLog.fileName, directoryHint: .notDirectory))
  }

  /// Aggiunge in coda al log dei byte arbitrari, senza passare da `IntentLog`.
  func appendRaw(_ text: String) throws {
    let handle = try FileHandle(forWritingTo: log.url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
  }

  func remove() {
    do {
      try FileManager.default.removeItem(at: directory)
    } catch {
      Issue.record("rimozione della directory del log di prova fallita: \(error)")
    }
  }
}

/// Piano costruito a mano: due passi, uno con destinazione e uno `trash` senza.
private func samplePlan() -> BatchPlan {
  BatchPlan(
    planId: UUID(),
    batchId: "lotto-di-prova",
    volumeUUID: "7A1C0E52-0000-4000-8000-000000000001",
    steps: [
      PlannedStep(
        id: "S01", opId: "OP1", kind: .rename, source: "IMG_0001.jpg",
        destination: "2026-08-24_evento_001.jpg", sha256: String(repeating: "a", count: 64),
        size: 1234),
      PlannedStep(
        id: "S09", opId: "OP5", kind: .trash, source: "IMG_0005.jpg", destination: nil,
        sha256: String(repeating: "b", count: 64), size: 4321),
    ],
    directoriesToCreate: ["selezione", "consegna"])
}

/// Un record per ogni valore del discriminante `type`, con i campi facoltativi sia presenti sia
/// assenti, e testo con a capo e lettere accentate.
private func everyRecordType() -> [IntentLog.Record] {
  [
    .plan(samplePlan()),
    .recheck(ok: true, divergences: []),
    .recheck(ok: false, divergences: ["S03 lotto/IMG_0002.jpg: digest diverso dal piano"]),
    .prepare(created: ["selezione", "consegna"]),
    .stepIntent(stepId: "S01", direction: .forward),
    .stepDone(
      stepId: "S09", direction: .forward,
      resultPath: ".Trashes/502/IMG_0005.jpg 11-11-52-954.jpg"),
    .stepDone(stepId: "S01", direction: .compensate, resultPath: "lotto/IMG_0001.jpg"),
    .stepFailed(stepId: "S01", direction: .forward, syscall: "renamex_np", errno: 17),
    .stepFailed(
      stepId: "S09", direction: .compensate, syscall: "trashItem", errno: nil,
      cocoa: "NSCocoaErrorDomain 513 / NSOSStatusErrorDomain -5000", errorClass: "L-locked",
      scope: "locale"),
    .recovery(strategy: "resume", direction: "forward", summary: "riga 1\nriga 2: è già fatto"),
    .decision(.retry),
    .decision(.abandon),
    .outcome(outcome: "completato", reason: nil, trace: []),
    .outcome(
      outcome: "NON_SUPPORTABILE", reason: "stato-non-riconoscibile",
      trace: ["S03 lotto/IMG_0002.jpg=assente", "S03 lotto/selezione/IMG_0002.jpg=assente"]),
    .undoRequested,
  ]
}

@Suite("Log di intenti JSONL con record troncato riconoscibile")
struct IntentLogTests {
  @Test("ogni tipo di record fa il giro completo, una riga JSON per record")
  func everyRecordTypeRoundTrips() throws {
    let directory = try LogDirectory()
    defer { directory.remove() }
    let log = directory.log
    let records = everyRecordType()
    #expect(Set(records.map(\.kind)) == Set(IntentLog.Record.Kind.allCases))

    // Un log che non esiste ancora è vuoto.
    let empty = try log.read()
    #expect(empty.records.isEmpty)
    #expect(empty.tornTail == nil)

    for record in records { try log.append(record) }
    let read = try log.read()
    #expect(read.records == records)
    #expect(read.tornTail == nil)

    // Una riga per record, ciascuna terminata da `\n`, con il discriminante `type`.
    let text = String(decoding: try Data(contentsOf: log.url), as: UTF8.self)
    #expect(text.hasSuffix("\n"))
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
    #expect(lines.count == records.count)
    for (line, record) in zip(lines, records) {
      let object = try #require(
        try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
      #expect(object["type"] as? String == record.kind.rawValue)
      #expect(Data(line.utf8) == (try IntentLog.encodeLine(record)))
    }
  }

  @Test("dopo appendTorn i record precedenti sono intatti e la coda troncata non è un record")
  func tornTailIsRecognized() throws {
    let directory = try LogDirectory()
    defer { directory.remove() }
    let log = directory.log
    let plan = IntentLog.Record.plan(samplePlan())
    let intent = IntentLog.Record.stepIntent(stepId: "S01", direction: .forward)
    let done = IntentLog.Record.stepDone(
      stepId: "S01", direction: .forward, resultPath: "lotto/2026-08-24_evento_001.jpg")

    try log.append(plan)
    try log.append(intent)
    try log.appendTorn(done)

    let line = try IntentLog.encodeLine(done)
    let fragment = line.prefix(line.count / 2)
    #expect(try Data(contentsOf: log.url).suffix(fragment.count) == fragment)

    let read = try log.read()
    #expect(read.records == [plan, intent])
    #expect(read.tornTail == String(decoding: fragment, as: UTF8.self))
    // La lettura non modifica il file.
    #expect(try log.read().tornTail != nil)
  }

  @Test("repairTornTail conserva il frammento come evidenza e il log riprende pulito")
  func repairedLogAcceptsNewRecords() throws {
    let directory = try LogDirectory()
    defer { directory.remove() }
    let log = directory.log
    let plan = IntentLog.Record.plan(samplePlan())
    let intent = IntentLog.Record.stepIntent(stepId: "S05", direction: .forward)
    let torn = IntentLog.Record.stepDone(
      stepId: "S05", direction: .forward, resultPath: "lotto/selezione/2026-08-24_evento_003.jpg")
    let recovery = IntentLog.Record.recovery(
      strategy: "resume", direction: "forward", summary: "ripresa dopo S05-torn")

    try log.append(plan)
    try log.append(intent)
    try log.appendTorn(torn)
    let line = try IntentLog.encodeLine(torn)
    let fragment = line.prefix(line.count / 2)

    let evidence = try #require(try log.repairTornTail())
    #expect(
      evidence.deletingLastPathComponent().fileSystemPath == directory.directory.fileSystemPath)
    #expect(evidence.lastPathComponent.hasPrefix("torn-"))
    #expect(evidence.pathExtension == "txt")
    #expect(try Data(contentsOf: evidence) == fragment)

    // Il log termina con l'ultima riga completa.
    #expect(try Data(contentsOf: log.url).last == 0x0A)
    #expect(try log.repairTornTail() == nil)

    try log.append(recovery)
    let read = try log.read()
    #expect(read.records == [plan, intent, recovery])
    #expect(read.tornTail == nil)
  }

  @Test(
    "senza riparazione, un append fonde il frammento con la riga nuova e nessuno dei due è letto")
  func appendWithoutRepairNeverYieldsTheMergedRecord() throws {
    let directory = try LogDirectory()
    defer { directory.remove() }
    let log = directory.log
    let plan = IntentLog.Record.plan(samplePlan())
    let torn = IntentLog.Record.stepIntent(stepId: "S01", direction: .forward)
    let next = IntentLog.Record.undoRequested

    try log.append(plan)
    try log.appendTorn(torn)
    try log.append(next)

    let tornLine = try IntentLog.encodeLine(torn)
    let merged = tornLine.prefix(tornLine.count / 2) + (try IntentLog.encodeLine(next))
    let read = try log.read()
    #expect(read.records == [plan])
    #expect(read.tornTail == String(decoding: merged, as: UTF8.self))
  }

  @Test("una riga corrotta in mezzo al log lancia logCorrotto con il suo numero")
  func corruptedLineInTheMiddleThrows() throws {
    let directory = try LogDirectory()
    defer { directory.remove() }
    let log = directory.log

    try log.append(.plan(samplePlan()))
    try directory.appendRaw("{\"type\":\"sconosciuto\"}\n")
    try log.append(.undoRequested)

    #expect(throws: IntentLogError.logCorrotto(linea: 2)) { try log.read() }
    #expect(throws: IntentLogError.logCorrotto(linea: 2)) { try log.repairTornTail() }
  }
}
