import Foundation

/// Scrive un `MeasurementResult` in `runs/` e stampa a terminale le cifre grezze.
///
/// Il riepilogo a terminale è ciò che il revisore osserva durante la dimostrazione: riporta il
/// `measurementId` e, per ogni grandezza, `n`, mediana, p95 e deviazione standard. Non è un
/// messaggio di esito.
public struct ResultWriter: Sendable {
  /// `Spikes/01-scale-memory/runs`, risolta dalla posizione di questo sorgente e quindi
  /// indipendente dalla directory corrente.
  public static var defaultRunsDirectory: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Sources/BenchKit
      .deletingLastPathComponent()  // Sources
      .deletingLastPathComponent()  // radice del pacchetto
      .appending(path: "runs", directoryHint: .isDirectory)
  }

  /// Directory in cui vengono scritti i risultati.
  public let runsDirectory: URL

  private let output: @Sendable (String) -> Void

  /// Crea uno scrittore.
  ///
  /// - Parameters:
  ///   - runsDirectory: directory di destinazione, creata se manca.
  ///   - output: destinazione del riepilogo; per difetto lo standard output.
  public init(
    runsDirectory: URL = ResultWriter.defaultRunsDirectory,
    output: @escaping @Sendable (String) -> Void = { print($0) }
  ) {
    self.runsDirectory = runsDirectory
    self.output = output
  }

  /// Scrive `result` in `runs/<bench>-<timestamp>-<prefisso measurementId>.json` e stampa il
  /// riepilogo.
  ///
  /// Rifiuta di scrivere un risultato la cui impronta hardware è incompleta: una cifra senza
  /// attribuzione non può entrare in `RESULT.md`.
  ///
  /// - Returns: il percorso del file scritto.
  /// - Throws: `HostFingerprint.IncompleteError`, oppure un errore di codifica (per esempio un
  ///   valore non finito) o di scrittura.
  @discardableResult
  public func write(_ result: MeasurementResult) throws -> URL {
    try result.host.assertComplete()
    let data = try MeasurementResult.jsonEncoder().encode(result)
    try FileManager.default.createDirectory(at: runsDirectory, withIntermediateDirectories: true)
    let file = fileURL(for: result)
    try data.write(to: file, options: .atomic)
    output(Self.summary(of: result, file: file))
    return file
  }

  /// Percorso del file per `result`: `<bench>-<inizio UTC>-<primi 8 caratteri di
  /// measurementId>.json`, per esempio `first-screen-20261113T094512Z-1b4e28ba.json`.
  public func fileURL(for result: MeasurementResult) -> URL {
    let timestamp = result.startedAt.formatted(
      Date.ISO8601FormatStyle(dateSeparator: .omitted, timeSeparator: .omitted, timeZone: .gmt)
    )
    let name = "\(result.bench)-\(timestamp)-\(result.measurementId.prefix(8)).json"
    return runsDirectory.appending(path: name, directoryHint: .notDirectory)
  }

  /// Riepilogo compatto con le cifre grezze di `result`.
  public static func summary(of result: MeasurementResult, file: URL? = nil) -> String {
    let host = result.host
    let power: String
    switch host.onACPower {
    case true?: power = "rete"
    case false?: power = "batteria"
    case nil: power = "non determinata"
    }
    let constrained = result.repetitions.filter(\.ranUnderThermalPressure).count
    var lines = [
      "measurementId  \(result.measurementId)",
      "bench          \(result.bench), profilo \(result.profile), "
        + "\(result.repetitions.count) ripetizioni",
      "host           \(host.model), \(host.cpuBrand), \(host.physicalMemoryBytes) B, "
        + "macOS \(host.osProductVersion) (\(host.osBuildVersion)), alimentazione \(power), "
        + "termico \(host.thermalState.rawValue)",
      "termico        \(constrained)/\(result.repetitions.count) ripetizioni con stato non "
        + "nominale",
    ]
    if let file {
      lines.append("file           \(file.path(percentEncoded: false))")
    }
    lines.append("")
    let metrics = result.dispersion.keys.sorted()
    guard !metrics.isEmpty else {
      lines.append("(nessuna grandezza con dispersione)")
      return lines.joined(separator: "\n")
    }
    let header = ["grandezza", "n", "mediana", "p95", "stddev"]
    let rows = metrics.compactMap { metric -> [String]? in
      guard let dispersion = result.dispersion[metric] else { return nil }
      return [
        metric,
        String(dispersion.n),
        formatted(dispersion.median),
        formatted(dispersion.p95),
        formatted(dispersion.stddev),
      ]
    }
    let widths = header.indices.map { column in
      ([header] + rows).map { $0[column].count }.max() ?? 0
    }
    for row in [header] + rows {
      let cells = row.enumerated().map { column, cell in
        let padding = String(repeating: " ", count: widths[column] - cell.count)
        return column == 0 ? cell + padding : padding + cell
      }
      lines.append(cells.joined(separator: "  "))
    }
    return lines.joined(separator: "\n")
  }

  /// Cifra grezza con tre decimali e punto decimale, indipendente dalla localizzazione.
  private static func formatted(_ value: Double) -> String {
    String(format: "%.3f", value)
  }
}
