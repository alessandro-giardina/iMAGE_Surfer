import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Lotto di prova (`batch.json`)

/// Tipo di un'operazione del lotto: i tipi di FR-081 e FR-082.
public enum OperationKind: String, Codable, CaseIterable, Sendable {
  case rename
  case move
  case copy
  case trash
}

/// Operazione del lotto di prova. Si applica alla coppia `<stem>.jpg` + `<stem>.xmp`.
public struct BatchOperation: Codable, Sendable, Equatable {
  /// Identificativo dell'operazione, da `OP1` a `OP5`.
  public let id: String
  public let kind: OperationKind
  /// Radice dei due file della coppia, senza estensione (es. `IMG_0001`).
  public let stem: String
  /// Radice di destinazione relativa a `root`, senza estensione; `nil` solo per `trash`.
  public let to: String?

  public init(id: String, kind: OperationKind, stem: String, to: String?) {
    self.id = id
    self.kind = kind
    self.stem = stem
    self.to = to
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    kind = try container.decode(OperationKind.self, forKey: .kind)
    stem = try container.decode(String.self, forKey: .stem)
    to = try container.decodeIfPresent(String.self, forKey: .to)
    // Un Cestino non ha destinazione; ogni altro tipo ne ha bisogno.
    guard (kind == .trash) == (to == nil) else {
      throw DecodingError.dataCorruptedError(
        forKey: .to, in: container,
        debugDescription: "l'operazione \(id) di tipo \(kind.rawValue) ha `to` incoerente")
    }
  }
}

/// Definizione versionata del lotto di prova, `fixtures/batch.json`.
public struct BatchDefinition: Codable, Sendable, Equatable {
  public let batchId: String
  /// Cartella del lotto sul volume di lavoro, relativa al punto di montaggio (`lotto`).
  public let root: String
  /// Operazioni nell'ordine di esecuzione.
  public let operations: [BatchOperation]

  public init(batchId: String, root: String, operations: [BatchOperation]) {
    self.batchId = batchId
    self.root = root
    self.operations = operations
  }

  /// Carica la definizione da file.
  public static func load(from url: URL) throws -> BatchDefinition {
    try JSONDecoder().decode(BatchDefinition.self, from: Data(contentsOf: url))
  }
}

// MARK: - Manifest delle fixture (`MANIFEST.json`)

/// Manifest delle fixture: SHA-256 e dimensione di ogni file versionato, ordinati per percorso.
public struct FixtureManifest: Codable, Sendable, Equatable {
  public struct Entry: Codable, Sendable, Equatable {
    /// Percorso relativo alla directory delle fixture (es. `folder/IMG_0001.jpg`).
    public let path: String
    public let sha256: String
    public let size: Int64

    public init(path: String, sha256: String, size: Int64) {
      self.path = path
      self.sha256 = sha256
      self.size = size
    }
  }

  public let files: [Entry]

  public init(files: [Entry]) {
    self.files = files
  }
}

/// Errori di generazione e verifica delle fixture: ciascuno nomina il file coinvolto.
public enum FixtureError: Error, Equatable, CustomStringConvertible, LocalizedError {
  case missingBatch(path: String)
  case missingManifest(path: String)
  case alreadyExists(path: String)
  case encodingFailed(path: String)
  case missingFile(path: String)
  case sizeMismatch(path: String, expected: Int64, found: Int64)
  case digestMismatch(path: String, expected: String, found: String)
  case unlistedFile(path: String)

  /// Il file nominato dall'errore, relativo alla directory delle fixture.
  public var path: String {
    switch self {
    case .missingBatch(let path), .missingManifest(let path), .alreadyExists(let path),
      .encodingFailed(let path), .missingFile(let path), .unlistedFile(let path):
      path
    case .sizeMismatch(let path, _, _), .digestMismatch(let path, _, _):
      path
    }
  }

  public var description: String {
    switch self {
    case .missingBatch(let path):
      "definizione del lotto assente: \(path)"
    case .missingManifest(let path):
      "manifest delle fixture assente: \(path)"
    case .alreadyExists(let path):
      "la fixture \(path) esiste già: per sovrascriverla serve --force"
    case .encodingFailed(let path):
      "codifica JPEG fallita per \(path)"
    case .missingFile(let path):
      "fixture divergente dal manifest: \(path) è assente"
    case .sizeMismatch(let path, let expected, let found):
      "fixture divergente dal manifest: \(path) ha dimensione \(found), attesa \(expected)"
    case .digestMismatch(let path, let expected, let found):
      "fixture divergente dal manifest: \(path) ha SHA-256 \(found), atteso \(expected)"
    case .unlistedFile(let path):
      "fixture divergente dal manifest: \(path) è presente ma non è nel manifest"
    }
  }

  public var errorDescription: String? { description }
}

// MARK: - Costanti delle fixture

/// Forma del lotto di prova versionato: cinque coppie immagine+sidecar in `folder/`.
///
/// La convenzione del sidecar `<radice>.xmp` è una scelta della sola fixture: la decisione sul nome
/// appartiene al cancello n°3, e nessun esito di questo cancello ne dipende.
public enum Fixtures {
  public static let batchFileName = "batch.json"
  public static let manifestFileName = "MANIFEST.json"
  public static let folderName = "folder"
  public static let imageExtension = "jpg"
  public static let sidecarExtension = "xmp"
  /// Estensioni di una coppia nell'ordine dei passi: prima l'immagine, poi il sidecar.
  public static let pairExtensions = [imageExtension, sidecarExtension]
  public static let pairCount = 5
  public static let imageWidth = 64
  public static let imageHeight = 48
  public static let jpegQuality = 0.8

  /// Radice della coppia di indice `index` (da 1): `IMG_0001`, `IMG_0002`, …
  public static func stem(index: Int) -> String {
    String(format: "IMG_%04d", index)
  }

  /// Le radici delle cinque coppie, nell'ordine.
  public static var stems: [String] { (1...pairCount).map(stem(index:)) }

  /// SHA-256 esadecimale minuscolo.
  public static func sha256Hex(of data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  /// SHA-256 esadecimale minuscolo del contenuto di un file.
  public static func sha256Hex(ofFileAt url: URL) throws -> String {
    sha256Hex(of: try Data(contentsOf: url))
  }

  /// Colore pieno della coppia di indice `index`: RGB `(i*40, 255-i*40, 128)`.
  static func color(index: Int) -> (red: Int, green: Int, blue: Int) {
    (index * 40, 255 - index * 40, 128)
  }

  /// JPEG 64×48 di colore pieno, codificato con ImageIO alla qualità della fixture.
  static func jpegData(index: Int, path: String) throws -> Data {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard
      let context = CGContext(
        data: nil, width: imageWidth, height: imageHeight, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw FixtureError.encodingFailed(path: path) }
    let rgb = color(index: index)
    let components: [CGFloat] = [
      CGFloat(rgb.red) / 255, CGFloat(rgb.green) / 255, CGFloat(rgb.blue) / 255, 1,
    ]
    context.setFillColor(CGColor(colorSpace: colorSpace, components: components)!)
    context.fill(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    guard let image = context.makeImage() else { throw FixtureError.encodingFailed(path: path) }

    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw FixtureError.encodingFailed(path: path) }
    let properties = [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else {
      throw FixtureError.encodingFailed(path: path)
    }
    return data as Data
  }

  /// Sidecar XMP minimo con `xmp:Rating` uguale all'indice della coppia.
  static func sidecarData(index: Int) -> Data {
    let xml = """
      <x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/">
            <xmp:Rating>\(index)</xmp:Rating>
          </rdf:Description>
        </rdf:RDF>
      </x:xmpmeta>

      """
    return Data(xml.utf8)
  }
}

// MARK: - Generazione e verifica

/// Genera le cinque coppie della fixture in `<directory>/folder/` e scrive
/// `<directory>/MANIFEST.json`, che include anche `batch.json`.
///
/// `batch.json` è scritto a mano e deve già esistere in `directory`: la generazione lo legge e lo
/// mette nel manifest, ma non lo riscrive.
///
/// - Parameter force: senza `force`, un file da generare già presente è un errore e nessun file
///   viene scritto.
/// - Returns: il manifest scritto.
@discardableResult
public func makeFixtures(into directory: URL, force: Bool) throws -> FixtureManifest {
  let fileManager = FileManager.default
  let batchURL = directory.appending(path: Fixtures.batchFileName, directoryHint: .notDirectory)
  guard fileManager.fileExists(atPath: batchURL.path(percentEncoded: false)) else {
    throw FixtureError.missingBatch(path: Fixtures.batchFileName)
  }
  // La definizione deve essere valida prima di finire nel manifest.
  _ = try BatchDefinition.load(from: batchURL)

  // Tutto in memoria prima di scrivere: i file sono minuscoli, e un errore di codifica non lascia
  // fixture a metà.
  var outputs: [(path: String, data: Data)] = []
  for index in 1...Fixtures.pairCount {
    let stem = Fixtures.stem(index: index)
    let imagePath = "\(Fixtures.folderName)/\(stem).\(Fixtures.imageExtension)"
    let sidecarPath = "\(Fixtures.folderName)/\(stem).\(Fixtures.sidecarExtension)"
    outputs.append((imagePath, try Fixtures.jpegData(index: index, path: imagePath)))
    outputs.append((sidecarPath, Fixtures.sidecarData(index: index)))
  }

  if !force {
    for path in outputs.map(\.path) + [Fixtures.manifestFileName] {
      let url = directory.appending(path: path, directoryHint: .notDirectory)
      if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
        throw FixtureError.alreadyExists(path: path)
      }
    }
  }

  try fileManager.createDirectory(
    at: directory.appending(path: Fixtures.folderName, directoryHint: .isDirectory),
    withIntermediateDirectories: true)

  let batchData = try Data(contentsOf: batchURL)
  var entries = [
    FixtureManifest.Entry(
      path: Fixtures.batchFileName, sha256: Fixtures.sha256Hex(of: batchData),
      size: Int64(batchData.count))
  ]
  for output in outputs {
    try output.data.write(
      to: directory.appending(path: output.path, directoryHint: .notDirectory), options: .atomic)
    entries.append(
      FixtureManifest.Entry(
        path: output.path, sha256: Fixtures.sha256Hex(of: output.data),
        size: Int64(output.data.count)))
  }

  let manifest = FixtureManifest(files: entries.sorted { $0.path < $1.path })
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  var manifestData = try encoder.encode(manifest)
  manifestData.append(Data("\n".utf8))
  try manifestData.write(
    to: directory.appending(path: Fixtures.manifestFileName, directoryHint: .notDirectory),
    options: .atomic)
  return manifest
}

/// Verifica che le fixture in `directory` coincidano con `MANIFEST.json`.
///
/// Ricalcola dimensione e SHA-256 di ogni file del manifest, nell'ordine del manifest, e lancia un
/// errore che nomina il primo file divergente. Poi verifica che `folder/` non contenga voci assenti
/// dal manifest, file nascosti compresi: anche un `.DS_Store` cambierebbe il lotto copiato sul
/// volume di lavoro.
///
/// - Returns: il manifest verificato.
@discardableResult
public func verifyFixtures(at directory: URL) throws -> FixtureManifest {
  let fileManager = FileManager.default
  let manifestURL = directory.appending(
    path: Fixtures.manifestFileName, directoryHint: .notDirectory)
  guard fileManager.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
    throw FixtureError.missingManifest(path: Fixtures.manifestFileName)
  }
  let manifest = try JSONDecoder().decode(
    FixtureManifest.self, from: Data(contentsOf: manifestURL))

  for entry in manifest.files {
    let url = directory.appending(path: entry.path, directoryHint: .notDirectory)
    guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
      throw FixtureError.missingFile(path: entry.path)
    }
    let data = try Data(contentsOf: url)
    guard Int64(data.count) == entry.size else {
      throw FixtureError.sizeMismatch(
        path: entry.path, expected: entry.size, found: Int64(data.count))
    }
    let digest = Fixtures.sha256Hex(of: data)
    guard digest == entry.sha256 else {
      throw FixtureError.digestMismatch(path: entry.path, expected: entry.sha256, found: digest)
    }
  }

  let folder = directory.appending(path: Fixtures.folderName, directoryHint: .isDirectory)
  if fileManager.fileExists(atPath: folder.path(percentEncoded: false)) {
    let listed = Set(manifest.files.map(\.path))
    let present = try fileManager.subpathsOfDirectory(atPath: folder.path(percentEncoded: false))
      .map { "\(Fixtures.folderName)/\($0)" }
      .sorted()
    if let unlisted = present.first(where: { !listed.contains($0) }) {
      throw FixtureError.unlistedFile(path: unlisted)
    }
  }
  return manifest
}
