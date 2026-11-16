import Foundation
import Testing

@testable import BenchKit

/// Oracolo eseguibile dei criteri dimostrati da un documento: ogni cifra di `RESULT.md` deve
/// essere rintracciabile in un JSON versionato sotto `measurements/`, l'esito deve avere la forma
/// dichiarata, e l'hardware delle misure citate deve essere quello dichiarato.
@Suite("Tracciabilità di RESULT.md")
struct ResultTraceabilityTests {
  static let resultURL = SpikePaths.packageRoot.appending(path: "RESULT.md")
  static let measurementsURL = SpikePaths.packageRoot.appending(
    path: "measurements", directoryHint: .isDirectory)

  /// Un JSON di `measurements/`: testo, risultato decodificato e albero generico.
  struct Measurement {
    let file: String
    let text: String
    let result: MeasurementResult
    let tree: [String: Any]
  }

  let document: String
  let measurements: [Measurement]

  init() throws {
    document = try String(contentsOf: Self.resultURL, encoding: .utf8)
    measurements = try FileManager.default.contentsOfDirectory(
      at: Self.measurementsURL, includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "json" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    .map { url in
      let data = try Data(contentsOf: url)
      return Measurement(
        file: url.lastPathComponent, text: String(decoding: data, as: UTF8.self),
        result: try MeasurementResult.decode(from: data),
        tree: try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any]))
    }
  }

  // MARK: - Supporto

  /// Il testo di una sezione `## Titolo`, fino alla sezione successiva dello stesso livello.
  func section(_ title: String) throws -> String {
    let lines = document.components(separatedBy: "\n")
    let start = try #require(
      lines.firstIndex { $0.hasPrefix("## ") && $0.contains(title) }, "sezione assente: \(title)")
    let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("## ") } ?? lines.count
    return lines[start..<end].joined(separator: "\n")
  }

  /// Righe di tabella che seguono un'intestazione che comincia con `header`.
  func tableRows(in text: String, header: String) -> [[String]] {
    var rows: [[String]] = []
    var inTable = false
    for line in text.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix(header) {
        inTable = true
        continue
      }
      guard inTable else { continue }
      guard trimmed.hasPrefix("|") else {
        inTable = false
        continue
      }
      if trimmed.hasPrefix("|---") { continue }
      rows.append(
        trimmed.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
          .map { $0.trimmingCharacters(in: .whitespaces) })
    }
    return rows
  }

  /// Un numero scritto con la virgola decimale e la sua tolleranza di arrotondamento.
  func number(_ text: String) -> (value: Double, tolerance: Double)? {
    let cleaned = text.replacingOccurrences(of: ",", with: ".")
    guard let value = Double(cleaned) else { return nil }
    let decimals = cleaned.split(separator: ".").dropFirst().first?.count ?? 0
    return (value, 0.5 * pow(10, -Double(decimals)) + 1e-9)
  }

  func identifier(_ cell: String) -> String {
    cell.trimmingCharacters(in: CharacterSet(charactersIn: "` "))
  }

  func key(_ cell: String) -> String {
    cell.trimmingCharacters(in: CharacterSet(charactersIn: "` "))
  }

  func measurement(withId id: String) -> Measurement? {
    measurements.first { $0.result.measurementId == id }
  }

  /// Un oggetto JSON con `measurementId` uguale a `id` ovunque in un albero (celle unite).
  func object(withId id: String) -> [String: Any]? {
    func search(_ node: Any) -> [String: Any]? {
      if let dictionary = node as? [String: Any] {
        if dictionary["measurementId"] as? String == id { return dictionary }
        for value in dictionary.values {
          if let found = search(value) { return found }
        }
      } else if let array = node as? [Any] {
        for value in array {
          if let found = search(value) { return found }
        }
      }
      return nil
    }
    for measurement in measurements {
      if let found = search(measurement.tree) { return found }
    }
    return nil
  }

  func resolve(_ path: String, in tree: [String: Any]) -> Any? {
    var node: Any? = tree
    for component in path.split(separator: ".") {
      node = (node as? [String: Any])?[String(component)]
    }
    return node
  }

  static let scales: [String: Double] = [
    "ms": 1, "MB": 1e6, "MB/h": 1e6, "kB/1000 el.": 1e3, "%": 0.01, "n.": 1, "min": 1,
  ]

  func expectMatch(
    _ written: String, _ actual: Double, scale: Double, _ context: String
  ) {
    guard let parsed = number(written) else {
      Issue.record("valore non numerico «\(written)» in \(context)")
      return
    }
    let expected = actual / scale
    #expect(
      abs(parsed.value - expected) <= parsed.tolerance,
      "\(context): scritto \(written), JSON \(expected)")
  }

  // MARK: - a. Esistenza dei riferimenti

  @Test("ogni measurementId citato esiste in un file di measurements/")
  func citedIdentifiersExist() throws {
    let pattern = try Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
    let cited = Set(document.matches(of: pattern).map { String(document[$0.range]) })
    #expect(!cited.isEmpty, "RESULT.md non cita alcun measurementId")
    let corpus = measurements.map(\.text).joined(separator: "\n")
    for id in cited.sorted() {
      #expect(corpus.contains(id), "measurementId citato e assente da measurements/: \(id)")
    }
  }

  // MARK: - b. Corrispondenza delle cifre

  @Test("le cifre delle misure grezze combaciano con i JSON")
  func rawMeasurementsMatch() throws {
    let text = try section("Misure grezze")
    let rows = tableRows(in: text, header: "| Misura | Chiave | Unità |")
    #expect(rows.count >= 10, "righe di misure grezze: \(rows.count)")
    let fields = ["median", "p95", "min", "max", "stddev", "iqr"]
    for row in rows {
      guard row.count == 11 else {
        Issue.record("riga malformata: \(row)")
        continue
      }
      let id = identifier(row[10])
      let name = key(row[1])
      let scale = try #require(Self.scales[row[2]], "unità sconosciuta \(row[2])")
      let measurement = try #require(measurement(withId: id), "misura \(id) assente")
      let dispersion: [String: Any]
      if name.hasPrefix("derived.") {
        dispersion = try #require(
          resolve(name, in: measurement.tree) as? [String: Any], "\(name) assente in \(id)")
      } else {
        let value = try #require(measurement.result.dispersion[name], "\(name) assente in \(id)")
        dispersion = [
          "n": Double(value.n), "median": value.median, "p95": value.p95, "min": value.min,
          "max": value.max, "stddev": value.stddev, "iqr": value.iqr,
        ]
      }
      #expect(
        Int(row[3]) == Int((dispersion["n"] as? Double) ?? Double(dispersion["n"] as? Int ?? -1)),
        "n di \(name)")
      for (offset, field) in fields.enumerated() {
        let actual = try #require(dispersion[field] as? Double, "\(field) di \(name)")
        expectMatch(row[4 + offset], actual, scale: scale, "\(row[0]) \(field)")
      }
    }
  }

  @Test("le cifre della sessione lunga combaciano con il JSON")
  func longSessionMatches() throws {
    let text = try section("Misure grezze")
    let rows = tableRows(in: text, header: "| Grandezza | Chiave | Unità | Valore |")
    #expect(!rows.isEmpty, "tabella della sessione lunga assente")
    for row in rows where row.count == 5 {
      let measurement = try #require(measurement(withId: identifier(row[4])))
      let value = resolve(key(row[1]), in: measurement.tree)
      if let flag = value as? Bool, row[3] == "sì" || row[3] == "no" {
        #expect(flag == (row[3] == "sì"), "\(row[0])")
      } else if let number = value as? Double {
        expectMatch(row[3], number, scale: try #require(Self.scales[row[2]]), row[0])
      } else {
        Issue.record("\(row[1]) non risolto in \(row[4])")
      }
    }
  }

  @Test("ogni riga delle stime di costo combacia con la misura che la calibra")
  func costEstimatesMatch() throws {
    let text = try section("Stime di costo in memoria")
    let rows = tableRows(in: text, header: "| Lavoro | Formato | Classe |")
    #expect(rows.count >= 60, "righe di costo: \(rows.count)")
    for row in rows {
      guard row.count == 12 else {
        Issue.record("riga malformata: \(row)")
        continue
      }
      let id = identifier(row[11])
      let cell = try #require(object(withId: id), "cella \(id) assente")
      let transient = try #require(cell["transientPeakDeltaBytes"] as? [String: Any])
      let retained = try #require(cell["retainedDeltaBytes"] as? [String: Any])
      let context = "\(row[0]):\(row[1]):\(row[2])"
      #expect(cell["work"] as? String == row[0], "lavoro di \(context)")
      #expect(Int(row[3]) == cell["n"] as? Int, "n di \(context)")
      let p95 = try #require(transient["p95"] as? Double)
      expectMatch(
        row[4], try #require(transient["median"] as? Double), scale: 1e6, "\(context) mediana")
      expectMatch(row[5], p95, scale: 1e6, "\(context) p95")
      expectMatch(row[6], try #require(transient["max"] as? Double), scale: 1e6, "\(context) max")
      expectMatch(
        row[7], try #require(retained["median"] as? Double), scale: 1e6, "\(context) trattenuto")
      // Stima adottata: p95 arrotondato per eccesso al decimo di MB.
      expectMatch(row[8], (p95 / 1e5).rounded(.up) / 10, scale: 1, "\(context) stima adottata")
      let limit = try #require(cell["perItemLimitBytes"] as? Double)
      expectMatch(row[10], limit, scale: 1_048_576, "\(context) limite per elemento")
      #expect(limit > p95, "il limite per elemento deve superare il p95 in \(context)")
    }
  }

  @Test("le righe della banda di ritenzione combaciano con lo spazzolamento")
  func retentionBandMatches() throws {
    let text = try section("Banda di ritenzione")
    let rows = tableRows(in: text, header: "| Entrata | Uscita |")
    #expect(rows.count >= 15, "righe della banda: \(rows.count)")
    for row in rows where row.count == 9 {
      let measurement = try #require(measurement(withId: identifier(row[8])))
      let derived = measurement.tree["derived"] as? [String: Any] ?? [:]
      var candidates = measurement.result.repetitions.map(\.values)
      for extra in ["noHysteresisReference", "supplementaryRows"] {
        candidates += (derived[extra] as? [[String: Double]]) ?? []
      }
      let enter = try #require(number(row[0])).value
      let exit = try #require(number(row[1])).value
      let match = try #require(
        candidates.first {
          abs(($0["enterBand"] ?? -1) - enter) < 1e-9 && abs(($0["exitBand"] ?? -1) - exit) < 1e-9
        }, "coppia \(row[0])/\(row[1]) assente dallo spazzolamento")
      expectMatch(
        row[2], match["steadyFootprintBytes"] ?? .nan, scale: 1e6, "regime \(row[0])/\(row[1])")
      expectMatch(
        row[3], match["retainedCount"] ?? .nan, scale: 1, "trattenute \(row[0])/\(row[1])")
      expectMatch(row[4], match["regeneratedSmall"] ?? .nan, scale: 1, "±0,25 \(row[0])/\(row[1])")
      expectMatch(row[5], match["regeneratedMedium"] ?? .nan, scale: 1, "±1 \(row[0])/\(row[1])")
    }
  }

  // MARK: - c. Completezza dell'esito (AC-6)

  /// Le quattro voci di esito, ciascuna col proprio testo.
  func verdicts() throws -> [String: String] {
    let text = try section("Esito")
    var entries: [String: String] = [:]
    var current: String?
    for line in text.components(separatedBy: "\n") {
      if line.hasPrefix("### ") {
        current = ["ADR-009", "NFR-P10", "NFR-P1", "NFR-P9"].first { line.contains($0) }
        if let current { entries[current] = "" }
      } else if let current {
        entries[current, default: ""] += line + "\n"
      }
    }
    return entries
  }

  @Test("quattro voci di esito, ciascuna con uno e un solo marcatore")
  func verdictsAreComplete() throws {
    let entries = try verdicts()
    #expect(Set(entries.keys) == ["ADR-009", "NFR-P1", "NFR-P9", "NFR-P10"])
    for (name, body) in entries {
      let confirmed = body.components(separatedBy: "**confermato**").count - 1
      let amended = body.components(separatedBy: "**emendato**").count - 1
      #expect(
        confirmed + amended == 1, "\(name): marcatori \(confirmed) confermato, \(amended) emendato")
      if amended == 1 {
        let replacement = try #require(
          body.components(separatedBy: "**Testo di sostituzione:**").dropFirst().first,
          "\(name) è emendato senza testo di sostituzione")
        #expect(
          replacement.trimmingCharacters(in: .whitespacesAndNewlines).count > 40,
          "\(name): testo di sostituzione vuoto")
        #expect(replacement.contains { $0.isNumber }, "\(name): nessun valore numerico misurato")
      }
      let pattern = try Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
      #expect(body.contains(pattern), "\(name): nessun measurementId della misura che decide")
    }
  }

  // MARK: - d. Coerenza dell'hardware (AC-2, AC-7)

  @Test("ogni misura citata è stata eseguita sull'hardware dichiarato")
  func hardwareIsCoherent() throws {
    let text = try section("Hardware di misura")
    let rows = tableRows(in: text, header: "| Campo | Valore |")
    let table = Dictionary(rows.map { ($0[0], $0[1]) }, uniquingKeysWith: { first, _ in first })
    let model = try #require(table["Modello"])
    let memory = try #require(
      table["Memoria fisica"]?.split(separator: " ").first.flatMap { UInt64($0) })
    let os = try #require(table["macOS"])
    #expect(!measurements.isEmpty)
    for measurement in measurements {
      let host = measurement.result.host
      #expect(host.model == model, "\(measurement.file): modello \(host.model)")
      #expect(host.physicalMemoryBytes == memory, "\(measurement.file): memoria")
      #expect(os.contains("build \(host.osBuildVersion)"), "\(measurement.file): build di macOS")
      try host.assertComplete()
    }
  }

  // MARK: - e. Simmetria delle soglie non supportabili (AC-7)

  @Test("ogni soglia mancata compare fra le non supportabili, e viceversa")
  func unsupportedThresholdsAreSymmetric() throws {
    let entries = try verdicts()
    let missed = Set(
      entries.filter { $0.value.contains("Soglia raggiunta: no") }.map(\.key))
    let reached = Set(
      entries.filter { $0.value.contains("Soglia raggiunta: sì") }.map(\.key))
    #expect(
      missed.union(reached) == Set(entries.keys), "ogni voce dichiara se la soglia è raggiunta")
    let unsupported = try section("Soglie non supportabili")
    let listed = Set(
      unsupported.components(separatedBy: "\n").filter { $0.hasPrefix("### ") }.compactMap { line in
        ["ADR-009", "NFR-P10", "NFR-P1", "NFR-P9"].first { line.contains($0) }
      })
    #expect(listed == missed, "mancate: \(missed.sorted()), elencate: \(listed.sorted())")
    #expect(unsupported.contains("nessuna misura è stata ripetuta su una configurazione diversa"))
  }
}
