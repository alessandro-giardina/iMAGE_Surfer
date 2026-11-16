import Foundation
import UniformTypeIdentifiers

/// Percorsi del pacchetto del banco, risolti dalla posizione dei sorgenti e quindi
/// indipendenti dalla directory corrente da cui viene lanciato `swift run`.
public enum SpikePaths {
  /// `Spikes/01-scale-memory`.
  public static var packageRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Sources/BenchKit
      .deletingLastPathComponent()  // Sources
      .deletingLastPathComponent()  // radice del pacchetto
  }

  /// `Spikes/01-scale-memory/dataset.json`, la configurazione versionata.
  public static var defaultConfig: URL {
    packageRoot.appending(path: "dataset.json", directoryHint: .notDirectory)
  }

  /// `Spikes/01-scale-memory/.data`, la directory dei dati generati (non versionata).
  public static var defaultDataDirectory: URL {
    packageRoot.appending(path: ".data", directoryHint: .isDirectory)
  }
}

/// Formato di file del dataset.
public enum ImageFormat: String, Codable, CaseIterable, Sendable, Comparable {
  case jpeg
  case heic
  case png
  case tiff

  /// Tipo uniforme usato dall'encoder ImageIO.
  public var utType: UTType {
    switch self {
    case .jpeg: .jpeg
    case .heic: .heic
    case .png: .png
    case .tiff: .tiff
    }
  }

  public var fileExtension: String {
    switch self {
    case .jpeg: "jpg"
    case .heic: "heic"
    case .png: "png"
    case .tiff: "tif"
    }
  }

  /// Vero per i formati con perdita, la cui qualità di codifica viene calibrata.
  public var isLossy: Bool { self == .jpeg || self == .heic }

  /// Formato dedotto dall'estensione di un file del dataset.
  public init?(fileExtension: String) {
    guard
      let format = Self.allCases.first(where: { $0.fileExtension == fileExtension.lowercased() })
    else { return nil }
    self = format
  }

  public static func < (lhs: ImageFormat, rhs: ImageFormat) -> Bool {
    allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
  }
}

/// Classe di risoluzione (`S`, `M`, `L`).
public enum ResolutionClass: String, Codable, CaseIterable, Sendable, Comparable {
  case small = "S"
  case medium = "M"
  case large = "L"

  public static func < (lhs: ResolutionClass, rhs: ResolutionClass) -> Bool {
    allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
  }
}

/// Dimensioni in pixel, codificate in JSON come `[larghezza, altezza]`.
public struct PixelSize: Codable, Hashable, Sendable, CustomStringConvertible {
  public let width: Int
  public let height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }

  public var megapixels: Double { Double(width) * Double(height) / 1_000_000 }

  public var description: String { "\(width)x\(height)" }

  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    let width = try container.decode(Int.self)
    let height = try container.decode(Int.self)
    guard width > 0, height > 0, container.isAtEnd else {
      throw DatasetConfigError.invalidPixels(path: decoder.codingPath.pathString)
    }
    self.init(width: width, height: height)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(width)
    try container.encode(height)
  }
}

/// Cella del dataset: formato × classe di risoluzione.
public struct DatasetCell: Hashable, Sendable, Comparable, CustomStringConvertible {
  public let format: ImageFormat
  public let resolutionClass: ResolutionClass

  public init(format: ImageFormat, resolutionClass: ResolutionClass) {
    self.format = format
    self.resolutionClass = resolutionClass
  }

  /// Le dodici celle nell'ordine canonico: formato, poi classe.
  public static let all: [DatasetCell] = ImageFormat.allCases.flatMap { format in
    ResolutionClass.allCases.map { DatasetCell(format: format, resolutionClass: $0) }
  }

  public var description: String { "\(format.rawValue)/\(resolutionClass.rawValue)" }

  public static func < (lhs: DatasetCell, rhs: DatasetCell) -> Bool {
    (lhs.format, lhs.resolutionClass) < (rhs.format, rhs.resolutionClass)
  }
}

/// Conteggi per cella, codificati come `{ formato: { classe: conteggio } }`.
public struct CellDistribution: Codable, Sendable {
  public let counts: [DatasetCell: Int]

  public init(counts: [DatasetCell: Int]) {
    self.counts = counts
  }

  public var total: Int { counts.values.reduce(0, +) }

  public func count(for cell: DatasetCell) -> Int { counts[cell] ?? 0 }

  public init(from decoder: Decoder) throws {
    let raw = try [String: [String: Int]](from: decoder)
    let path = decoder.codingPath.pathString
    var counts: [DatasetCell: Int] = [:]
    for (formatKey, classes) in raw {
      guard let format = ImageFormat(rawValue: formatKey) else {
        throw DatasetConfigError.unknownCell(path: path, cell: formatKey)
      }
      for (classKey, count) in classes {
        guard let resolutionClass = ResolutionClass(rawValue: classKey) else {
          throw DatasetConfigError.unknownCell(path: path, cell: "\(formatKey)/\(classKey)")
        }
        guard count >= 0 else {
          throw DatasetConfigError.negativeCount(
            path: path, cell: "\(formatKey)/\(classKey)", count: count)
        }
        counts[DatasetCell(format: format, resolutionClass: resolutionClass)] = count
      }
    }
    self.counts = counts
  }

  public func encode(to encoder: Encoder) throws {
    var raw: [String: [String: Int]] = [:]
    for (cell, count) in counts {
      raw[cell.format.rawValue, default: [:]][cell.resolutionClass.rawValue] = count
    }
    try raw.encode(to: encoder)
  }

  /// Verifica che la somma delle celle combaci con il totale dichiarato; altrimenti
  /// lancia un errore che nomina la sezione e ogni cella con il suo conteggio.
  func validate(sumEquals declared: Int, path: String) throws {
    guard total == declared else {
      let cells = DatasetCell.all.filter { counts[$0] != nil }
        .map { "\($0)=\(count(for: $0))" }
        .joined(separator: ", ")
      throw DatasetConfigError.inconsistentDistribution(
        path: path, declared: declared, sum: total, cells: cells)
    }
  }
}

/// Configurazione della cartella da 50.000 file usata per lo scorrimento.
public struct ScrollFolderConfig: Codable, Sendable {
  public let name: String
  public let total: Int
  public let uniquePerCell: Int
  public let cloneRemainder: Bool
  public let distribution: CellDistribution

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    total = try container.decode(Int.self, forKey: .total)
    uniquePerCell = try container.decode(Int.self, forKey: .uniquePerCell)
    cloneRemainder = try container.decode(Bool.self, forKey: .cloneRemainder)
    distribution = try container.decode(CellDistribution.self, forKey: .distribution)
    let path = decoder.codingPath.pathString
    guard uniquePerCell > 0 else {
      throw DatasetConfigError.invalidValue(path: path, field: "uniquePerCell")
    }
    try distribution.validate(sumEquals: total, path: "\(path).distribution")
  }
}

/// Configurazione delle cartelle disgiunte per la misura di prima schermata.
public struct FirstScreenFoldersConfig: Codable, Sendable {
  public let count: Int
  public let size: Int
  public let unique: Bool
  public let cloneRemainder: Bool
  public let distribution: CellDistribution

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    count = try container.decode(Int.self, forKey: .count)
    size = try container.decode(Int.self, forKey: .size)
    unique = try container.decode(Bool.self, forKey: .unique)
    cloneRemainder = try container.decode(Bool.self, forKey: .cloneRemainder)
    distribution = try container.decode(CellDistribution.self, forKey: .distribution)
    let path = decoder.codingPath.pathString
    guard count > 0 else { throw DatasetConfigError.invalidValue(path: path, field: "count") }
    guard unique, !cloneRemainder else {
      // La prima schermata misura l'I/O a freddo: i cloni la falserebbero.
      throw DatasetConfigError.invalidValue(path: path, field: "unique/cloneRemainder")
    }
    try distribution.validate(sumEquals: size, path: "\(path).distribution")
  }
}

/// Pool di elementi unici per la misura del costo per elemento.
public struct ItemCostPoolConfig: Codable, Sendable {
  public let uniquePerCell: Int
}

/// Elementi anomali generati per calibrare il limite per singolo elemento.
public struct AnomalousItemConfig: Codable, Sendable {
  public let format: ImageFormat
  public let pixels: PixelSize
  public let count: Int
}

/// Sezione `smokeProfile`: gli stessi campi del profilo pieno, ridotti.
///
/// `resolutionClasses` è facoltativo: se presente sostituisce le dimensioni del profilo pieno, così
/// il profilo `smoke` resta rapido. Le sue cifre non hanno valore di misura.
public struct SmokeProfileConfig: Codable, Sendable {
  public let resolutionClasses: [String: PixelSize]?
  public let scrollFolder: ScrollFolderConfig
  public let firstScreenFolders: FirstScreenFoldersConfig
  public let itemCostPool: ItemCostPoolConfig
  public let anomalousItems: [AnomalousItemConfig]
}

/// Profilo di generazione e di misura.
public enum DatasetProfile: String, Codable, CaseIterable, Sendable {
  case full
  case smoke
}

/// Configurazione versionata del dataset (`dataset.json`).
public struct DatasetConfig: Codable, Sendable {
  public static let schemaIdentifier = "image-surfer/spike-01/dataset/v1"

  public let schema: String
  public let seed: UInt64
  public let resolutionClasses: [String: PixelSize]
  public let bytesPerMegapixelTarget: [String: Double]
  public let tolerance: Double
  public let scrollFolder: ScrollFolderConfig
  public let firstScreenFolders: FirstScreenFoldersConfig
  public let itemCostPool: ItemCostPoolConfig
  public let anomalousItems: [AnomalousItemConfig]
  public let smokeProfile: SmokeProfileConfig

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schema = try container.decode(String.self, forKey: .schema)
    guard schema == Self.schemaIdentifier else {
      throw DatasetConfigError.wrongSchema(found: schema)
    }
    seed = try container.decode(UInt64.self, forKey: .seed)
    resolutionClasses = try container.decode([String: PixelSize].self, forKey: .resolutionClasses)
    bytesPerMegapixelTarget = try container.decode(
      [String: Double].self, forKey: .bytesPerMegapixelTarget)
    tolerance = try container.decode(Double.self, forKey: .tolerance)
    scrollFolder = try container.decode(ScrollFolderConfig.self, forKey: .scrollFolder)
    firstScreenFolders = try container.decode(
      FirstScreenFoldersConfig.self, forKey: .firstScreenFolders)
    itemCostPool = try container.decode(ItemCostPoolConfig.self, forKey: .itemCostPool)
    anomalousItems = try container.decode([AnomalousItemConfig].self, forKey: .anomalousItems)
    smokeProfile = try container.decode(SmokeProfileConfig.self, forKey: .smokeProfile)

    for resolutionClass in ResolutionClass.allCases
    where resolutionClasses[resolutionClass.rawValue] == nil {
      throw DatasetConfigError.missingKey(path: "resolutionClasses", key: resolutionClass.rawValue)
    }
    for format in ImageFormat.allCases where bytesPerMegapixelTarget[format.rawValue] == nil {
      throw DatasetConfigError.missingKey(path: "bytesPerMegapixelTarget", key: format.rawValue)
    }
    guard tolerance > 0, tolerance < 1 else {
      throw DatasetConfigError.invalidValue(path: "", field: "tolerance")
    }
  }

  /// Carica e valida la configurazione da file.
  public static func load(from url: URL) throws -> DatasetConfig {
    try JSONDecoder().decode(DatasetConfig.self, from: Data(contentsOf: url))
  }

  /// Configurazione risolta per il profilo richiesto.
  public func plan(for profile: DatasetProfile) -> DatasetPlan {
    switch profile {
    case .full:
      DatasetPlan(
        profile: profile, seed: seed, tolerance: tolerance,
        pixels: Self.pixelTable(resolutionClasses),
        bytesPerMegapixelTarget: Self.targetTable(bytesPerMegapixelTarget),
        scrollFolder: scrollFolder, firstScreenFolders: firstScreenFolders,
        itemCostPool: itemCostPool, anomalousItems: anomalousItems)
    case .smoke:
      DatasetPlan(
        profile: profile, seed: seed, tolerance: tolerance,
        pixels: Self.pixelTable(smokeProfile.resolutionClasses ?? resolutionClasses),
        bytesPerMegapixelTarget: Self.targetTable(bytesPerMegapixelTarget),
        scrollFolder: smokeProfile.scrollFolder,
        firstScreenFolders: smokeProfile.firstScreenFolders,
        itemCostPool: smokeProfile.itemCostPool,
        anomalousItems: smokeProfile.anomalousItems)
    }
  }

  private static func pixelTable(_ raw: [String: PixelSize]) -> [ResolutionClass: PixelSize] {
    var table: [ResolutionClass: PixelSize] = [:]
    for resolutionClass in ResolutionClass.allCases {
      table[resolutionClass] = raw[resolutionClass.rawValue]
    }
    return table
  }

  private static func targetTable(_ raw: [String: Double]) -> [ImageFormat: Double] {
    var table: [ImageFormat: Double] = [:]
    for format in ImageFormat.allCases {
      table[format] = raw[format.rawValue]
    }
    return table
  }
}

/// Configurazione risolta per un profilo: è ciò che il generatore esegue.
public struct DatasetPlan: Sendable {
  public let profile: DatasetProfile
  public let seed: UInt64
  public let tolerance: Double
  public let pixels: [ResolutionClass: PixelSize]
  /// Obiettivo di byte per megapixel in MB/MP (1 MB = 10⁶ byte, 1 MP = 10⁶ pixel).
  public let bytesPerMegapixelTarget: [ImageFormat: Double]
  public let scrollFolder: ScrollFolderConfig
  public let firstScreenFolders: FirstScreenFoldersConfig
  public let itemCostPool: ItemCostPoolConfig
  public let anomalousItems: [AnomalousItemConfig]

  public func pixels(for cell: DatasetCell) -> PixelSize { pixels[cell.resolutionClass]! }

  public func target(for format: ImageFormat) -> Double { bytesPerMegapixelTarget[format]! }

  /// Byte attesi per un file della cella, secondo l'obiettivo dichiarato.
  public func expectedBytes(for cell: DatasetCell) -> Double {
    pixels(for: cell).megapixels * target(for: cell.format) * 1_000_000
  }

  /// Nomi delle cartelle di prima schermata: `p1-run-01`, `p1-run-02`, …
  public var firstScreenFolderNames: [String] {
    (1...firstScreenFolders.count).map { String(format: "p1-run-%02d", $0) }
  }

  /// Numero di file unici della cella nella cartella di scorrimento.
  public func scrollUniqueCount(for cell: DatasetCell) -> Int {
    let total = scrollFolder.distribution.count(for: cell)
    return scrollFolder.cloneRemainder ? min(scrollFolder.uniquePerCell, total) : total
  }

  /// Stima dello spazio richiesto: per ogni cella, conteggio unico × megapixel × obiettivo.
  /// I cloni APFS non occupano blocchi propri e non entrano nella stima.
  public var estimatedRequiredBytes: Int64 {
    var bytes = 0.0
    for cell in DatasetCell.all {
      let perFile = expectedBytes(for: cell)
      let firstScreen = firstScreenFolders.distribution.count(for: cell) * firstScreenFolders.count
      let unique = firstScreen + scrollUniqueCount(for: cell) + itemCostPool.uniquePerCell
      bytes += Double(unique) * perFile
    }
    for item in anomalousItems {
      bytes += Double(item.count) * item.pixels.megapixels * target(for: item.format) * 1_000_000
    }
    return Int64(bytes.rounded(.up))
  }
}

/// Errori di validazione della configurazione: ciascuno nomina la sezione o la cella incoerente.
public enum DatasetConfigError: Error, CustomStringConvertible, Equatable {
  case wrongSchema(found: String)
  case inconsistentDistribution(path: String, declared: Int, sum: Int, cells: String)
  case unknownCell(path: String, cell: String)
  case negativeCount(path: String, cell: String, count: Int)
  case invalidPixels(path: String)
  case invalidValue(path: String, field: String)
  case missingKey(path: String, key: String)

  public var description: String {
    switch self {
    case .wrongSchema(let found):
      "schema non riconosciuto: \(found), atteso \(DatasetConfig.schemaIdentifier)"
    case .inconsistentDistribution(let path, let declared, let sum, let cells):
      "distribuzione incoerente in \(path): la somma delle celle è \(sum), il totale dichiarato è "
        + "\(declared) (celle: \(cells))"
    case .unknownCell(let path, let cell):
      "cella sconosciuta \(cell) in \(path)"
    case .negativeCount(let path, let cell, let count):
      "conteggio negativo \(count) per la cella \(cell) in \(path)"
    case .invalidPixels(let path):
      "dimensioni in pixel non valide in \(path): attese [larghezza, altezza] positive"
    case .invalidValue(let path, let field):
      "valore non valido per \(field) in \(path.isEmpty ? "radice" : path)"
    case .missingKey(let path, let key):
      "chiave mancante \(key) in \(path)"
    }
  }
}

extension [CodingKey] {
  /// Percorso leggibile della chiave, per esempio `smokeProfile.scrollFolder`.
  var pathString: String {
    map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
  }
}
