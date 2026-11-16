import Darwin
import Foundation
import Testing

@testable import CrashKit

/// Oracolo eseguibile del documento del cancello: ogni riga di `RESULT.md` deve trovare la sua
/// cella nel JSON versionato sotto `measurements/`, e ogni cella rilevante del JSON deve avere la
/// sua riga.
///
/// Ogni controllo è una funzione pura del testo del documento che restituisce i rilievi trovati: i
/// test la applicano a `RESULT.md`, il test di controllo la applica a copie alterate in memoria, per
/// dimostrare che il confronto può fallire. Le attese vengono dal JSON decodificato con
/// `MeasurementResult` e dall'enumerazione dei punti, mai dal documento stesso. Nessun conteggio ha
/// tolleranza; un rilievo si corregge in `RESULT.md`, mai nel JSON.
@Suite("Tracciabilità di RESULT.md sulla misura versionata")
struct ResultTraceabilityTests {
  static let resultURL = CrashPaths.packageRoot.appending(
    path: "RESULT.md", directoryHint: .notDirectory)

  // Titoli delle sezioni di `RESULT.md` e inizio dell'intestazione delle loro tabelle.
  static let configurationSection = "Configurazione"
  static let pointsSection = "Punti di interruzione"
  static let pointsHeader = "| Punto | Fase |"
  static let compensationSection = "Compensazione"
  static let compensationHeader = "| Cella | Esito | Coincide"
  static let classesSection = "Classi di errore"
  static let classesHeader = "| Classe | Ambito adottato |"
  static let blockedSection = "Punti bloccati in attesa dell'utente"
  static let blockedHeader = "| Cella | Classe | Ambito |"
  static let separationSection = "Separazione di immagine e sidecar"
  static let separationHeader = "| Cella | Coppie separate"
  static let unsupportedSection = "Esiti non supportabili"
  static let unsupportedHeader = "| Cella | Motivo | Traccia |"
  static let verdictSection = "Esito su ADR-007"

  /// I punti dell'elenco enumerato con la fixture versionata.
  static let expectedPointCount = 61
  /// Cella di tabella per una strategia che non ha la cella nel JSON (U+2014).
  static let absent = "—"
  /// Prefisso dei rilievi della simmetria fra non supportabili e bloccati (AC-7).
  static let symmetryTag = "simmetria AC-7"

  /// Nomi degli errno che il documento può citare fra parentesi dopo il numero.
  static let errnoNames: [Int32: String] = [
    EPERM: "EPERM", ENOENT: "ENOENT", EACCES: "EACCES", EEXIST: "EEXIST", ENOSPC: "ENOSPC",
    EDQUOT: "EDQUOT", EROFS: "EROFS",
  ]

  let document: String
  let measurementFile: URL
  let result: MeasurementResult
  /// I punti ricostruiti con `CrashPoints.enumerate` sul piano di riferimento della fixture.
  let enumeratedPoints: [CrashPoint]
  /// Le celle del JSON per ID.
  let cellsById: [String: MeasurementCell]

  init() throws {
    document = try String(contentsOf: Self.resultURL, encoding: .utf8)
    let files = try FileManager.default.contentsOfDirectory(
      at: CrashPaths.measurements, includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "json" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    try #require(
      files.count == 1,
      "measurements/ deve contenere un solo JSON: \(files.map(\.lastPathComponent))")
    measurementFile = files[0]
    result = try MeasurementResult.load(from: measurementFile)
    let definition = try BatchDefinition.load(
      from: CrashPaths.fixtures.appending(
        path: Fixtures.batchFileName, directoryHint: .notDirectory))
    enumeratedPoints = CrashPoints.enumerate(try CrashPoints.referencePlan(definition: definition))
    cellsById = Dictionary(
      result.cells.map { ($0.cellId, $0) }, uniquingKeysWith: { first, _ in first })
  }

  // MARK: - Lettura del documento

  /// Il testo della sezione `## <title>`, fino alla sezione successiva dello stesso livello; `nil`
  /// se manca. Copiato da Spike 01 e adattato: titolo esatto, e nessun `#require`, perché il test
  /// di controllo applica i controlli anche a copie alterate.
  static func section(_ title: String, in document: String) -> String? {
    let lines = document.components(separatedBy: "\n")
    guard let start = lines.firstIndex(where: { $0 == "## \(title)" }) else { return nil }
    let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("## ") } ?? lines.count
    return lines[start..<end].joined(separator: "\n")
  }

  /// Le righe della tabella che segue l'intestazione che comincia con `header`, come celle senza
  /// spazi ai bordi; `nil` se l'intestazione manca. La tabella finisce alla prima riga che non
  /// comincia con `|`. Copiato da Spike 01 e adattato.
  static func tableRows(in text: String, header: String) -> [[String]]? {
    var rows: [[String]] = []
    var found = false
    var inTable = false
    for line in text.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix(header) {
        found = true
        inTable = true
        continue
      }
      guard inTable else { continue }
      guard trimmed.hasPrefix("|") else {
        inTable = false
        continue
      }
      if trimmed.hasPrefix("|---") { continue }
      rows.append(cells(of: trimmed))
    }
    return found ? rows : nil
  }

  /// Le celle di una riga di tabella.
  static func cells(of line: String) -> [String] {
    line.trimmingCharacters(in: .whitespaces)
      .split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
      .map { $0.trimmingCharacters(in: .whitespaces) }
  }

  /// La riga di tabella con le celle date.
  static func line(of cells: [String]) -> String {
    "| " + cells.joined(separator: " | ") + " |"
  }

  /// Le righe ben formate della tabella di una sezione. Una sezione o una tabella assente, o una
  /// riga con un numero di colonne diverso da `columns`, è un rilievo; le righe malformate sono
  /// escluse dai confronti successivi.
  static func table(
    _ title: String, header: String, columns: Int, in document: String,
    findings: inout [String]
  ) -> [[String]] {
    guard let text = section(title, in: document) else {
      findings.append("§ \(title): sezione assente")
      return []
    }
    guard let rows = tableRows(in: text, header: header) else {
      findings.append("§ \(title): tabella «\(header)» assente")
      return []
    }
    var wellFormed: [[String]] = []
    for row in rows {
      if row.count == columns {
        wellFormed.append(row)
      } else {
        findings.append(
          "§ \(title): riga «\(row.first ?? "")» con \(row.count) colonne invece di \(columns)")
      }
    }
    return wellFormed
  }

  /// Il testo di una sottosezione `### <title>` di `text`, fino al titolo successivo di qualunque
  /// livello; `nil` se manca.
  static func subsection(_ title: String, in text: String) -> String? {
    let lines = text.components(separatedBy: "\n")
    guard let start = lines.firstIndex(where: { $0 == "### \(title)" }) else { return nil }
    let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("#") } ?? lines.count
    return lines[(start + 1)..<end].joined(separator: "\n")
  }

  /// Vero se `text` cita `id` come identificativo intero: non preceduto né seguito da una lettera,
  /// una cifra, `-`, `_` o `/`. Così `S06-b/resume` non si trova dentro
  /// `S06-b/resume/G-folder-readonly`.
  static func mentions(_ text: String, _ id: String) -> Bool {
    func isIdentifierCharacter(_ character: Character?) -> Bool {
      guard let character else { return false }
      return character.isLetter || character.isNumber || "-_/".contains(character)
    }
    var searchStart = text.startIndex
    while let range = text.range(of: id, range: searchStart..<text.endIndex) {
      let before =
        range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
      let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
      if !isIdentifierCharacter(before), !isIdentifierCharacter(after) { return true }
      searchStart = text.index(after: range.lowerBound)
    }
    return false
  }

  /// Un elenco `<voce> (<n>/<totale>)` separato da `; `, letto come conteggi per voce e totali
  /// dichiarati; `nil` se un elemento non ha questa forma o se una voce compare due volte.
  static func countedList(_ text: String) -> (counts: [String: Int], totals: [Int])? {
    var counts: [String: Int] = [:]
    var totals: [Int] = []
    for item in text.components(separatedBy: "; ") {
      guard let match = item.wholeMatch(of: /(.+) \((\d+)\/(\d+)\)/),
        let count = Int(match.2), let total = Int(match.3), counts[String(match.1)] == nil
      else { return nil }
      counts[String(match.1)] = count
      totals.append(total)
    }
    return (counts, totals)
  }

  /// Un elenco separato da `separator`, oppure `empty` per l'elenco vuoto.
  static func list(_ text: String, separator: String = ", ", empty: String) -> [String] {
    text == empty ? [] : text.components(separatedBy: separator)
  }

  /// Un elenco `OPn i:<pos> s:<pos> …`, letto come `OPn` → `i:<pos> s:<pos>`; `nil` se un elemento
  /// non ha questa forma o se un'operazione compare due volte.
  static func pairList(_ text: String) -> [String: String]? {
    let tokens = text.split(separator: " ").map(String.init)
    guard !tokens.isEmpty, tokens.count.isMultiple(of: 3) else { return nil }
    var pairs: [String: String] = [:]
    for index in stride(from: 0, to: tokens.count, by: 3) {
      let (operation, image, sidecar) = (tokens[index], tokens[index + 1], tokens[index + 2])
      guard operation.hasPrefix("OP"), image.hasPrefix("i:"), sidecar.hasPrefix("s:"),
        pairs[operation] == nil
      else { return nil }
      pairs[operation] = "\(image) \(sidecar)"
    }
    return pairs
  }

  /// `percorso:campo` di uno scostamento.
  static func key(_ deviation: Deviation) -> String {
    "\(deviation.path):\(deviation.field.rawValue)"
  }

  static func render(_ values: [String: Int]) -> String {
    values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
  }

  static func render(_ values: [String: String]) -> String {
    values.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: " ")
  }

  static func render(_ values: [String: Set<String>]) -> String {
    values.sorted { $0.key < $1.key }
      .map { "\($0.key) da \($0.value.sorted().joined(separator: ", "))" }
      .joined(separator: "; ")
  }

  // MARK: - Confronti

  /// Corrispondenza biunivoca fra la prima colonna di una tabella e gli ID attesi: di cella, di
  /// punto o di classe, secondo `item` («della cella», «del punto», «della classe»).
  static func bijection(
    _ rowIds: [String], _ expectedIds: [String], item: String = "della cella", context: String
  ) -> [String] {
    var findings: [String] = []
    for id in expectedIds where !rowIds.contains(id) {
      findings.append("\(context): manca la riga \(item) \(id)")
    }
    for id in rowIds where !expectedIds.contains(id) {
      findings.append("\(context): riga senza corrispondenza nel JSON: \(id)")
    }
    let repeated = Dictionary(grouping: rowIds, by: { $0 }).filter { $0.value.count > 1 }.keys
    for id in repeated.sorted() {
      findings.append("\(context): riga ripetuta: \(id)")
    }
    return findings
  }

  /// Rilievi se `written` non dichiara esattamente i conteggi `expected` su `total` ripetizioni.
  static func compareCounts(
    _ written: String, expected: [String: Int], total: Int, context: String
  ) -> [String] {
    let expected = expected.filter { $0.value > 0 }
    guard let parsed = countedList(written) else {
      return ["\(context): «\(written)» non ha la forma `<voce> (<n>/<totale>)`"]
    }
    var findings: [String] = []
    if parsed.counts != expected {
      findings.append(
        "\(context): scritto \(render(parsed.counts)), JSON \(render(expected))")
    }
    for written in parsed.totals where written != total {
      findings.append("\(context): totale scritto \(written), JSON \(total)")
    }
    return findings
  }

  /// Rilievi se l'elenco `written` non contiene esattamente gli elementi `expected`, ripetizioni
  /// comprese, in qualunque ordine.
  static func compareElements(_ written: [String], _ expected: [String], context: String)
    -> [String]
  {
    var findings: [String] = []
    let missing = expected.filter { !written.contains($0) }
    let extra = written.filter { !expected.contains($0) }
    if !missing.isEmpty {
      findings.append("\(context): mancano \(missing.joined(separator: ", "))")
    }
    if !extra.isEmpty {
      findings.append("\(context): non nel JSON \(extra.joined(separator: ", "))")
    }
    if missing.isEmpty, extra.isEmpty, written.sorted() != expected.sorted() {
      findings.append("\(context): ripetizioni diverse, scritto \(written), JSON \(expected)")
    }
    return findings
  }

  /// La cella di base `<punto>/<strategia>` del JSON, se esiste.
  func baseCell(_ point: String, _ strategy: RecoveryStrategy) -> MeasurementCell? {
    result.cells.first { $0.point == point && $0.strategy == strategy && $0.perturbation == nil }
  }

  /// Colonna di esito di § *Punti di interruzione*: i conteggi della cella, oppure `—`.
  static func outcomeColumn(_ written: String, cell: MeasurementCell?, context: String)
    -> [String]
  {
    guard let cell else {
      return written == absent ? [] : ["\(context): «\(written)» per una cella assente dal JSON"]
    }
    return compareCounts(
      written, expected: cell.outcomes, total: cell.repetitions,
      context: "\(context) (\(cell.cellId))")
  }

  /// Colonna di stato di § *Punti di interruzione*: le posizioni di `pairs`, oppure `—`.
  static func pairsColumn(_ written: String, cell: MeasurementCell?, context: String) -> [String] {
    guard let cell else {
      return written == absent ? [] : ["\(context): «\(written)» per una cella assente dal JSON"]
    }
    let expected = cell.pairs.mapValues { "i:\($0.image.rawValue) s:\($0.sidecar.rawValue)" }
    guard let parsed = pairList(written) else {
      return ["\(context): «\(written)» non ha la forma `OPn i:<pos> s:<pos>`"]
    }
    return parsed == expected
      ? [] : ["\(context) (\(cell.cellId)): scritto \(render(parsed)), JSON \(render(expected))"]
  }

  /// Colonna «Errore osservato» di § *Classi di errore*: per ogni errno o errore Cocoa dei
  /// fallimenti registrati nelle celle provate, le chiamate che lo hanno prodotto.
  static func observedErrorFindings(
    _ written: String, cells: [MeasurementCell], context: String
  ) -> [String] {
    var expected: [String: Set<String>] = [:]
    for failure in cells.flatMap(\.failures) {
      let cause =
        failure.errno.map { "errno \($0)" } ?? failure.cocoa.map { "Cocoa \($0)" }
        ?? "nessun codice"
      expected[cause, default: []].insert(failure.syscall)
    }
    if written.hasPrefix("non applicabile") {
      return expected.isEmpty
        ? [] : ["\(context): «non applicabile», ma il JSON registra \(render(expected))"]
    }
    var findings: [String] = []
    var parsed: [String: Set<String>] = [:]
    for clause in written.components(separatedBy: "; ") {
      guard let separator = clause.range(of: " da ", options: .backwards) else {
        return ["\(context): «\(clause)» non ha la forma `<errore> da <chiamate>`"]
      }
      var cause = String(clause[..<separator.lowerBound])
      let calls = clause[separator.upperBound...].components(separatedBy: ", ")
      if let match = cause.wholeMatch(of: /errno (\d+) \((\w+)\)/) {
        if let code = Int32(match.1), let name = errnoNames[code], name != String(match.2) {
          findings.append("\(context): errno \(code) è \(name), non \(match.2)")
        }
        cause = "errno \(match.1)"
      }
      guard parsed[cause] == nil, Set(calls).count == calls.count else {
        return ["\(context): «\(written)» ripete un errore o una chiamata"]
      }
      parsed[cause] = Set(calls)
    }
    if parsed != expected {
      findings.append("\(context): scritto \(render(parsed)), JSON \(render(expected))")
    }
    return findings
  }

  /// Colonna «Classificazione confermata» di § *Classi di errore*: `sì` se nessuna cella provata
  /// adotta un'altra classe; altrimenti `no — …`, con ogni cella che la adotta e la classe adottata.
  /// Una cella senza classe adottata non ha incontrato l'errore, e non smentisce la classe.
  static func confirmationFindings(
    _ written: String, errorClass: ErrorClass, cells: [MeasurementCell], context: String
  ) -> [String] {
    let others = cells.filter { $0.errorClass != nil && $0.errorClass != errorClass }
    if others.isEmpty {
      return written == "sì"
        ? [] : ["\(context): «\(written)», ma nessuna cella provata adotta un'altra classe"]
    }
    guard written.hasPrefix("no — ") else {
      return [
        "\(context): «\(written)», ma adotta un'altra classe: "
          + others.map(\.cellId).joined(separator: ", ")
      ]
    }
    var findings: [String] = []
    for cell in others {
      let adopted = cell.errorClass?.rawValue ?? ""
      if !mentions(written, cell.cellId) || !mentions(written, adopted) {
        findings.append("\(context): non nomina \(cell.cellId) con la classe adottata \(adopted)")
      }
    }
    return findings
  }

  // MARK: - Controlli, uno per passo del contratto

  /// Passo 2: identità della misura e § *Configurazione*.
  func configurationFindings(_ document: String) -> [String] {
    var findings: [String] = []
    let fileName = measurementFile.deletingPathExtension().lastPathComponent
    if result.measurementId != fileName {
      findings.append("measurementId \(result.measurementId) diverso dal file \(fileName).json")
    }
    if cellsById.count != result.cells.count {
      findings.append("il JSON ha ID di cella ripetuti")
    }
    for cell in result.cells where !cell.pointReached {
      findings.append("cella \(cell.cellId): pointReached == false")
    }
    let title = Self.configurationSection
    guard let text = Self.section(title, in: document) else {
      return findings + ["§ \(title): sezione assente"]
    }
    let cited = [
      ("measurementId", result.measurementId), ("modello dell'host", result.host.model),
      ("build di macOS", result.host.osBuild),
      ("digest del manifest", result.fixtureManifestSha256),
    ]
    for (name, value) in cited {
      if value.isEmpty {
        findings.append("JSON: \(name) vuoto")
      } else if !text.contains(value) {
        findings.append("§ \(title): non cita \(name) \(value)")
      }
    }
    let rows = (Self.tableRows(in: text, header: "| Campo | Valore |") ?? []).filter {
      $0.count == 2
    }
    let values = Dictionary(rows.map { ($0[0], $0[1]) }, uniquingKeysWith: { first, _ in first })
    for (label, value) in [
      ("Host: modello", result.host.model), ("Host: build di macOS", result.host.osBuild),
    ]
    where values[label] != value {
      findings.append("§ \(title): «\(label)» è «\(values[label] ?? "assente")», JSON \(value)")
    }
    return findings
  }

  /// Passo 3: § *Punti di interruzione* (AC-2).
  func pointFindings(_ document: String) -> [String] {
    var findings: [String] = []
    let title = Self.pointsSection
    let rows = Self.table(
      title, header: Self.pointsHeader, columns: 7, in: document, findings: &findings)
    let rowIds = rows.map { $0[0] }
    let enumeratedIds = enumeratedPoints.map(\.id)
    if enumeratedIds.count != Self.expectedPointCount {
      findings.append("enumerazione di \(enumeratedIds.count) punti invece di 61")
    }
    if result.points.map(\.id) != enumeratedIds {
      findings.append("points del JSON diversi dall'enumerazione ricostruita sulla fixture")
    }
    let idFindings = Self.bijection(
      rowIds, enumeratedIds, item: "del punto", context: "§ \(title)")
    findings += idFindings
    if idFindings.isEmpty, rowIds != enumeratedIds {
      findings.append("§ \(title): righe in un ordine diverso dall'enumerazione")
    }

    let phases = Dictionary(
      result.points.map { ($0.id, $0.phase.rawValue) }, uniquingKeysWith: { first, _ in first })
    for row in rows {
      let point = row[0]
      let context = "§ \(title), punto \(point)"
      if let phase = phases[point], row[1] != phase {
        findings.append("\(context): fase \(row[1]), JSON \(phase)")
      }
      let resume = baseCell(point, .resume)
      let compensate = baseCell(point, .compensate)
      if resume == nil, compensate == nil {
        findings.append("\(context): nessuna cella di base nel JSON")
      }
      findings += Self.outcomeColumn(row[2], cell: resume, context: "\(context), esito ripresa")
      findings += Self.outcomeColumn(
        row[3], cell: compensate, context: "\(context), esito compensazione")
      for cell in [resume, compensate].compactMap({ $0 }) where row[4] != "\(cell.repetitions)" {
        findings.append(
          "\(context): ripetizioni \(row[4]), JSON \(cell.repetitions) (\(cell.cellId))")
      }
      findings += Self.pairsColumn(row[5], cell: resume, context: "\(context), stato dopo ripresa")
      findings += Self.pairsColumn(
        row[6], cell: compensate, context: "\(context), stato dopo compensazione")
    }

    // Direzione inversa: ogni cella di base del JSON ha la sua colonna in una riga.
    var written: Set<String> = []
    for row in rows {
      if row[2] != Self.absent { written.insert("\(row[0])/\(RecoveryStrategy.resume.rawValue)") }
      if row[3] != Self.absent {
        written.insert("\(row[0])/\(RecoveryStrategy.compensate.rawValue)")
      }
    }
    for cell in result.cells where cell.perturbation == nil {
      if !written.contains("\(cell.point)/\(cell.strategy.rawValue)") {
        findings.append("§ \(title): la cella \(cell.cellId) non ha la sua colonna")
      }
    }
    return findings
  }

  /// Passo 4: § *Compensazione* (AC-3).
  func compensationFindings(_ document: String) -> [String] {
    var findings: [String] = []
    let title = Self.compensationSection
    let rows = Self.table(
      title, header: Self.compensationHeader, columns: 5, in: document, findings: &findings)
    let attempted = result.cells.filter(\.compensation.attempted).map(\.cellId)
    findings += Self.bijection(rows.map { $0[0] }, attempted, context: "§ \(title)")
    for row in rows {
      guard let cell = cellsById[row[0]], cell.compensation.attempted else { continue }
      let context = "§ \(title), \(cell.cellId)"
      let oracle = cell.compensation
      findings += Self.compareCounts(
        row[1], expected: cell.outcomes, total: cell.repetitions, context: "\(context), esito")
      if let matchesPre = oracle.matchesPre {
        if row[2] != (matchesPre ? "sì" : "no") {
          findings.append("\(context): «Coincide» \(row[2]), JSON matchesPre \(matchesPre)")
        }
      } else {
        findings.append("\(context): matchesPre assente dal JSON")
      }
      findings += Self.compareElements(
        Self.list(row[3], empty: "nessuno"), oracle.fileDeviations.map(Self.key),
        context: "\(context), scostamenti su file")
      findings += Self.compareElements(
        Self.list(row[4], empty: "nessuno"), oracle.directoryMtimeDeviations.map(Self.key),
        context: "\(context), scostamenti mtime di directory")
    }
    return findings
  }

  /// Passo 5: § *Classi di errore* (AC-4).
  func classFindings(_ document: String) -> [String] {
    var findings: [String] = []
    let title = Self.classesSection
    let rows = Self.table(
      title, header: Self.classesHeader, columns: 6, in: document, findings: &findings)
    let names = ErrorClass.allCases.map(\.rawValue)
    if rows.count != names.count {
      findings.append("§ \(title): \(rows.count) righe invece di \(names.count)")
    }
    findings += Self.bijection(
      rows.map { $0[0] }, names, item: "della classe", context: "§ \(title)")
    for row in rows {
      guard let errorClass = ErrorClass(rawValue: row[0]) else { continue }
      let context = "§ \(title), \(errorClass.rawValue)"
      if row[1] != errorClass.scope.rawValue {
        findings.append("\(context): ambito \(row[1]), ErrorClass.scope \(errorClass.scope)")
      }
      let tried = result.cells.filter { $0.perturbation == errorClass && $0.applicable }
      findings += Self.compareElements(
        Self.list(row[3], empty: "nessuna"), tried.map(\.cellId),
        context: "\(context), celle provate")
      var outcomes: [String: Int] = [:]
      for (kind, count) in tried.flatMap(\.outcomes) { outcomes[kind, default: 0] += count }
      findings += Self.compareCounts(
        row[4], expected: outcomes, total: tried.map(\.repetitions).reduce(0, +),
        context: "\(context), esiti")
      findings += Self.observedErrorFindings(
        row[2], cells: tried, context: "\(context), errore osservato")
      findings += Self.confirmationFindings(
        row[5], errorClass: errorClass, cells: tried, context: "\(context), confermata")
    }
    return findings
  }

  /// Passo 6: § *Punti bloccati in attesa dell'utente* (AC-4).
  func blockedFindings(_ document: String) -> [String] {
    var findings: [String] = []
    let title = Self.blockedSection
    let rows = Self.table(
      title, header: Self.blockedHeader, columns: 6, in: document, findings: &findings)
    let blocked = result.cells.filter { ($0.outcomes[OutcomeKind.bloccato.rawValue] ?? 0) > 0 }
    let blockedIds = blocked.map(\.cellId)
    findings += Self.bijection(rows.map { $0[0] }, blockedIds, context: "§ \(title)")
    let scopes = ErrorScope.allCases.map(\.rawValue)
    for row in rows {
      guard let cell = cellsById[row[0]], blockedIds.contains(cell.cellId) else { continue }
      let context = "§ \(title), \(cell.cellId)"
      if row[1] != cell.errorClass?.rawValue {
        findings.append(
          "\(context): classe \(row[1]), JSON \(cell.errorClass?.rawValue ?? "assente")")
      }
      if !scopes.contains(row[2]) {
        findings.append("\(context): ambito «\(row[2])» né locale né sistemico")
      } else if row[2] != cell.errorScope?.rawValue {
        findings.append(
          "\(context): ambito \(row[2]), JSON \(cell.errorScope?.rawValue ?? "assente")")
      }
      if row[3].isEmpty {
        findings.append("\(context): ragione vuota")
      } else if let failure = cell.failures.first {
        // La ragione nomina il fallimento che ha sospeso il lotto: chiamata e passo.
        if !Self.mentions(row[3], failure.syscall) {
          findings.append("\(context): la ragione non nomina \(failure.syscall)")
        }
        if failure.stepId != Steps.prepareStepId, !Self.mentions(row[3], failure.stepId) {
          findings.append("\(context): la ragione non nomina il passo \(failure.stepId)")
        }
      }
      guard let retry = cell.followUp?.retry, let abandon = cell.followUp?.abandon else {
        findings.append("\(context): followUp senza i rami retry e abandon nel JSON")
        continue
      }
      findings += Self.compareCounts(
        row[4], expected: retry.outcomes, total: retry.repetitions,
        context: "\(context), esito dopo retry")
      findings += Self.compareCounts(
        row[5], expected: abandon.outcomes, total: abandon.repetitions,
        context: "\(context), esito dopo abandon")
    }
    return findings
  }

  /// Passo 7: § *Separazione di immagine e sidecar* (AC-5).
  func separationFindings(_ document: String) -> [String] {
    var findings: [String] = []
    let title = Self.separationSection
    let rows = Self.table(
      title, header: Self.separationHeader, columns: 5, in: document, findings: &findings)
    let separated = result.cells.filter { !$0.separationsAtCrash.isEmpty }.map(\.cellId)
    findings += Self.bijection(rows.map { $0[0] }, separated, context: "§ \(title)")
    for row in rows {
      guard let cell = cellsById[row[0]], !cell.separationsAtCrash.isEmpty else { continue }
      let context = "§ \(title), \(cell.cellId)"
      findings += Self.compareElements(
        Self.list(row[1], empty: "nessuna"), cell.separationsAtCrash,
        context: "\(context), coppie separate all'arresto")
      let detected = cell.separationDetected?.rawValue ?? "assente"
      if row[2] != detected {
        findings.append("\(context): «Rilevata dal recupero» \(row[2]), JSON \(detected)")
      }
      // «Cosa riferisce»: la riga `SEPARAZIONI-ALL-AVVIO` del recupero, poi la posizione finale
      // di ogni coppia separata o riferita, dall'istantanea dopo il recupero.
      let reported =
        cell.separationsReported.isEmpty
        ? "nessuna" : cell.separationsReported.joined(separator: ",")
      let firstClause = row[3].components(separatedBy: "; ").first ?? ""
      if firstClause != "SEPARAZIONI-ALL-AVVIO \(reported)" {
        findings.append(
          "\(context): riferisce «\(firstClause)», JSON SEPARAZIONI-ALL-AVVIO \(reported)")
      }
      let writtenPairs = row[3].matches(of: /COPPIA OP\d+ i:\w+ s:\w+/).map { String($0.output) }
      var expectedPairs: [String] = []
      for operation in Set(cell.separationsAtCrash + cell.separationsReported).sorted() {
        guard let pair = cell.pairs[operation] else {
          findings.append("\(context): il JSON non ha la posizione di \(operation)")
          continue
        }
        expectedPairs.append(
          "COPPIA \(operation) i:\(pair.image.rawValue) s:\(pair.sidecar.rawValue)")
      }
      findings += Self.compareElements(
        writtenPairs, expectedPairs, context: "\(context), posizioni riferite")
      findings += Self.compareElements(
        Self.list(row[4], empty: "nessuna"), cell.separationsResidual,
        context: "\(context), separazioni residue")
    }
    // Una separazione sfuggita al recupero, o riferita senza esserci, è nominata nella sezione.
    let text = Self.section(title, in: document) ?? ""
    for cell in result.cells {
      guard let detection = cell.separationDetected,
        detection == .nonRilevata || detection == .falsaSegnalazione
      else { continue }
      if !Self.mentions(text, cell.cellId) {
        findings.append("§ \(title): la cella \(detection.rawValue) \(cell.cellId) non è nominata")
      }
    }
    return findings
  }

  /// Passo 8: § *Esiti non supportabili* e simmetria con § *Punti bloccati* (AC-7).
  func unsupportedFindings(_ document: String) -> [String] {
    var findings: [String] = []
    let title = Self.unsupportedSection
    let rows = Self.table(
      title, header: Self.unsupportedHeader, columns: 3, in: document, findings: &findings)
    let nonSupportable = OutcomeKind.nonSupportabile.rawValue
    let unsupported = result.cells.filter {
      ($0.outcomes[nonSupportable] ?? 0) > 0 || $0.recognitionError
    }
    let unsupportedIds = unsupported.map(\.cellId)
    findings += Self.bijection(rows.map { $0[0] }, unsupportedIds, context: "§ \(title)")
    for row in rows {
      guard let cell = cellsById[row[0]], unsupportedIds.contains(cell.cellId) else { continue }
      let context = "§ \(title), \(cell.cellId)"
      if cell.reasons.isEmpty {
        if !row[1].contains("RICONOSCIMENTO_ERRATO") {
          findings.append("\(context): motivo «\(row[1])» senza RICONOSCIMENTO_ERRATO")
        }
      } else {
        findings += Self.compareCounts(
          row[1], expected: cell.reasons, total: cell.repetitions, context: "\(context), motivo")
      }
      let trace = cell.trace.joined(separator: " / ")
      if trace.isEmpty {
        findings.append("\(context): il JSON non ha la traccia che dimostra l'esito")
      } else if row[2] != trace {
        findings.append("\(context): traccia «\(row[2])», JSON «\(trace)»")
      }
    }

    // Simmetria: nessuna cella non supportabile è fra i punti bloccati. L'unica eccezione è una
    // cella che ha anche ripetizioni `bloccato`: con esiti diversi fra le ripetizioni la cella è
    // necessariamente `nonDeterministic`, e lo deve dichiarare. Una cella con il solo
    // `RICONOSCIMENTO_ERRATO` e 5 ripetizioni `bloccato` è legittimamente in entrambe le tabelle.
    let blockedText = Self.section(Self.blockedSection, in: document) ?? ""
    for cell in unsupported {
      let blockedRepetitions = cell.outcomes[OutcomeKind.bloccato.rawValue] ?? 0
      let nonSupportableRepetitions = cell.outcomes[nonSupportable] ?? 0
      if blockedRepetitions > 0 {
        if nonSupportableRepetitions > 0, !cell.nonDeterministic {
          findings.append(
            "\(Self.symmetryTag): \(cell.cellId) ha ripetizioni NON_SUPPORTABILE e bloccato, "
              + "ma non è nonDeterministic")
        }
      } else if Self.mentions(blockedText, cell.cellId) {
        findings.append(
          "\(Self.symmetryTag): la cella non supportabile \(cell.cellId) compare in "
            + "§ \(Self.blockedSection)")
      }
    }
    return findings
  }

  /// Passo 9: § *Esito su ADR-007* (AC-6).
  func verdictFindings(_ document: String) -> [String] {
    let title = Self.verdictSection
    guard let text = Self.section(title, in: document) else {
      return ["§ \(title): sezione assente"]
    }
    var findings: [String] = []
    let confirmed = text.components(separatedBy: "**confermato**").count - 1
    let amended = text.components(separatedBy: "**emendato**").count - 1
    if confirmed + amended != 1 {
      findings.append("§ \(title): \(confirmed) **confermato** e \(amended) **emendato**")
    }
    if amended > 0 {
      let replacement = Self.subsection("Testo di sostituzione", in: text) ?? ""
      if replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        findings.append("§ \(title): emendato senza un «### Testo di sostituzione» non vuoto")
      }
    }
    let noOutcome = result.cells.filter {
      ($0.reasons[OutcomeReason.nessunEsitoApplicabile.rawValue] ?? 0) > 0
    }
    if !noOutcome.isEmpty, !noOutcome.contains(where: { Self.mentions(text, $0.cellId) }) {
      findings.append(
        "§ \(title): non cita alcuna cella nessun-esito-applicabile: "
          + noOutcome.map(\.cellId).joined(separator: ", "))
    }
    // Le proposte sono motivate da celle reali: ogni ID di cella citato esiste nel JSON.
    let cited = text.matches(
      of: #/[XSKD][0-9]{2}(?:-[a-z]+)*/(?:resume|compensate)(?:/[GL](?:-[a-z]+)+)?/#)
    for id in Set(cited.map { String($0.output) }).sorted() where cellsById[id] == nil {
      findings.append("§ \(title): cita la cella \(id), assente dal JSON")
    }
    return findings
  }

  /// Registra un problema per ogni rilievo, così che il resoconto li elenchi tutti.
  func expectNoFindings(_ findings: [String]) {
    for finding in findings {
      Issue.record(Comment(rawValue: finding))
    }
  }

  // MARK: - Test

  @Test("la misura è unica, si chiama come il suo measurementId ed è citata in § Configurazione")
  func configurationTracesTheMeasurement() {
    expectNoFindings(configurationFindings(document))
  }

  @Test("§ Punti di interruzione: una riga per punto enumerato, con esiti, ripetizioni e stato")
  func pointsMatchTheMeasurement() {
    expectNoFindings(pointFindings(document))
  }

  @Test("§ Compensazione: una riga per compensazione tentata, scostamento per scostamento")
  func compensationMatchesTheMeasurement() {
    expectNoFindings(compensationFindings(document))
  }

  @Test("§ Classi di errore: otto classi con ambito, celle provate, esiti ed errori osservati")
  func errorClassesMatchTheMeasurement() {
    expectNoFindings(classFindings(document))
  }

  @Test("§ Punti bloccati: una riga per cella bloccata, con ambito, ragione e i due rami")
  func blockedPointsMatchTheMeasurement() {
    expectNoFindings(blockedFindings(document))
  }

  @Test("§ Separazione: una riga per cella con coppie separate, con ciò che il recupero riferisce")
  func separationsMatchTheMeasurement() {
    expectNoFindings(separationFindings(document))
  }

  @Test("§ Esiti non supportabili: righe, motivi e tracce dal JSON, nessuna fra i bloccati")
  func unsupportedOutcomesAreSymmetric() {
    expectNoFindings(unsupportedFindings(document))
  }

  @Test("§ Esito su ADR-007: un solo marcatore, testo di sostituzione e celle reali citate")
  func verdictIsCompleteAndTraced() {
    expectNoFindings(verdictFindings(document))
  }

  // MARK: - Il controllo deve poter fallire

  /// Alterazioni in memoria di `RESULT.md` che i controlli dei passi 3, 6 e 8 devono rilevare.
  enum Alteration: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case pointOutcomeCount = "conteggio di un esito cambiato in § Punti di interruzione"
    case blockedCellRemoved = "cella bloccata rimossa da § Punti bloccati"
    case unsupportedMovedToBlocked = "cella NON_SUPPORTABILE spostata fra i bloccati"

    var testDescription: String { rawValue }
  }

  /// Indici delle righe di dati della tabella con intestazione `header` nella sezione `title`.
  static func dataLineIndices(_ lines: [String], section title: String, header: String) -> [Int] {
    guard let start = lines.firstIndex(of: "## \(title)") else { return [] }
    let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("## ") } ?? lines.count
    guard let headerIndex = lines[start..<end].firstIndex(where: { $0.hasPrefix(header) }) else {
      return []
    }
    var indices: [Int] = []
    for index in (headerIndex + 1)..<end {
      guard lines[index].hasPrefix("|") else { break }
      if !lines[index].hasPrefix("|---") { indices.append(index) }
    }
    return indices
  }

  /// Il documento alterato e l'ID (punto o cella) che l'alterazione colpisce; `nil` se il
  /// documento non ha le righe da alterare. Le righe scelte vengono dal documento stesso, non da
  /// stringhe scritte qui.
  static func alter(_ document: String, _ alteration: Alteration) -> (
    document: String, target: String
  )? {
    var lines = document.components(separatedBy: "\n")
    switch alteration {
    case .pointOutcomeCount:
      // La prima riga con un esito di ripresa: il primo conteggio scende di uno.
      for index in dataLineIndices(lines, section: pointsSection, header: pointsHeader) {
        var row = cells(of: lines[index])
        guard row.count == 7, let match = row[2].firstMatch(of: /\((\d+)\//),
          let count = Int(match.1), count > 0
        else { continue }
        row[2].replaceSubrange(match.range, with: "(\(count - 1)/")
        lines[index] = line(of: row)
        return (lines.joined(separator: "\n"), row[0])
      }
      return nil
    case .blockedCellRemoved:
      guard
        let index = dataLineIndices(lines, section: blockedSection, header: blockedHeader).first
      else { return nil }
      let target = cells(of: lines[index]).first ?? ""
      lines.remove(at: index)
      return (lines.joined(separator: "\n"), target)
    case .unsupportedMovedToBlocked:
      // La riga della prima cella non supportabile esce dalla sua tabella ed entra fra i
      // bloccati, con le colonne della prima riga bloccata: cambia solo l'ID.
      guard
        let unsupportedIndex = dataLineIndices(
          lines, section: unsupportedSection, header: unsupportedHeader
        ).first,
        let blockedIndex = dataLineIndices(lines, section: blockedSection, header: blockedHeader)
          .first,
        let target = cells(of: lines[unsupportedIndex]).first
      else { return nil }
      var moved = cells(of: lines[blockedIndex])
      moved[0] = target
      var altered: [String] = []
      for (index, text) in lines.enumerated() where index != unsupportedIndex {
        altered.append(text)
        if index == blockedIndex { altered.append(line(of: moved)) }
      }
      return (altered.joined(separator: "\n"), target)
    }
  }

  @Test("il confronto rileva un documento alterato in memoria", arguments: Alteration.allCases)
  func alteredDocumentIsDetected(_ alteration: Alteration) throws {
    // Il documento vero passa gli stessi controlli: il rilievo viene solo dall'alterazione.
    let checks: [(String) -> [String]] = [pointFindings, blockedFindings, unsupportedFindings]
    #expect(checks.flatMap { $0(document) } == [])

    let altered = try #require(
      Self.alter(document, alteration), "il documento non ha le righe da alterare")
    #expect(altered.document != document)
    #expect(!checks.flatMap { $0(altered.document) }.isEmpty)

    let target = altered.target
    switch alteration {
    case .pointOutcomeCount:
      #expect(enumeratedPoints.contains { $0.id == target })
      let findings = pointFindings(altered.document)
      #expect(findings.contains { $0.contains("punto \(target), esito ripresa") }, "\(findings)")
    case .blockedCellRemoved:
      #expect((cellsById[target]?.outcomes[OutcomeKind.bloccato.rawValue] ?? 0) > 0)
      let findings = blockedFindings(altered.document)
      #expect(
        findings.contains { $0.contains("manca la riga della cella \(target)") }, "\(findings)")
    case .unsupportedMovedToBlocked:
      let cell = try #require(cellsById[target])
      #expect((cell.outcomes[OutcomeKind.nonSupportabile.rawValue] ?? 0) > 0)
      #expect((cell.outcomes[OutcomeKind.bloccato.rawValue] ?? 0) == 0)
      let unsupported = unsupportedFindings(altered.document)
      #expect(
        unsupported.contains { $0.hasPrefix(Self.symmetryTag) && $0.contains(target) },
        "\(unsupported)")
      #expect(unsupported.contains { $0.contains("manca la riga della cella \(target)") })
      let blocked = blockedFindings(altered.document)
      #expect(blocked.contains { $0.contains("riga senza corrispondenza nel JSON: \(target)") })
    }
  }
}
