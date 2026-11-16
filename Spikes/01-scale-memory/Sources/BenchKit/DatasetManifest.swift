import CryptoKit
import Foundation

/// Manifest del dataset generato (`dataset-manifest.json`, nella directory di uscita e quindi non
/// versionato). Rende ogni conteggio verificabile: per ogni cella riporta unici, cloni, byte e
/// byte per megapixel effettivamente ottenuti.
///
/// `totals` e `cells` descrivono l'insieme da 50.000 file della cartella di scorrimento; le altre
/// cartelle sono descritte in `folders`.
public struct DatasetManifest: Codable, Sendable {
  public static let schemaIdentifier = "image-surfer/spike-01/dataset-manifest/v1"
  public static let fileName = "dataset-manifest.json"

  public var schema: String
  /// SHA-256 esadecimale di `dataset.json`.
  public var configDigest: String
  public var seed: UInt64
  public var profile: DatasetProfile
  public var generatedAt: Date
  public var generationSeconds: Double
  /// Vero se il volume di uscita ha accettato `clonefile(2)`; falso se i cloni sono copie piene.
  public var cloneSupported: Bool
  public var tolerance: Double
  public var totals: Totals
  public var cells: [Cell]
  public var calibration: [CalibrationEntry]
  public var folders: Folders

  /// Totali della cartella di scorrimento.
  public struct Totals: Codable, Sendable {
    public var total: Int
    public var uniqueTotal: Int
    public var cloneTotal: Int
    /// Byte logici, cloni compresi.
    public var bytesTotal: Int64
  }

  /// Una cella (formato × classe di risoluzione) di una cartella.
  public struct Cell: Codable, Sendable {
    public var format: ImageFormat
    /// `S`, `M`, `L`, oppure `anomalous` per gli elementi anomali.
    public var resolutionClass: String
    public var pixels: PixelSize
    public var uniqueCount: Int
    public var cloneCount: Int
    public var totalCount: Int
    /// Byte logici di tutti i file della cella, cloni compresi.
    public var bytesTotal: Int64
    /// Byte dei soli file unici.
    public var uniqueBytesTotal: Int64
    /// MB/MP dichiarato in `dataset.json`.
    public var bytesPerMegapixelTarget: Double
    /// MB/MP ottenuto, calcolato sui soli file unici (1 MB = 10⁶ byte).
    public var bytesPerMegapixelAchieved: Double
    /// Qualità di codifica usata, `nil` per i formati senza perdita.
    public var encoderQuality: Double?
    /// Vero se `bytesPerMegapixelAchieved` esce dalla tolleranza dichiarata.
    public var toleranceMiss: Bool
  }

  /// Calibrazione della qualità per formato e classe, condivisa da tutte le cartelle.
  public struct CalibrationEntry: Codable, Sendable {
    public var format: ImageFormat
    public var resolutionClass: String
    public var pixels: PixelSize
    public var quality: Double?
    public var sampleBytesPerMegapixel: Double
    public var iterations: Int
  }

  /// Una cartella del dataset.
  public struct Folder: Codable, Sendable {
    public var name: String
    /// `scroll`, `firstScreen`, `itemCost`, `anomalous`.
    public var role: String
    public var fileCount: Int
    public var uniqueCount: Int
    public var cloneCount: Int
    public var bytesTotal: Int64
    /// Indice TSV dei file, relativo alla directory del dataset.
    public var indexFile: String
    public var cells: [Cell]
  }

  public struct Folders: Codable, Sendable {
    public var scroll: Folder
    public var firstScreen: [Folder]
    public var itemCostPool: Folder
    public var anomalous: Folder
  }

  /// Carica il manifest dalla directory del dataset e ne calcola il digest SHA-256, da riportare
  /// in ogni risultato di misura.
  public static func load(fromDataDirectory directory: URL) throws -> (
    manifest: DatasetManifest, digest: String
  ) {
    let url = directory.appending(path: fileName, directoryHint: .notDirectory)
    let data = try Data(contentsOf: url)
    return (try decoder().decode(DatasetManifest.self, from: data), sha256Hex(data))
  }

  public static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  public static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

/// Una riga dell'indice di una cartella: dice per ogni file la cella, le dimensioni e se è un
/// clone (e di quale file unico).
public struct DatasetIndexEntry: Sendable, Equatable {
  public let name: String
  public let format: ImageFormat
  public let resolutionClass: String
  public let pixels: PixelSize
  public let isClone: Bool
  /// Nome del file unico di cui questo è un clone; `nil` per i file unici.
  public let cloneSource: String?

  public init(
    name: String, format: ImageFormat, resolutionClass: String, pixels: PixelSize,
    isClone: Bool, cloneSource: String?
  ) {
    self.name = name
    self.format = format
    self.resolutionClass = resolutionClass
    self.pixels = pixels
    self.isClone = isClone
    self.cloneSource = cloneSource
  }
}

/// Lettura e scrittura degli indici TSV delle cartelle.
public enum DatasetIndex {
  static let header = "name\tformat\tresolutionClass\twidth\theight\tkind\tsource"

  public static func encode(_ entries: [DatasetIndexEntry]) -> String {
    var lines = [header]
    for entry in entries {
      lines.append(
        [
          entry.name, entry.format.rawValue, entry.resolutionClass, String(entry.pixels.width),
          String(entry.pixels.height), entry.isClone ? "clone" : "unique", entry.cloneSource ?? "-",
        ].joined(separator: "\t"))
    }
    return lines.joined(separator: "\n") + "\n"
  }

  public static func load(from url: URL) throws -> [DatasetIndexEntry] {
    let text = try String(contentsOf: url, encoding: .utf8)
    return try text.split(separator: "\n").dropFirst().map { line in
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      guard fields.count == 7, let format = ImageFormat(rawValue: fields[1]),
        let width = Int(fields[3]), let height = Int(fields[4])
      else { throw IndexError.malformedLine(String(line)) }
      return DatasetIndexEntry(
        name: fields[0], format: format, resolutionClass: fields[2],
        pixels: PixelSize(width: width, height: height), isClone: fields[5] == "clone",
        cloneSource: fields[6] == "-" ? nil : fields[6])
    }
  }

  public enum IndexError: Error, CustomStringConvertible {
    case malformedLine(String)

    public var description: String {
      switch self {
      case .malformedLine(let line): "riga di indice malformata: \(line)"
      }
    }
  }
}
