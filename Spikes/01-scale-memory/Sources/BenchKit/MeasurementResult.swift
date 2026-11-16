import Foundation

/// Una ripetizione di una misura: i valori misurati e lo stato termico agli estremi.
///
/// Una ripetizione eseguita sotto limitazione termica deve restare riconoscibile, non mediata
/// alla cieca con le altre: per questo lo stato termico è registrato all'inizio e alla fine.
public struct Repetition: Codable, Sendable, Equatable {
  /// Indice della ripetizione, da 0.
  public var index: Int
  /// Valori misurati per grandezza (es. `firstScreenMs`). Ogni valore deve essere finito:
  /// un risultato con `NaN` o infiniti non si codifica in JSON.
  public var values: [String: Double]
  /// Marcature booleane della ripetizione (es. `footprintDidNotSettle`), vuote per difetto.
  public var flags: [String: Bool]
  /// Stato termico all'inizio della ripetizione.
  public var thermalStateAtStart: ThermalState
  /// Stato termico alla fine della ripetizione.
  public var thermalStateAtEnd: ThermalState

  /// Crea una ripetizione con valori già misurati.
  public init(
    index: Int,
    values: [String: Double],
    flags: [String: Bool] = [:],
    thermalStateAtStart: ThermalState,
    thermalStateAtEnd: ThermalState
  ) {
    self.index = index
    self.values = values
    self.flags = flags
    self.thermalStateAtStart = thermalStateAtStart
    self.thermalStateAtEnd = thermalStateAtEnd
  }

  /// Esegue `body` registrando lo stato termico prima e dopo.
  ///
  /// - Parameters:
  ///   - index: indice della ripetizione.
  ///   - body: il lavoro misurato; restituisce i valori per grandezza.
  public static func measure(
    index: Int,
    _ body: () throws -> [String: Double]
  ) rethrows -> Repetition {
    let thermalStateAtStart = ThermalState.current
    let values = try body()
    return Repetition(
      index: index,
      values: values,
      thermalStateAtStart: thermalStateAtStart,
      thermalStateAtEnd: .current
    )
  }

  /// `true` se all'inizio o alla fine lo stato termico non era nominale.
  public var ranUnderThermalPressure: Bool {
    !thermalStateAtStart.isNominal || !thermalStateAtEnd.isNominal
  }
}

/// Risultato di un'esecuzione del banco: schema `image-surfer/spike-01/measurement/v1`.
///
/// Ogni cifra pubblicata in `RESULT.md` rimanda al `measurementId` di un risultato come questo,
/// che porta con sé l'impronta hardware completa, i parametri, le ripetizioni e la dispersione.
public struct MeasurementResult: Codable, Sendable, Equatable {
  /// Identificatore dello schema scritto da questa versione del banco.
  public static let schemaIdentifier = "image-surfer/spike-01/measurement/v1"

  /// Identificatore dello schema del documento.
  public let schema: String
  /// Identificatore univoco dell'esecuzione (UUID in minuscolo), citato da `RESULT.md`.
  public let measurementId: String
  /// Nome del sottocomando del banco (es. `first-screen`).
  public var bench: String
  /// Inizio dell'esecuzione.
  public var startedAt: Date
  /// Fine dell'esecuzione.
  public var finishedAt: Date
  /// Profilo del dataset (`full` o `smoke`).
  public var profile: String
  /// Impronta del manifest del dataset misurato.
  public var datasetManifestDigest: String
  /// Hardware e ambiente di misura.
  public var host: HostFingerprint
  /// Parametri dell'esecuzione come testo (es. `intervalMs`, `window`).
  public var parameters: [String: String]
  /// Ripetizioni eseguite, nell'ordine di esecuzione.
  public var repetitions: [Repetition]
  /// Dispersione per grandezza.
  public var dispersion: [String: Dispersion]
  /// Grandezze derivate dal banco che non sono ripetizioni: per esempio la coppia raccomandata
  /// della banda di ritenzione, la pendenza della sessione lunga, le righe per cella del costo per
  /// elemento. Vuoto per difetto.
  public var derived: [String: JSONValue]

  /// Crea un risultato.
  ///
  /// - Parameters:
  ///   - measurementId: identificatore dell'esecuzione; per difetto un UUID nuovo.
  ///   - dispersion: dispersione per grandezza; se `nil` è calcolata da `repetitions` con
  ///     `dispersion(of:)`.
  public init(
    measurementId: String = MeasurementResult.newMeasurementId(),
    bench: String,
    startedAt: Date,
    finishedAt: Date,
    profile: String,
    datasetManifestDigest: String,
    host: HostFingerprint,
    parameters: [String: String] = [:],
    repetitions: [Repetition],
    dispersion: [String: Dispersion]? = nil,
    derived: [String: JSONValue] = [:]
  ) {
    self.schema = Self.schemaIdentifier
    self.measurementId = measurementId
    self.bench = bench
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.profile = profile
    self.datasetManifestDigest = datasetManifestDigest
    self.host = host
    self.parameters = parameters
    self.repetitions = repetitions
    self.dispersion = dispersion ?? Self.dispersion(of: repetitions)
    self.derived = derived
  }

  /// Un nuovo identificatore di esecuzione: UUID in minuscolo.
  public static func newMeasurementId() -> String {
    UUID().uuidString.lowercased()
  }

  /// Dispersione per grandezza su tutte le ripetizioni che la riportano.
  ///
  /// Una grandezza con un valore non finito non ha dispersione (vedi `Dispersion.init(_:)`) e
  /// manca dal dizionario restituito.
  public static func dispersion(of repetitions: [Repetition]) -> [String: Dispersion] {
    var series: [String: [Double]] = [:]
    for repetition in repetitions {
      for (metric, value) in repetition.values {
        series[metric, default: []].append(value)
      }
    }
    return series.compactMapValues { Dispersion($0) }
  }

  /// Codificatore JSON dello schema: chiavi ordinate, output leggibile, date ISO 8601.
  public static func jsonEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  /// Decodificatore JSON dello schema, simmetrico a `jsonEncoder()`.
  public static func jsonDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  /// Decodifica un risultato scritto da `ResultWriter`.
  public static func decode(from data: Data) throws -> MeasurementResult {
    try jsonDecoder().decode(MeasurementResult.self, from: data)
  }
}

/// Valore JSON generico, per le grandezze derivate di `MeasurementResult`.
///
/// `null` è codificato esplicitamente: una chiave con valore `null` resta presente nel JSON, ed
/// è così che un banco dichiara «nessuna raccomandazione» invece di omettere il campo.
public enum JSONValue: Codable, Sendable, Equatable {
  case number(Double)
  case string(String)
  case bool(Bool)
  case array([JSONValue])
  case object([String: JSONValue])
  case null

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }

  /// Il numero contenuto, se il valore è numerico.
  public var number: Double? {
    if case .number(let value) = self { return value }
    return nil
  }

  /// La stringa contenuta, se il valore è una stringa.
  public var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  /// Il booleano contenuto, se il valore è booleano.
  public var bool: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }

  /// Il dizionario contenuto, se il valore è un oggetto.
  public var object: [String: JSONValue]? {
    if case .object(let value) = self { return value }
    return nil
  }

  /// L'elenco contenuto, se il valore è un array.
  public var array: [JSONValue]? {
    if case .array(let value) = self { return value }
    return nil
  }

  public var isNull: Bool { self == .null }

  /// Elemento di un oggetto per chiave.
  public subscript(key: String) -> JSONValue? { object?[key] }

  /// Un numero da un intero, per comodità nei banchi.
  public static func int(_ value: Int) -> JSONValue { .number(Double(value)) }
}
