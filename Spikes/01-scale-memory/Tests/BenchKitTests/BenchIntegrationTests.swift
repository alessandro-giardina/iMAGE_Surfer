import Foundation
import Testing

@testable import BenchKit

/// Esecuzione del binario `bench` reale come processo esterno, con uscite su file.
enum BenchBinary {
  static var url: URL {
    SpikePaths.packageRoot.appending(path: ".build/debug/bench", directoryHint: .notDirectory)
  }

  struct Run {
    var status: Int32
    var standardOutput: String
    var standardError: String
    var outputDirectory: URL

    /// Risultati JSON scritti nella directory di uscita.
    func results() throws -> [MeasurementResult] {
      try FileManager.default.contentsOfDirectory(
        at: outputDirectory, includingPropertiesForKeys: nil
      )
      .filter { $0.pathExtension == "json" }
      .map { try MeasurementResult.decode(from: Data(contentsOf: $0)) }
    }

    /// L'unico risultato scritto, oppure quello che soddisfa `where`.
    func result(where predicate: (MeasurementResult) -> Bool = { _ in true }) throws
      -> MeasurementResult
    {
      let matching = try results().filter(predicate)
      return try #require(
        matching.count == 1 ? matching.first : nil, "risultati: \(matching.count)")
    }
  }

  static func run(_ arguments: [String]) async throws -> Run {
    let scratch = FileManager.default.temporaryDirectory
      .appending(path: "spike01-bench-\(UUID().uuidString)", directoryHint: .isDirectory)
    let output = scratch.appending(path: "runs", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let stdoutURL = scratch.appending(path: "stdout.txt")
    let stderrURL = scratch.appending(path: "stderr.txt")
    FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
    FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

    let process = Process()
    process.executableURL = url
    process.arguments = arguments.map { $0 == "{out}" ? output.path : $0 }
    process.standardOutput = try FileHandle(forWritingTo: stdoutURL)
    process.standardError = try FileHandle(forWritingTo: stderrURL)
    let status = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Int32, any Error>) in
      process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
      do { try process.run() } catch { continuation.resume(throwing: error) }
    }
    return Run(
      status: status, standardOutput: try String(contentsOf: stdoutURL, encoding: .utf8),
      standardError: try String(contentsOf: stderrURL, encoding: .utf8), outputDirectory: output)
  }
}

/// Integrazione del banco sul profilo `smoke`: ogni sottocomando deve produrre misure vere, non
/// soltanto uno stato di uscita zero. Nessuna asserzione su valori assoluti di tempo o memoria,
/// che sono l'oggetto della misura e non del test. In serie: i banchi AppKit si contendono la
/// finestra chiave.
@Suite("Integrazione del banco sul profilo smoke", .serialized)
struct BenchIntegrationTests {
  /// Argomenti comuni: dataset `smoke` condiviso e uscita in una directory temporanea.
  func common() async throws -> [String] {
    let (directory, _) = try await SmokeDataset.prepared()
    return ["--profile", "smoke", "--data", directory.path, "--out", "{out}"]
  }

  /// Controlli validi per ogni sottocomando: schema, identificatore, impronta completa, numero
  /// esatto di ripetizioni, e dispersione completa, finita e calcolata su tutte le ripetizioni.
  func expectWellFormed(
    _ result: MeasurementResult, bench: String, repetitions: Int, metrics: [String]
  ) throws {
    #expect(result.schema == "image-surfer/spike-01/measurement/v1")
    #expect(result.bench == bench)
    #expect(!result.measurementId.isEmpty)
    #expect(result.profile == "smoke")
    try result.host.assertComplete()
    #expect(result.repetitions.count == repetitions, "ripetizioni eseguite")
    for metric in metrics {
      let dispersion = try #require(result.dispersion[metric], "dispersione assente: \(metric)")
      let fields = [
        dispersion.min, dispersion.median, dispersion.p95, dispersion.max, dispersion.mean,
        dispersion.stddev, dispersion.iqr,
      ]
      let allFinite = fields.allSatisfy { $0.isFinite }
      #expect(allFinite, "campo non finito in \(metric)")
      #expect(dispersion.n == result.repetitions.count, "n di \(metric)")
    }
    for (metric, dispersion) in result.dispersion {
      #expect(dispersion.n == result.repetitions.count, "n di \(metric)")
      let allFinite = [dispersion.p95, dispersion.stddev, dispersion.iqr].allSatisfy { $0.isFinite }
      #expect(allFinite, "campo non finito in \(metric)")
    }
  }

  @Test(
    "first-screen: ripetizioni su cartelle diverse, anteprime pronte prima del fotogramma",
    .timeLimit(.minutes(5)))
  func firstScreen() async throws {
    // Porta di vista ridotta: 12 elementi in vista su 24 per cartella, così anche il secondo
    // blocco dell'enumerazione (aggiunta di elementi durante la misura) viene eseguito.
    let run = try await BenchBinary.run(
      ["first-screen", "--repetitions", "2", "--window", "1000x600"] + common())
    #expect(run.status == 0, "\(run.standardError)")
    let result = try run.result()
    try expectWellFormed(
      result, bench: "first-screen", repetitions: 2,
      metrics: ["firstScreenMs", "thumbnailsReadyMs", "firstUrlsReadyMs"])
    for repetition in result.repetitions {
      let ready = try #require(repetition.values["thumbnailsReadyMs"])
      let screen = try #require(repetition.values["firstScreenMs"])
      #expect(ready > 0 && screen > 0)
      #expect(ready <= screen, "la composizione non può precedere le anteprime")
    }
    let folders = try #require(result.parameters["folders"]).split(separator: ",")
    #expect(folders.count == 2 && Set(folders).count == 2, "cartelle: \(folders)")
    #expect(result.parameters["frameOracle"]?.contains("CATransaction") == true)
    #expect(result.parameters["visibleCount"] == "12")
    #expect(run.standardOutput.contains(result.measurementId))
  }

  @Test(
    "selection-latency: spostamenti richiesti, misurati a code sature",
    .timeLimit(.minutes(5)))
  func selectionLatency() async throws {
    let run = try await BenchBinary.run(["selection-latency", "--moves", "12"] + common())
    #expect(run.status == 0, "\(run.standardError)")
    let result = try run.result()
    try expectWellFormed(
      result, bench: "selection-latency", repetitions: 12,
      metrics: ["selectionLatencyMs", "selectionHandledMs"])
    #expect(result.parameters["moves"] == "12")
    let width = try #require(Int(result.parameters["queueWidth"] ?? ""))
    let depths = try #require(result.derived["queueDepthAtStart"]?.object)
    for queue in [
      "io", result.parameters["thumbnailPath"] == "quicklook" ? "quicklook" : "decode", "vision",
    ] {
      let depth = try #require(depths[queue]?.number, "profondità di \(queue) assente")
      #expect(Int(depth) > width, "la coda \(queue) non era satura: \(depth)")
    }
    #expect(result.derived["movesOver100ms"]?.number != nil)
  }

  @Test(
    "scroll-memory: picco sopra la baseline e pendenza con intervallo di confidenza",
    .timeLimit(.minutes(5)))
  func scrollMemory() async throws {
    let run = try await BenchBinary.run(
      ["scroll-memory", "--repetitions", "2", "--long-session", "0.25"] + common())
    #expect(run.status == 0, "\(run.standardError)")
    let result = try run.result()
    try expectWellFormed(
      result, bench: "scroll-memory", repetitions: 2,
      metrics: ["peakFootprintBytes", "plateauFootprintBytes", "marginalBytesPer1000Items"])
    let baseline = try #require(result.derived["baselineFootprintBytes"]?.number)
    for repetition in result.repetitions {
      let peak = try #require(repetition.values["peakFootprintBytes"])
      #expect(peak > baseline)
    }
    let longSession = try #require(result.derived["longSession"]?.object)
    #expect(longSession["slopeDistinguishableFromZero"]?.bool != nil)
    #expect(longSession["longSessionSlopeBytesPerHour"]?.number?.isFinite == true)
    #expect(longSession["slopeConfidenceInterval95"]?.number?.isFinite == true)
    #expect(longSession["windowSlopesBytesPerHour"]?.object != nil)
  }

  @Test(
    "retention-band: 15 coppie con soglie distinte e raccomandazione esplicita",
    .timeLimit(.minutes(15)))
  func retentionBand() async throws {
    let run = try await BenchBinary.run(["retention-band", "--cycles", "1"] + common())
    #expect(run.status == 0, "\(run.standardError)")
    let result = try run.result()
    try expectWellFormed(
      result, bench: "retention-band", repetitions: 15,
      metrics: ["regeneratedSmall", "regeneratedMedium", "steadyFootprintBytes"])
    for row in result.repetitions {
      let enter = try #require(row.values["enterBand"])
      let exit = try #require(row.values["exitBand"])
      #expect(exit > enter)
      #expect(row.values["regeneratedSmall"] != nil && row.values["regeneratedMedium"] != nil)
    }
    let recommendation = try #require(result.derived["recommendation"], "campo assente")
    if recommendation.isNull {
      #expect(result.derived["recommendationReason"]?.string?.isEmpty == false)
    } else {
      #expect(recommendation["regeneratedSmall"]?.number == 0)
    }
    #expect(result.derived["noHysteresisReference"]?.array?.count == 6)
    #expect(result.derived["supplementaryRows"]?.array?.count == 5)
  }

  @Test(
    "item-cost su una cella: n elementi, picco transitorio e delta trattenuto distinti",
    .timeLimit(.minutes(5)))
  func itemCostCell() async throws {
    let run = try await BenchBinary.run(
      ["item-cost", "--cell", "decode:jpeg:M", "--n", "3"] + common())
    #expect(run.status == 0, "\(run.standardError)")
    let result = try run.result()
    try expectWellFormed(
      result, bench: "item-cost", repetitions: 3,
      metrics: ["transientPeakDeltaBytes", "retainedDeltaBytes", "wallClockMs"])
    let limit = try #require(result.derived["perItemLimitBytes"]?.number)
    #expect(limit > (result.dispersion["transientPeakDeltaBytes"]?.p95 ?? .infinity))
    #expect(result.derived["perItemLimitFormula"]?.string?.isEmpty == false)
    // Il campionatore deve osservare l'operazione: un picco nullo o inferiore all'anteprima
    // prodotta significa che la misura non contiene il lavoro.
    let transient = try #require(result.dispersion["transientPeakDeltaBytes"])
    #expect(transient.median > 0)
    #expect(result.derived["peakNotObservedCount"]?.number == 0)
    #expect(result.derived["operationFailedCount"]?.number == 0)
  }

  @Test(
    "item-cost --all: una riga per cella non vuota, limite oltre il p95 e formula",
    .timeLimit(.minutes(10)))
  func itemCostAll() async throws {
    let run = try await BenchBinary.run(["item-cost", "--all", "--n", "1"] + common())
    #expect(run.status == 0, "\(run.standardError)")
    let merged = try run.result { $0.parameters["mode"] == "all" }
    let (_, manifest) = try await SmokeDataset.prepared()
    let nonEmpty =
      manifest.folders.itemCostPool.cells.filter { $0.uniqueCount > 0 }.count
      + manifest.folders.anomalous.cells.filter { $0.uniqueCount > 0 }.count
    let cells = try #require(merged.derived["cells"]?.array)
    #expect(cells.count == nonEmpty * WorkKind.measured.count)
    #expect(merged.repetitions.count == cells.count)
    var identifiers: Set<String> = []
    for cell in cells {
      let p95 = try #require(cell["transientPeakDeltaBytes"]?["p95"]?.number)
      let limit = try #require(cell["perItemLimitBytes"]?.number)
      #expect(limit > p95, "cella \(cell["cell"]?.string ?? "?")")
      #expect(cell["perItemLimitFormula"]?.string?.isEmpty == false)
      #expect(cell["retainedDeltaBytes"]?.object != nil)
      identifiers.insert(try #require(cell["measurementId"]?.string))
    }
    #expect(identifiers.count == cells.count, "un measurementId di sottoprocesso per cella")
    #expect(cells.contains { $0["resolutionClass"]?.string == "anomalous" })
    #expect(merged.derived["instrumentationFloor"]?["measurementId"]?.string != nil)
  }

  @Test("senza manifest il banco esce con stato 1 e rimanda a gen-dataset")
  func missingDatasetFails() async throws {
    let empty = FileManager.default.temporaryDirectory
      .appending(path: "spike01-empty-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    let run = try await BenchBinary.run(
      ["first-screen", "--profile", "smoke", "--data", empty.path, "--out", "{out}"])
    #expect(run.status == 1)
    #expect(run.standardError.contains("gen-dataset"))
    #expect(try run.results().isEmpty)
  }

  @Test("un'opzione sconosciuta esce con stato 2 e stampa l'uso")
  func unknownOptionPrintsUsage() async throws {
    let run = try await BenchBinary.run(["first-screen", "--frobnicate", "1"])
    #expect(run.status == 2)
    #expect(run.standardError.contains("uso: bench"))
  }
}
