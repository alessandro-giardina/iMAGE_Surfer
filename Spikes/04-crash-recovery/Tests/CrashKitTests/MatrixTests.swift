import Foundation
import Testing

@testable import CrashKit

/// Parti pure della matrice: celle, selezione delle esecuzioni parziali, oracoli sull'istantanea,
/// analisi dell'output del recupero e unione delle parti. Nessun volume: l'esecuzione reale è
/// provata sul binario dai test di integrazione.
@Suite("Matrice: celle, selezione, oracoli e unione delle parti")
struct MatrixTests {
  let points: [CrashPoint]

  init() throws {
    points = try CrashPoints.fixturePoints()
  }

  @Test("il profilo full ha 98 celle di base e 48 di perturbazione, con ID unici")
  func fullProfileCells() {
    let cells = Matrix.cells(points: points, profile: .full)
    let ids = cells.map(\.id)
    #expect(cells.count == 146)
    #expect(Set(ids).count == ids.count)
    #expect(cells.filter { $0.perturbation == nil }.count == 98)
    #expect(cells.filter { $0.perturbation != nil }.count == 48)
    #expect(ids.contains("X00-plan-torn/resume") && ids.contains("X00-plan-torn/compensate"))
    #expect(ids.contains("K05-a/compensate") && !ids.contains("K05-a/resume"))
    #expect(ids.contains("D01/resume") && !ids.contains("D01/compensate"))
    #expect(ids.contains("D02/compensate") && !ids.contains("D02/resume"))
    #expect(ids.contains("S10-c/compensate/L-trash-emptied"))
    #expect(ids.firstIndex(of: "D02/compensate") == 97, "le celle di base vengono prima")
  }

  @Test("il profilo smoke ha 6 punti con le loro strategie e 2 perturbazioni")
  func smokeProfileCells() {
    let ids = Matrix.cells(points: points, profile: .smoke).map(\.id)
    #expect(
      ids == [
        "X01-plan/resume", "X01-plan/compensate", "S03-b/resume", "S03-b/compensate",
        "S07-m/resume", "S07-m/compensate", "S10-c/resume", "S10-c/compensate",
        "K05-a/compensate", "D01/resume", "S06-b/resume/G-volume-missing",
        "S06-b/resume/L-locked",
      ])
  }

  @Test("--only e --shard: modelli fnmatch, parti disgiunte che coprono la selezione")
  func selection() throws {
    let cells = Matrix.cells(points: points, profile: .full)
    let base = try Matrix.select(cells, only: ["*/resume", "*/compensate"], shard: nil)
    #expect(base.count == 98 && base.allSatisfy { $0.perturbation == nil })
    #expect(try Matrix.select(cells, only: ["*/*/*"], shard: nil).count == 48)
    #expect(
      try Matrix.select(cells, only: ["S06-b/resume"], shard: nil).map(\.id) == ["S06-b/resume"])
    #expect(throws: MatrixError.patternMatchesNothing("S99-*")) {
      try Matrix.select(cells, only: ["S99-*"], shard: nil)
    }

    let order = Dictionary(uniqueKeysWithValues: cells.map(\.id).enumerated().map { ($1, $0) })
    let count = 7
    var seen: [String] = []
    for index in 1...count {
      let shard = try #require(MatrixShard("\(index)/\(count)"))
      let positions = try Matrix.select(cells, only: [], shard: shard).map { order[$0.id] ?? -1 }
      #expect(positions == positions.sorted() && positions.allSatisfy { $0 % count == index - 1 })
      seen += positions.map { cells[$0].id }
    }
    #expect(seen.count == cells.count && Set(seen) == Set(cells.map(\.id)))
    #expect(MatrixShard("0/3") == nil && MatrixShard("4/3") == nil && MatrixShard("1/0") == nil)
  }

  @Test(
    "la separazione rilevata confronta le liste osservata e riferita",
    arguments: [
      ([String](), [String](), SeparationDetection.nessuna),
      (["OP2"], ["OP2"], .rilevata),
      (["OP2", "OP5"], ["OP2"], .nonRilevata),
      (["OP2"], ["OP2", "OP5"], .falsaSegnalazione),
      (["OP2"], ["OP5"], .nonRilevata),
      ([], ["OP5"], .falsaSegnalazione),
    ])
  func separationDetection(observed: [String], reported: [String], expected: SeparationDetection) {
    #expect(Matrix.detection(observed: observed, reported: reported) == expected)
  }

  @Test("posizioni sull'istantanea: la regola del piano, senza riconoscitore")
  func positionsOnSnapshot() throws {
    let plan = try CrashPoints.referencePlan(
      definition: BatchDefinition.load(
        from: CrashPaths.fixtures.appending(
          path: Fixtures.batchFileName, directoryHint: .notDirectory)))
    let s03 = try #require(plan.step("S03"))
    let s07 = try #require(plan.step("S07"))
    let s09 = try #require(plan.step("S09"))
    func file(_ sha256: String) -> Snapshot.Entry {
      Snapshot.Entry(
        kind: .file, size: 1, sha256: sha256, mode: 0o100644, flags: 0, mtime: 0, birthtime: 0,
        inode: 1, xattrs: [:])
    }
    var snapshot = Snapshot(entries: [
      "lotto/selezione/IMG_0002.jpg": file(s03.sha256),
      "lotto/IMG_0004.jpg": file(s07.sha256),
      "lotto/consegna/IMG_0004.jpg": file(s07.sha256),
      "@cestino/IMG_0005.jpg": file(s09.sha256),
      "@cestino/IMG_0005.jpg 12-00-00-000.jpg": file(s09.sha256),
    ])
    #expect(Matrix.position(of: s03, in: snapshot) == .destinazione)
    #expect(Matrix.position(of: s07, in: snapshot) == .destinazione, "copia: dest se la copia c'è")
    #expect(Matrix.position(of: s09, in: snapshot) == .ambigua, "due voci del Cestino")
    #expect(Matrix.separations(plan: plan, snapshot: snapshot).contains("OP2"), "dest e ass")
    let s04 = try #require(plan.step("S04"))
    snapshot.entries["lotto/selezione/IMG_0002.xmp"] = file(s04.sha256)
    #expect(!Matrix.separations(plan: plan, snapshot: snapshot).contains("OP2"), "dest e dest")
    snapshot.entries["lotto/selezione/IMG_0002.jpg"] = file("estraneo")
    #expect(Matrix.position(of: s03, in: snapshot) == .assente, "digest diverso: non è il file")
  }

  @Test("l'output a formato fisso del recupero si analizza riga per riga")
  func parsesRecoveryOutput() throws {
    let output = try #require(
      RecoveryOutput.parse([
        "DOPPIO-ARRESTO D01 primo=S03-b secondo=S08-b strategia=resume",
        "RECUPERO strategia=resume direzione=forward", "RECORD-TRONCATO no",
        "DIVERGENZA S03 log=non-fatto disco=fatto", "PASSO S08 non-fatto -> fatto",
        "PASSO S09 non-fatto -> saltato classe=L-locked ambito=locale",
        "COPPIA OP5 immagine=orig sidecar=cest SEPARATA", "SEPARAZIONI-ALL-AVVIO nessuna",
        "SEPARAZIONI-RESIDUE OP5", "ESITO parzialmente-recuperato",
        "TRACCIA passo saltato per errore locale: L-locked",
      ]))
    #expect(output.direction == "forward" && output.recordTroncato == false)
    #expect(output.divergences == ["S03 log=non-fatto disco=fatto"])
    #expect(output.stepOrder == ["S08", "S09"])
    #expect(
      output.steps["S09"]
        == CellStep(
          start: "non-fatto", final: "saltato", errorClass: "L-locked", errorScope: "locale"))
    #expect(output.pairs == [ReportedPair(opId: "OP5", image: "orig", sidecar: "cest")])
    #expect(output.separationsAtStart.isEmpty && output.separationsResidual == ["OP5"])
    #expect(output.outcome == .parzialmenteRecuperato && output.reason == nil)
    #expect(output.trace == ["passo saltato per errore locale: L-locked"])
    #expect(
      RecoveryOutput.parse(["ESITO NON_SUPPORTABILE motivo=nessun-esito-applicabile"])?.reason
        == "nessun-esito-applicabile")
    #expect(RecoveryOutput.parse(["RECUPERO strategia=resume direzione=forward"]) == nil)
  }

  @Test("le parti di una misura si uniscono una volta sola, in ordine di profilo")
  func combinesParts() throws {
    let canonical = Matrix.cells(points: points, profile: .smoke).map(\.id)
    let first = measurement(cells: Array(canonical.suffix(5)), startedAt: "2026-11-16T10:00:00Z")
    let second = measurement(cells: Array(canonical.prefix(7)), startedAt: "2026-11-16T09:00:00Z")

    let combined = try MeasurementResult.combine(
      [("b.json", first), ("a.json", second)], canonicalCells: canonical)
    #expect(combined.cells.map(\.cellId) == canonical)
    #expect(combined.coverage.complete && combined.coverage.missingCells.isEmpty)
    #expect(combined.startedAt == "2026-11-16T09:00:00Z" && combined.durationSeconds == 20)
    #expect(combined.parts?.map(\.file) == ["a.json", "b.json"] && combined.selection == nil)
    #expect(combined.summary.cells == canonical.count)

    let partial = try MeasurementResult.combine([("a.json", second)], canonicalCells: canonical)
    #expect(
      !partial.coverage.complete && partial.coverage.missingCells == Array(canonical.suffix(5)))

    var overlapping = first
    overlapping.cells = [first.cells[0]] + second.cells.prefix(1)
    #expect(throws: MeasurementCombineError.self) {
      try MeasurementResult.combine(
        [("a.json", second), ("c.json", overlapping)], canonicalCells: canonical)
    }
    var otherHost = first
    otherHost.host.osBuild = "altro"
    #expect(throws: MeasurementCombineError.self) {
      try MeasurementResult.combine(
        [("a.json", second), ("d.json", otherHost)], canonicalCells: canonical)
    }
    var otherId = first
    otherId.measurementId = "crash-matrix-20261116T090000Z-ffffffff"
    #expect(throws: MeasurementCombineError.self) {
      try MeasurementResult.combine(
        [("a.json", second), ("e.json", otherId)], canonicalCells: canonical)
    }
  }

  @Test("measurementId: forma crash-matrix-<UTC>-<8 esadecimali>")
  func measurementIdentifier() {
    let id = MeasurementResult.newMeasurementId(at: Date(timeIntervalSince1970: 0))
    #expect(id.hasPrefix("crash-matrix-19700101T000000Z-"))
    #expect(MeasurementResult.isValidMeasurementId(id))
    #expect(!MeasurementResult.isValidMeasurementId("crash-matrix-1970-0000"))
  }

  /// Una misura sintetica con le celle date, ciascuna con un esito `completato`.
  private func measurement(cells ids: [String], startedAt: String) -> MeasurementResult {
    let cells = ids.map { id in
      MeasurementCell(
        cellId: id, point: String(id.prefix { $0 != "/" }), phase: .esecuzione, strategy: .resume,
        perturbation: nil, target: nil, applicable: true, notApplicableReason: nil,
        repetitions: 1, outcomes: ["completato": 1], reasons: [:], direction: "forward",
        recordTroncato: false, divergences: [], trace: [], steps: [:], pairs: [:],
        separationsAtCrash: [], separationsBeforePerturbation: nil, separationsAtFirstCrash: nil,
        separationsReported: [], separationsResidual: [], separationDetected: .nessuna,
        compensation: .notAttempted, resumeMatchesExpected: true, resumeMismatches: [],
        recognitionError: false, recognitionErrors: [], followUp: nil, errorClass: nil,
        errorScope: nil, errnoObserved: nil, cocoaObserved: nil, syscallObserved: nil,
        failures: [], nonDeterministic: false, repetitionNotes: [], pointReached: true,
        snapshotsNotSettled: [],
        settle: SettleStatistics(captures: 3, changed: 0, maxLastChangeSeconds: 0),
        benchErrors: [], durationSeconds: 3)
    }
    return MeasurementResult(
      measurementId: "crash-matrix-20261116T090000Z-0123abcd", spike: MeasurementResult.spikeName,
      host: HostFingerprint(model: "Mac", osVersion: "27.2", osBuild: "26B123", uid: 502),
      volume: .workVolume, fixtureManifestSha256: "abc", profile: .smoke, repetitions: 1,
      startedAt: startedAt, durationSeconds: 10, points: points, settleParameters: .standard,
      selection: MatrixSelection(only: ["*"], shard: nil), preparation: [], parts: nil,
      coverage: .of(present: ids, expected: ids), summary: .of(cells), cells: cells)
  }
}
