import Darwin
import Foundation

/// Direzione di un passo: esecuzione in avanti o compensazione all'indietro.
public enum StepDirection: String, Codable, Sendable, CaseIterable {
  case forward
  case compensate
}

/// Decisione dell'utente su un lotto `bloccato`.
public enum UserDecision: String, Codable, Sendable, CaseIterable {
  case retry
  case abandon
}

/// Errori del log di intenti: ciascuno nomina il percorso o la riga coinvolta.
public enum IntentLogError: Error, Equatable, CustomStringConvertible, LocalizedError {
  /// Una chiamata di sistema è fallita sul log o sul file di evidenza.
  case systemCallFailed(call: String, path: String, errno: Int32)
  /// `write(2)` ha scritto meno byte della riga: il record non è su disco per intero.
  case partialWrite(path: String, expected: Int, written: Int)
  /// Una riga terminata da `\n` che non si decodifica, seguita da altre righe: non è una coda
  /// troncata da un arresto, è un log corrotto, e non viene mai ignorata. Righe numerate da 1.
  case logCorrotto(linea: Int)

  public var description: String {
    switch self {
    case .systemCallFailed(let call, let path, let code):
      "\(call) fallita su \(path): \(String(cString: strerror(code))) (errno \(code))"
    case .partialWrite(let path, let expected, let written):
      "scrittura parziale su \(path): \(written) byte su \(expected)"
    case .logCorrotto(let linea):
      "log di intenti corrotto alla riga \(linea): riga completa non decodificabile prima della coda"
    }
  }

  public var errorDescription: String? { description }
}

/// Log di intenti JSONL del lotto, sul volume **ospite** (`<data>/state/intent-log.jsonl`):
/// espellere o riempire il volume di lavoro non lo tocca.
///
/// **Durabilità.** Ogni record occupa una riga, scritta con una sola `write(2)` su un descrittore
/// aperto in `O_APPEND` e seguita da `fcntl(F_FULLFSYNC)`. Chi annuncia un'azione scrive il record
/// **prima** di eseguirla: quando `append` ritorna, il record è sul disco.
///
/// **Lettura.** Il lettore tollera una sola coda troncata, l'effetto di un arresto durante la
/// scrittura dell'ultimo record: la riconosce, la restituisce a parte e non la legge mai come record
/// valido. `repairTornTail()` la conserva come evidenza e tronca il file all'ultima riga completa.
/// Una riga non decodificabile che non sta in coda è invece un errore.
public struct IntentLog: Sendable {
  /// Nome del file del log nella directory di stato.
  public static let fileName = "intent-log.jsonl"

  /// `<data>/state/intent-log.jsonl` del volume dato.
  public static func defaultURL(in volume: WorkVolume) -> URL {
    volume.stateDirectory.appending(path: fileName, directoryHint: .notDirectory)
  }

  public let url: URL

  /// Log su `url`; predefinito: il log della directory dati predefinita del banco.
  public init(url: URL = IntentLog.defaultURL(in: WorkVolume())) {
    self.url = url
  }

  /// Log predefinito del volume dato, `<data>/state/intent-log.jsonl`.
  public init(volume: WorkVolume) {
    self.init(url: Self.defaultURL(in: volume))
  }

  // MARK: - Record

  /// Un record del log. In JSON è un oggetto su una sola riga, con chiavi ordinate e il
  /// discriminante `type`.
  public enum Record: Codable, Sendable, Equatable {
    /// Il piano completo, primo record di ogni esecuzione.
    case plan(BatchPlan)
    /// Esito del ricontrollo delle precondizioni prima di agire (FR-080).
    case recheck(ok: Bool, divergences: [String] = [])
    /// Cartelle create dal lotto, relative a `lotto/`.
    case prepare(created: [String])
    /// Intento di un passo, scritto prima dell'azione.
    case stepIntent(stepId: String, direction: StepDirection)
    /// Passo eseguito. `resultPath` è relativo al punto di montaggio del volume: per `trash` è il
    /// `resultingItemURL` restituito dal Cestino.
    case stepDone(stepId: String, direction: StepDirection, resultPath: String)
    /// Passo fallito. `errno` è assente quando l'errore non viene da POSIX: in quel caso `cocoa`
    /// porta dominio e codice dell'errore Cocoa (Cestino). `errorClass` e `scope` sono
    /// riempiti dal classificatore degli errori.
    case stepFailed(
      stepId: String, direction: StepDirection, syscall: String, errno: Int32?,
      cocoa: String? = nil, errorClass: String? = nil, scope: String? = nil)
    /// Avvio di un recupero, con la strategia chiesta e la direzione adottata.
    case recovery(strategy: String, direction: String, summary: String)
    /// Decisione dell'utente su un lotto `bloccato`.
    case decision(UserDecision)
    /// Esito di un'esecuzione o di un recupero.
    case outcome(outcome: String, reason: String? = nil, trace: [String] = [])
    /// Annullamento chiesto dall'utente dopo un lotto completato (FR-083).
    case undoRequested

    /// Valore del discriminante `type`.
    public enum Kind: String, Codable, Sendable, CaseIterable {
      case plan
      case recheck
      case prepare
      case stepIntent = "step-intent"
      case stepDone = "step-done"
      case stepFailed = "step-failed"
      case recovery
      case decision
      case outcome
      case undoRequested = "undo-requested"
    }

    public var kind: Kind {
      switch self {
      case .plan: .plan
      case .recheck: .recheck
      case .prepare: .prepare
      case .stepIntent: .stepIntent
      case .stepDone: .stepDone
      case .stepFailed: .stepFailed
      case .recovery: .recovery
      case .decision: .decision
      case .outcome: .outcome
      case .undoRequested: .undoRequested
      }
    }

    /// Record `step-failed` costruito da un fallimento grezzo di un passo.
    public static func failed(
      _ failure: StepFailure, direction: StepDirection, errorClass: String? = nil,
      scope: String? = nil
    ) -> Record {
      .stepFailed(
        stepId: failure.stepId, direction: direction, syscall: failure.syscall,
        errno: failure.errno, cocoa: failure.cocoa, errorClass: errorClass, scope: scope)
    }

    private enum CodingKeys: String, CodingKey {
      case type
      case plan
      case ok
      case divergences
      case created
      case stepId
      case direction
      case resultPath
      case syscall
      case errno
      case cocoa
      case errorClass
      case scope
      case strategy
      case summary
      case decision
      case outcome
      case reason
      case trace
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      switch try container.decode(Kind.self, forKey: .type) {
      case .plan:
        self = .plan(try container.decode(BatchPlan.self, forKey: .plan))
      case .recheck:
        self = .recheck(
          ok: try container.decode(Bool.self, forKey: .ok),
          divergences: try container.decode([String].self, forKey: .divergences))
      case .prepare:
        self = .prepare(created: try container.decode([String].self, forKey: .created))
      case .stepIntent:
        self = .stepIntent(
          stepId: try container.decode(String.self, forKey: .stepId),
          direction: try container.decode(StepDirection.self, forKey: .direction))
      case .stepDone:
        self = .stepDone(
          stepId: try container.decode(String.self, forKey: .stepId),
          direction: try container.decode(StepDirection.self, forKey: .direction),
          resultPath: try container.decode(String.self, forKey: .resultPath))
      case .stepFailed:
        self = .stepFailed(
          stepId: try container.decode(String.self, forKey: .stepId),
          direction: try container.decode(StepDirection.self, forKey: .direction),
          syscall: try container.decode(String.self, forKey: .syscall),
          errno: try container.decodeIfPresent(Int32.self, forKey: .errno),
          cocoa: try container.decodeIfPresent(String.self, forKey: .cocoa),
          errorClass: try container.decodeIfPresent(String.self, forKey: .errorClass),
          scope: try container.decodeIfPresent(String.self, forKey: .scope))
      case .recovery:
        self = .recovery(
          strategy: try container.decode(String.self, forKey: .strategy),
          direction: try container.decode(String.self, forKey: .direction),
          summary: try container.decode(String.self, forKey: .summary))
      case .decision:
        self = .decision(try container.decode(UserDecision.self, forKey: .decision))
      case .outcome:
        self = .outcome(
          outcome: try container.decode(String.self, forKey: .outcome),
          reason: try container.decodeIfPresent(String.self, forKey: .reason),
          trace: try container.decode([String].self, forKey: .trace))
      case .undoRequested:
        self = .undoRequested
      }
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(kind, forKey: .type)
      switch self {
      case .plan(let plan):
        try container.encode(plan, forKey: .plan)
      case .recheck(let ok, let divergences):
        try container.encode(ok, forKey: .ok)
        try container.encode(divergences, forKey: .divergences)
      case .prepare(let created):
        try container.encode(created, forKey: .created)
      case .stepIntent(let stepId, let direction):
        try container.encode(stepId, forKey: .stepId)
        try container.encode(direction, forKey: .direction)
      case .stepDone(let stepId, let direction, let resultPath):
        try container.encode(stepId, forKey: .stepId)
        try container.encode(direction, forKey: .direction)
        try container.encode(resultPath, forKey: .resultPath)
      case .stepFailed(
        let stepId, let direction, let syscall, let code, let cocoa, let errorClass, let scope):
        try container.encode(stepId, forKey: .stepId)
        try container.encode(direction, forKey: .direction)
        try container.encode(syscall, forKey: .syscall)
        try container.encodeIfPresent(code, forKey: .errno)
        try container.encodeIfPresent(cocoa, forKey: .cocoa)
        try container.encodeIfPresent(errorClass, forKey: .errorClass)
        try container.encodeIfPresent(scope, forKey: .scope)
      case .recovery(let strategy, let direction, let summary):
        try container.encode(strategy, forKey: .strategy)
        try container.encode(direction, forKey: .direction)
        try container.encode(summary, forKey: .summary)
      case .decision(let decision):
        try container.encode(decision, forKey: .decision)
      case .outcome(let outcome, let reason, let trace):
        try container.encode(outcome, forKey: .outcome)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encode(trace, forKey: .trace)
      case .undoRequested:
        break
      }
    }
  }

  // MARK: - Scrittura

  /// Serializza il record su una sola riga, senza `\n`: JSON con chiavi ordinate.
  static func encodeLine(_ record: Record) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(record)
  }

  /// Scrive il record come una riga terminata da `\n`, con una sola `write(2)` in `O_APPEND`
  /// seguita da `fcntl(F_FULLFSYNC)`. Una scrittura parziale o una sincronizzazione fallita
  /// lanciano un errore. La directory del log deve esistere.
  public func append(_ record: Record) throws {
    var line = try Self.encodeLine(record)
    line.append(0x0A)
    try Self.writeSynchronously(line, to: url, flags: O_WRONLY | O_CREAT | O_APPEND)
  }

  /// Scrive solo la prima metà (`count / 2` byte) della riga del record, senza `\n`, e la
  /// sincronizza: è il record troncato di un arresto durante la scrittura (punti `-torn`).
  public func appendTorn(_ record: Record) throws {
    let line = try Self.encodeLine(record)
    try Self.writeSynchronously(
      line.prefix(line.count / 2), to: url, flags: O_WRONLY | O_CREAT | O_APPEND)
  }

  // MARK: - Lettura

  /// Prefisso valido del log e coda troncata.
  ///
  /// Decodifica le righe terminate da `\n`. L'ultimo frammento, se non termina con `\n` oppure se
  /// non si decodifica, è la coda troncata (`tornTail`) e non entra fra i record. Una riga
  /// terminata e non decodificabile **prima** della coda lancia `IntentLogError.logCorrotto`.
  /// Un log assente è un log vuoto.
  public func read() throws -> (records: [Record], tornTail: String?) {
    let parsed = try parse()
    return (parsed.records, parsed.tail.map { String(decoding: $0, as: UTF8.self) })
  }

  /// Se il log ha una coda troncata, ne copia i byte in `<state>/torn-<ISO8601>.txt` (sincronizzato)
  /// e poi tronca il log all'ultima riga completa con `ftruncate`, seguito da `F_FULLFSYNC`.
  ///
  /// Va chiamato prima di ogni `append` successivo a un arresto: altrimenti la riga nuova si
  /// fonderebbe con il frammento in una riga non decodificabile.
  ///
  /// - Returns: il file di evidenza, oppure `nil` se il log non aveva una coda troncata.
  @discardableResult
  public func repairTornTail() throws -> URL? {
    let parsed = try parse()
    guard let tail = parsed.tail else { return nil }

    let formatter = ISO8601DateFormatter()
    // Formato ISO 8601 di base, senza `:` nel nome del file.
    formatter.formatOptions = [
      .withYear, .withMonth, .withDay, .withTime, .withFractionalSeconds, .withTimeZone,
    ]
    let evidence = url.deletingLastPathComponent().appending(
      path: "torn-\(formatter.string(from: Date())).txt", directoryHint: .notDirectory)
    // `O_EXCL`: un'evidenza già presente non viene mai sovrascritta.
    try Self.writeSynchronously(tail, to: evidence, flags: O_WRONLY | O_CREAT | O_EXCL)

    let path = url.fileSystemPath
    let descriptor = open(path, O_WRONLY)
    guard descriptor >= 0 else {
      throw IntentLogError.systemCallFailed(call: "open", path: path, errno: errno)
    }
    var failure: IntentLogError?
    if ftruncate(descriptor, off_t(parsed.tailOffset)) != 0 {
      failure = .systemCallFailed(call: "ftruncate", path: path, errno: errno)
    } else if fcntl(descriptor, F_FULLFSYNC) == -1 {
      failure = .systemCallFailed(call: "fcntl(F_FULLFSYNC)", path: path, errno: errno)
    }
    try Self.close(descriptor, path: path, after: failure)
    return evidence
  }

  /// Risultato dell'analisi del file: record validi, byte della coda troncata e posizione da cui
  /// la coda comincia (la lunghezza del prefisso valido).
  private struct Parsed {
    var records: [Record]
    var tail: Data?
    var tailOffset: Int
  }

  private func parse() throws -> Parsed {
    let path = url.fileSystemPath
    var info = stat()
    guard lstat(path, &info) == 0 else {
      let code = errno
      if code == ENOENT { return Parsed(records: [], tail: nil, tailOffset: 0) }
      throw IntentLogError.systemCallFailed(call: "lstat", path: path, errno: code)
    }
    let bytes = [UInt8](try Data(contentsOf: url))

    // Righe terminate da `\n` (senza il terminatore) e frammento finale non terminato.
    var lines: [Range<Int>] = []
    var start = 0
    for (index, byte) in bytes.enumerated() where byte == 0x0A {
      lines.append(start..<index)
      start = index + 1
    }
    let fragment = start < bytes.count ? start..<bytes.count : nil

    let decoder = JSONDecoder()
    var records: [Record] = []
    for (number, range) in lines.enumerated() {
      if let record = try? decoder.decode(Record.self, from: Data(bytes[range])) {
        records.append(record)
        continue
      }
      // Una riga terminata ma non decodificabile è la coda solo se è l'ultima cosa nel file.
      guard number == lines.count - 1, fragment == nil else {
        throw IntentLogError.logCorrotto(linea: number + 1)
      }
      return Parsed(records: records, tail: Data(bytes[range]), tailOffset: range.lowerBound)
    }
    if let fragment {
      return Parsed(records: records, tail: Data(bytes[fragment]), tailOffset: fragment.lowerBound)
    }
    return Parsed(records: records, tail: nil, tailOffset: bytes.count)
  }

  // MARK: - Supporto

  /// Apre `url` con `flags`, scrive `data` con una sola `write(2)`, sincronizza con
  /// `F_FULLFSYNC` e chiude. Ogni fallimento, compresa una scrittura parziale, lancia un errore.
  private static func writeSynchronously(_ data: Data, to url: URL, flags: Int32) throws {
    let path = url.fileSystemPath
    let descriptor = open(path, flags, 0o644)
    guard descriptor >= 0 else {
      throw IntentLogError.systemCallFailed(call: "open", path: path, errno: errno)
    }
    var failure: IntentLogError?
    let written = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    if written < 0 {
      failure = .systemCallFailed(call: "write", path: path, errno: errno)
    } else if written != data.count {
      failure = .partialWrite(path: path, expected: data.count, written: written)
    } else if fcntl(descriptor, F_FULLFSYNC) == -1 {
      failure = .systemCallFailed(call: "fcntl(F_FULLFSYNC)", path: path, errno: errno)
    }
    try close(descriptor, path: path, after: failure)
  }

  /// Chiude il descrittore in ogni caso; lancia il fallimento precedente, se c'è, altrimenti
  /// l'eventuale fallimento di `close`.
  private static func close(_ descriptor: Int32, path: String, after failure: IntentLogError?)
    throws
  {
    let closed = Darwin.close(descriptor)
    let code = errno
    if let failure { throw failure }
    guard closed == 0 else {
      throw IntentLogError.systemCallFailed(call: "close", path: path, errno: code)
    }
  }
}
