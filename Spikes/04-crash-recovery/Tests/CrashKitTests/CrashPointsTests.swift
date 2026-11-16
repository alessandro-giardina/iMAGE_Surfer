import Foundation
import Testing

@testable import CrashKit

/// Punti di interruzione attesi, scritti qui a mano come oracolo indipendente dal codice che li
/// deriva dal piano.
private let expectedHead = ["X00-plan-torn", "X01-plan", "X02-recheck", "X03-prepare"]
private let expectedSteps = [
  "S01-a", "S01-b", "S01-c",
  "S02-a", "S02-b", "S02-c",
  "S03-a", "S03-b", "S03-c",
  "S04-a", "S04-b", "S04-c",
  "S05-a", "S05-b", "S05-c",
  "S06-a", "S06-b", "S06-c",
  "S07-a", "S07-m", "S07-b", "S07-c",
  "S08-a", "S08-m", "S08-b", "S08-c",
  "S09-a", "S09-b", "S09-c",
  "S10-a", "S10-b", "S10-c",
]
private let expectedCompensation = [
  "K10-a", "K10-b", "K09-a", "K09-b", "K08-a", "K08-b", "K07-a", "K07-b", "K06-a", "K06-b",
  "K05-a", "K05-b", "K04-a", "K04-b", "K03-a", "K03-b", "K02-a", "K02-b", "K01-a", "K01-b",
  "K00-a", "K00-b",
]
private let expectedIds =
  expectedHead + expectedSteps + ["S05-torn"] + expectedCompensation + ["D01", "D02"]

/// Elenco dei punti e iniettore di prova: nessun volume, nessun processo figlio.
@Suite("Elenco enumerato dei punti di interruzione e iniettore dell'arresto")
struct CrashPointsTests {
  @Test("61 punti con ID unici, nell'ordine dichiarato dal piano")
  func sixtyOnePointsInDeclaredOrder() throws {
    let points = try CrashPoints.fixturePoints()

    #expect(points.count == 61)
    #expect(Set(points.map(\.id)).count == points.count)
    #expect(points.map(\.id) == expectedIds)
  }

  @Test("le fasi: 37 di esecuzione, 22 di compensazione e 2 di doppio arresto")
  func phasesFollowTheSections() throws {
    let points = try CrashPoints.fixturePoints()
    let phases = Dictionary(grouping: points, by: \.phase).mapValues { $0.map(\.id) }

    #expect(phases[.esecuzione] == expectedHead + expectedSteps + ["S05-torn"])
    #expect(phases[.compensazione] == expectedCompensation)
    #expect(phases[.doppio] == ["D01", "D02"])
  }

  @Test("Sxx-m esiste solo per le copie S07 e S08")
  func tempPointsOnlyForCopies() throws {
    let points = try CrashPoints.fixturePoints()
    #expect(points.map(\.id).filter { $0.hasSuffix("-m") } == ["S07-m", "S08-m"])
  }

  @Test("ogni descrizione è non vuota, su una riga e senza tabulazioni")
  func descriptionsAreNonEmptySingleLines() throws {
    for point in try CrashPoints.fixturePoints() {
      #expect(!point.description.trimmingCharacters(in: .whitespaces).isEmpty, "\(point.id)")
      #expect(!point.description.contains("\t"), "\(point.id)")
      #expect(!point.description.contains("\n"), "\(point.id)")
    }
  }

  @Test("composite contiene esattamente D01 e D02, con primo e secondo arresto e strategia")
  func compositeDescribesTheDoubleCrashes() {
    #expect(
      CrashPoints.composite == [
        CompositeCrash(id: "D01", firstCrash: "S03-b", secondCrash: "S08-b", strategy: .resume),
        CompositeCrash(
          id: "D02", firstCrash: "S03-b", secondCrash: "K02-a", strategy: .compensate),
      ])
    #expect(CrashPoints.composite("D02")?.secondCrash == "K02-a")
    #expect(CrashPoints.composite("S03-b") == nil)
  }

  @Test("i punti sono derivati dal piano: un passo che non è più una copia perde il punto -m")
  func pointsAreDerivedFromThePlan() throws {
    let definition = try BatchDefinition.load(
      from: CrashPaths.fixtures.appending(
        path: Fixtures.batchFileName, directoryHint: .notDirectory))
    let plan = try CrashPoints.referencePlan(definition: definition)
    let steps = plan.steps.map { step in
      step.id == "S07"
        ? PlannedStep(
          id: step.id, opId: step.opId, kind: .move, source: step.source,
          destination: step.destination, sha256: step.sha256, size: step.size)
        : step
    }
    let changed = BatchPlan(
      planId: plan.planId, batchId: plan.batchId, volumeUUID: plan.volumeUUID, steps: steps,
      directoriesToCreate: plan.directoriesToCreate)

    let ids = CrashPoints.enumerate(changed).map(\.id)
    #expect(ids.count == 60)
    #expect(!ids.contains("S07-m"))
    #expect(ids.contains("S08-m"))
  }

  @Test("l'iniettore chiama l'osservatore a ogni punto e si arresta solo sul bersaglio")
  func injectorStopsOnlyAtTarget() throws {
    var seen: [String] = []
    let injector = CrashInjector(
      target: "S03-b", mode: .throwForTest, observer: { seen.append($0) })

    try injector.hit("S03-a")
    #expect(throws: SimulatedCrash("S03-b")) { try injector.hit("S03-b") }
    #expect(seen == ["S03-a", "S03-b"])

    // Senza bersaglio nessun punto arresta.
    try CrashInjector(target: nil, mode: .throwForTest).hit("S03-b")
  }

  @Test("hitTorn è vero solo per un punto di record troncato che è il bersaglio")
  func hitTornOnlyForTornTarget() {
    #expect(CrashPoints.tornPoints == ["X00-plan-torn", "S05-torn"])
    #expect(CrashInjector(target: "S05-torn", mode: .throwForTest).hitTorn("S05-torn"))
    #expect(CrashInjector(target: "X00-plan-torn", mode: .kill).hitTorn("X00-plan-torn"))
    #expect(!CrashInjector(target: "S05-torn", mode: .throwForTest).hitTorn("X00-plan-torn"))
    #expect(!CrashInjector(target: "S03-b", mode: .throwForTest).hitTorn("S03-b"))
    #expect(!CrashInjector(target: nil, mode: .throwForTest).hitTorn("S05-torn"))
  }
}
