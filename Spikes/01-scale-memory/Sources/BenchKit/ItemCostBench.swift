import CoreGraphics
import Foundation

/// Una cella del costo per elemento: tipo di lavoro × formato × classe di risoluzione
/// (`S`, `M`, `L`, oppure `anomalous` per gli elementi anomali).
public struct ItemCostCell: Hashable, Sendable, CustomStringConvertible {
  public let work: WorkKind
  public let format: ImageFormat
  public let resolutionClass: String

  public init(work: WorkKind, format: ImageFormat, resolutionClass: String) {
    self.work = work
    self.format = format
    self.resolutionClass = resolutionClass
  }

  /// Interpreta `<lavoro>:<formato>:<classe>`, per esempio `decode:jpeg:M`.
  public init?(parsing label: String) {
    let parts = label.split(separator: ":").map(String.init)
    guard parts.count == 3, let work = WorkKind(rawValue: parts[0]),
      let format = ImageFormat(rawValue: parts[1]),
      ResolutionClass(rawValue: parts[2]) != nil || parts[2] == "anomalous"
    else { return nil }
    self.init(work: work, format: format, resolutionClass: parts[2])
  }

  public var description: String { "\(work.rawValue):\(format.rawValue):\(resolutionClass)" }
}

/// `bench item-cost`: costo in memoria di un singolo elemento per tipo di lavoro, formato e classe
/// di risoluzione, e limite per singolo elemento derivato dalla coda osservata (ADR-009, NFR-P10).
///
/// Ogni elemento registra due grandezze distinte: `transientPeakDeltaBytes`, il picco durante
/// l'operazione meno la baseline, che serve all'ammissione perché l'ammissione precede
/// l'esecuzione; e `retainedDeltaBytes`, il footprint dopo il drenaggio meno la baseline, che
/// rivela crescita di cache o mancato rilascio.
public final class ItemCostBench {
  public static let name = "item-cost"
  public static let formula =
    "perItemLimitBytes = max(1 MB, arrotondamento per eccesso al MB di "
    + "max(p95(transientPeakDeltaBytes) × 4, max(transientPeakDeltaBytes) × 1,5)), "
    + "con 1 MB = 1.048.576 byte"
  static let megabyte = 1_048_576.0
  static let samplerIntervalMs = 5.0

  private let options: BenchOptions
  private let dataset: LoadedDataset

  public init(options: BenchOptions) throws {
    self.options = options
    dataset = try LoadedDataset.load(options)
  }

  /// Limite per singolo elemento dalla formula dichiarata.
  public static func perItemLimit(p95: Double, max: Double) -> Double {
    let raw = Swift.max(Swift.max(0, p95) * 4, Swift.max(0, max) * 1.5)
    return Swift.max(megabyte, (raw / megabyte).rounded(.up) * megabyte)
  }

  // MARK: - Una cella

  /// Misura una cella su `n` elementi del pool. Se il pool ne ha meno di `n` li riusa a rotazione
  /// e lo dichiara in `distinctItems`. La cella degli anomali usa tutti e soli gli anomali.
  public func runCell(_ cell: ItemCostCell, n requested: Int) throws -> MeasurementResult {
    let startedAt = Date()
    let host = HostFingerprint.collect(volumeContaining: dataset.directory)
    try host.assertComplete()
    let pool = try items(for: cell)
    guard !pool.isEmpty else {
      throw BenchError.invalidOption("nessun elemento nel dataset per la cella \(cell)")
    }
    let n = cell.resolutionClass == "anomalous" ? pool.count : requested
    let side = GridGeometry(viewport: options.window).itemSide
    let scale = options.thumbnailScale
    let cacheDirectory = FileManager.default.temporaryDirectory
      .appending(path: "spike01-store-\(ProcessInfo.processInfo.processIdentifier)")
    try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: cacheDirectory) }

    // Il campionatore va creato prima di ogni baseline (riserva la propria memoria).
    let sampler = FootprintSampler(intervalMs: Self.samplerIntervalMs, reservedSamples: 4_096)

    // Elemento di riscaldamento non misurato: il costo una tantum (caricamento di modelli e
    // codec) è riportato a parte e non entra nella stima per elemento. Quando il pool lo
    // consente è un elemento che non verrà misurato, così non scalda la cache di Quick Look per
    // un elemento misurato.
    let warmupIndex = pool.count > n ? n : pool.count - 1
    let warmup = measureItem(
      cell.work, url: pool[warmupIndex], side: side, scale: scale, cacheDirectory: cacheDirectory,
      sampler: sampler)

    var repetitions: [Repetition] = []
    for index in 0..<n {
      let url = pool[index % pool.count]
      let thermalAtStart = ThermalState.current
      let flags = RepetitionEnvironment.flags()
      let item = measureItem(
        cell.work, url: url, side: side, scale: scale, cacheDirectory: cacheDirectory,
        sampler: sampler)
      var itemFlags = flags
      itemFlags["didNotSettle"] = !item.settled
      itemFlags["baselineNotQuiet"] = !item.baselineQuiet
      itemFlags["operationFailed"] = item.failure != nil
      itemFlags["peakNotObserved"] = item.outputBytes > 0 && item.transient < item.outputBytes
      if let failure = item.failure {
        FileHandle.standardError.write(Data("  elemento \(index) di \(cell): \(failure)\n".utf8))
      }
      repetitions.append(
        Repetition(
          index: index,
          values: [
            "transientPeakDeltaBytes": item.transient,
            "retainedDeltaBytes": item.retained,
            "wallClockMs": item.wallClockMs,
            "outputBytes": item.outputBytes,
          ],
          flags: itemFlags, thermalStateAtStart: thermalAtStart, thermalStateAtEnd: .current))
    }

    let dispersion = MeasurementResult.dispersion(of: repetitions)
    let transient = dispersion["transientPeakDeltaBytes"]
    let limit = Self.perItemLimit(p95: transient?.p95 ?? 0, max: transient?.max ?? 0)
    var parameters: [String: String] = [
      "cell": cell.description, "work": cell.work.rawValue, "format": cell.format.rawValue,
      "resolutionClass": cell.resolutionClass, "n": "\(n)",
      "distinctItems": "\(min(n, pool.count))", "samplerIntervalMs": "\(Self.samplerIntervalMs)",
      "warmupItem": pool[warmupIndex].lastPathComponent,
      "warmupItemAlsoMeasured": "\(warmupIndex < n)",
      "outputLifetime": "l'uscita dell'operazione resta viva fino all'ultima lettura del picco",
      "baselineRule": "mediana di 20 campioni consecutivi entro l'1%, scadenza 5 s",
      "settleRule": "rientro entro baseline + 1 MB dopo il drenaggio del pool, scadenza 5 s",
      "thumbnailScale": "\(scale)", "maxPixelSize": "\(Int((side * scale).rounded()))",
      "memoryMetric": "phys_footprint (task_info TASK_VM_INFO)",
    ]
    if let pixels = items(pixelsFor: cell) { parameters["pixels"] = pixels.description }
    return MeasurementResult(
      bench: Self.name, startedAt: startedAt, finishedAt: Date(),
      profile: options.profile.rawValue, datasetManifestDigest: dataset.manifestDigest,
      host: host, parameters: parameters, repetitions: repetitions, dispersion: dispersion,
      derived: [
        "cell": .string(cell.description),
        "perItemLimitBytes": .number(limit),
        "perItemLimitFormula": .string(Self.formula),
        "perItemLimitInputs": .object([
          "p95TransientPeakDeltaBytes": .number(transient?.p95 ?? 0),
          "maxTransientPeakDeltaBytes": .number(transient?.max ?? 0),
        ]),
        "warmupTransientPeakDeltaBytes": .number(warmup.transient),
        "warmupRetainedDeltaBytes": .number(warmup.retained),
        "didNotSettleCount": .int(repetitions.filter { $0.flags["didNotSettle"] == true }.count),
        "operationFailedCount": .int(
          repetitions.filter { $0.flags["operationFailed"] == true }.count),
        "peakNotObservedCount": .int(
          repetitions.filter { $0.flags["peakNotObserved"] == true }.count),
      ])
  }

  private struct ItemMeasurement {
    var transient: Double
    var retained: Double
    var wallClockMs: Double
    var outputBytes: Double
    var settled: Bool
    var baselineQuiet: Bool
    var failure: String?
  }

  /// Misura un elemento. Il thread del campionatore parte **prima** della baseline, così la sua
  /// memoria è nella baseline e non viene attribuita all'operazione; l'uscita dell'operazione
  /// resta viva fino all'ultima lettura del picco; l'ingresso preparato resta vivo fino alla
  /// lettura del delta trattenuto. Un'operazione che fallisce è un dato marcato, non un errore
  /// che interrompe la cella.
  private func measureItem(
    _ work: WorkKind, url: URL, side: CGFloat, scale: CGFloat, cacheDirectory: URL,
    sampler: FootprintSampler
  ) -> ItemMeasurement {
    let prepared = work.prepare(url, side: side, scale: scale)
    sampler.start(baseline: 0)
    let (baseline, quiet) = Self.quietBaseline()
    let start = BenchClock.now()
    var endReading: UInt64 = 0
    var outputBytes = 0
    var failure: String?
    autoreleasepool {
      do {
        let output = try work.perform(
          url, prepared: prepared, side: side, scale: scale, cacheDirectory: cacheDirectory)
        outputBytes = output.outputBytes
        // Lettura all'ultimo istante con l'uscita ancora viva: un'operazione più breve
        // dell'intervallo del campionatore non sfugge alla misura.
        withExtendedLifetime(output) { endReading = FootprintSampler.physFootprint() }
      } catch {
        failure = "\(error)"
        endReading = FootprintSampler.physFootprint()
      }
    }
    let end = BenchClock.now()
    var after = FootprintSampler.physFootprint()
    let deadline = end + 5_000_000_000
    while Double(after) > Double(baseline) + Self.megabyte && BenchClock.now() < deadline {
      usleep(5_000)
      after = FootprintSampler.physFootprint()
    }
    let trace = sampler.stop()
    withExtendedLifetime(prepared) {}
    let during = trace.samples(from: start, to: end + UInt64(Self.samplerIntervalMs * 1e6))
    let peak = max(during.map(\.physFootprintBytes).max() ?? 0, endReading)
    return ItemMeasurement(
      transient: max(0, Double(peak) - Double(baseline)),
      retained: Double(after) - Double(baseline),
      wallClockMs: BenchClock.milliseconds(from: start, to: end),
      outputBytes: Double(outputBytes),
      settled: Double(after) <= Double(baseline) + Self.megabyte,
      baselineQuiet: quiet, failure: failure)
  }

  /// Baseline in quiete: mediana di 20 letture consecutive a 5 ms entro l'1% l'una dall'altra,
  /// con scadenza di 5 s (oltre la quale si usa l'ultima finestra e lo si dichiara).
  static func quietBaseline() -> (UInt64, Bool) {
    var window: [Double] = []
    let deadline = BenchClock.now() + 5_000_000_000
    while true {
      window.append(Double(FootprintSampler.physFootprint()))
      if window.count > 20 { window.removeFirst() }
      if window.count == 20, let low = window.min(), let high = window.max(),
        high - low <= low * 0.01
      {
        return (UInt64(Dispersion(window)!.median), true)
      }
      if BenchClock.now() > deadline {
        return (UInt64(Dispersion(window)?.median ?? 0), false)
      }
      usleep(5_000)
    }
  }

  private func items(for cell: ItemCostCell) throws -> [URL] {
    let folder =
      cell.resolutionClass == "anomalous"
      ? dataset.manifest.folders.anomalous : dataset.manifest.folders.itemCostPool
    return try dataset.index(of: folder)
      .filter { $0.format == cell.format && $0.resolutionClass == cell.resolutionClass }
      .map { dataset.folderURL(folder.name).appending(path: $0.name) }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  private func items(pixelsFor cell: ItemCostCell) -> PixelSize? {
    let folder =
      cell.resolutionClass == "anomalous"
      ? dataset.manifest.folders.anomalous : dataset.manifest.folders.itemCostPool
    return folder.cells.first {
      $0.format == cell.format && $0.resolutionClass == cell.resolutionClass
    }?.pixels
  }

  // MARK: - Tutte le celle

  /// Tutte le celle non vuote del pool per ogni tipo di lavoro, più la cella degli anomali.
  public func allCells() -> [ItemCostCell] {
    var cells: [ItemCostCell] = []
    for work in WorkKind.measured {
      for cell in dataset.manifest.folders.itemCostPool.cells where cell.uniqueCount > 0 {
        cells.append(
          ItemCostCell(work: work, format: cell.format, resolutionClass: cell.resolutionClass))
      }
      for cell in dataset.manifest.folders.anomalous.cells where cell.uniqueCount > 0 {
        cells.append(ItemCostCell(work: work, format: cell.format, resolutionClass: "anomalous"))
      }
    }
    return cells
  }

  /// Rilancia `executable` come sottoprocesso una cella per volta e unisce i risultati. La
  /// separazione di processo è deliberata: il footprint è una grandezza dell'intero processo, e
  /// misurare celle diverse nello stesso processo contaminerebbe la baseline con la cache
  /// accumulata dalle celle precedenti.
  public func runAll(n: Int, executable: URL) throws -> MeasurementResult {
    let startedAt = Date()
    let host = HostFingerprint.collect(volumeContaining: dataset.directory)
    try host.assertComplete()
    let scratch = FileManager.default.temporaryDirectory
      .appending(path: "spike01-item-cost-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: scratch) }
    let writer = ResultWriter(runsDirectory: options.outputDirectory, output: { _ in })

    func runSubprocess(_ cell: ItemCostCell, index: Int) throws -> MeasurementResult {
      let output = scratch.appending(path: "\(index)")
      let process = Process()
      process.executableURL = executable
      process.arguments = [
        Self.name, "--cell", cell.description, "--n", "\(n)", "--data",
        dataset.directory.path, "--profile", options.profile.rawValue, "--out", output.path,
        "--scale", "\(options.thumbnailScale)",
      ]
      process.standardOutput = FileHandle.nullDevice
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        throw BenchError.measurementFailed(
          "il sottoprocesso della cella \(cell) è uscito con stato \(process.terminationStatus)")
      }
      let file = try FileManager.default.contentsOfDirectory(
        at: output, includingPropertiesForKeys: nil
      ).first { $0.pathExtension == "json" }
      guard let file else {
        throw BenchError.measurementFailed("nessun risultato dal sottoprocesso della cella \(cell)")
      }
      let result = try MeasurementResult.decode(from: Data(contentsOf: file))
      try writer.write(result)
      return result
    }

    // Cella di controllo: il fondo della strumentazione, misurato con le stesse regole.
    let control = try runSubprocess(
      ItemCostCell(work: .noop, format: .jpeg, resolutionClass: "S"), index: -1)
    let floor = Self.row(of: control)
    print(
      String(
        format: "  controllo noop: picco transitorio mediano %.3f MB, p95 %.3f MB (%@)",
        (floor.values["transientPeakMedianBytes"] ?? 0) / 1e6,
        (floor.values["transientPeakP95Bytes"] ?? 0) / 1e6,
        String(control.measurementId.prefix(8))))

    var rows: [Repetition] = []
    var cells: [JSONValue] = []
    for (index, cell) in allCells().enumerated() {
      let result = try runSubprocess(cell, index: index)
      let row = Self.row(of: result)
      rows.append(
        Repetition(
          index: index, values: row.values, thermalStateAtStart: row.thermalAtStart,
          thermalStateAtEnd: row.thermalAtEnd))
      cells.append(row.json)
      print(
        String(
          format: "  %@: picco transitorio mediano %.2f MB, p95 %.2f MB, limite %.0f MB (%@)",
          cell.description, (row.values["transientPeakMedianBytes"] ?? 0) / 1e6,
          (row.values["transientPeakP95Bytes"] ?? 0) / 1e6,
          (row.values["perItemLimitBytes"] ?? 0) / Self.megabyte,
          String(result.measurementId.prefix(8))))
    }
    return MeasurementResult(
      bench: Self.name, startedAt: startedAt, finishedAt: Date(),
      profile: options.profile.rawValue, datasetManifestDigest: dataset.manifestDigest,
      host: host,
      parameters: [
        "mode": "all", "cells": "\(cells.count)", "n": "\(n)",
        "isolation": "un sottoprocesso per cella",
        "samplerIntervalMs": "\(Self.samplerIntervalMs)",
        "thumbnailScale": "\(options.thumbnailScale)",
        "perItemLimitFormula": Self.formula,
      ],
      repetitions: rows,
      derived: [
        "cells": .array(cells), "perItemLimitFormula": .string(Self.formula),
        "instrumentationFloor": floor.json,
      ])
  }

  /// Riga riassuntiva di una cella, con il `measurementId` del sottoprocesso che la calibra.
  static func row(of result: MeasurementResult) -> (
    values: [String: Double], json: JSONValue, thermalAtStart: ThermalState,
    thermalAtEnd: ThermalState
  ) {
    let transient = result.dispersion["transientPeakDeltaBytes"]
    let retained = result.dispersion["retainedDeltaBytes"]
    let wall = result.dispersion["wallClockMs"]
    let limit = result.derived["perItemLimitBytes"]?.number ?? 0
    let values: [String: Double] = [
      "n": Double(result.repetitions.count),
      "transientPeakMedianBytes": transient?.median ?? 0,
      "transientPeakP95Bytes": transient?.p95 ?? 0,
      "transientPeakMaxBytes": transient?.max ?? 0,
      "transientPeakStddevBytes": transient?.stddev ?? 0,
      "retainedMedianBytes": retained?.median ?? 0,
      "retainedP95Bytes": retained?.p95 ?? 0,
      "retainedMaxBytes": retained?.max ?? 0,
      "wallClockMedianMs": wall?.median ?? 0,
      "perItemLimitBytes": limit,
    ]
    var json: [String: JSONValue] = [
      "cell": .string(result.parameters["cell"] ?? "?"),
      "work": .string(result.parameters["work"] ?? "?"),
      "format": .string(result.parameters["format"] ?? "?"),
      "resolutionClass": .string(result.parameters["resolutionClass"] ?? "?"),
      "pixels": .string(result.parameters["pixels"] ?? "?"),
      "measurementId": .string(result.measurementId),
      "n": .int(result.repetitions.count),
      "distinctItems": .string(result.parameters["distinctItems"] ?? "?"),
      "perItemLimitBytes": .number(limit),
      "perItemLimitFormula": .string(formula),
      "transientPeakDeltaBytes": transient?.json ?? .null,
      "retainedDeltaBytes": retained?.json ?? .null,
      "wallClockMs": wall?.json ?? .null,
      "transientPeakDeltaBytesPerItem": .array(
        result.repetitions.map { .number($0.values["transientPeakDeltaBytes"] ?? 0) }),
      "retainedDeltaBytesPerItem": .array(
        result.repetitions.map { .number($0.values["retainedDeltaBytes"] ?? 0) }),
    ]
    json["outputBytes"] = result.dispersion["outputBytes"]?.json ?? .null
    json["warmupItemAlsoMeasured"] = .string(result.parameters["warmupItemAlsoMeasured"] ?? "?")
    for key in [
      "warmupTransientPeakDeltaBytes", "warmupRetainedDeltaBytes", "didNotSettleCount",
      "operationFailedCount", "peakNotObservedCount",
    ] {
      json[key] = result.derived[key] ?? .null
    }
    let thermal = result.repetitions.map(\.thermalStateAtStart)
    let worstStart = thermal.first { !$0.isNominal } ?? .nominal
    let worstEnd = result.repetitions.map(\.thermalStateAtEnd).first { !$0.isNominal } ?? .nominal
    return (values, .object(json), worstStart, worstEnd)
  }
}
