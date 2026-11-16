import Darwin
import Foundation

/// Errori di costruzione del piano del lotto.
public enum BatchPlanError: Error, Equatable, CustomStringConvertible, LocalizedError {
  /// La cartella del lotto di `batch.json` non è quella del volume di lavoro.
  case rootMismatch(definition: String, volume: String)

  public var description: String {
    switch self {
    case .rootMismatch(let definition, let volume):
      "la cartella del lotto di batch.json (\(definition)) non è quella del volume di lavoro "
        + "(\(volume))"
    }
  }

  public var errorDescription: String? { description }
}

/// Un passo del piano: un solo file della coppia, mosso da una sola operazione.
///
/// I percorsi sono relativi alla cartella del lotto (`lotto/`): `IMG_0002.jpg`,
/// `selezione/IMG_0002.jpg`.
public struct PlannedStep: Codable, Sendable, Equatable {
  /// Identificativo del passo, da `S01` a `S10`.
  public let id: String
  /// Operazione di `batch.json` da cui il passo deriva (`OP1`…`OP5`).
  public let opId: String
  public let kind: OperationKind
  /// File di origine, relativo a `lotto/`.
  public let source: String
  /// File di arrivo, relativo a `lotto/`; `nil` per `trash`.
  public let destination: String?
  /// SHA-256 della sorgente letto dal volume quando il piano è stato costruito.
  public let sha256: String
  /// Dimensione della sorgente, in byte, letta dal volume.
  public let size: Int64

  public init(
    id: String, opId: String, kind: OperationKind, source: String, destination: String?,
    sha256: String, size: Int64
  ) {
    self.id = id
    self.opId = opId
    self.kind = kind
    self.source = source
    self.destination = destination
    self.sha256 = sha256
    self.size = size
  }
}

/// Piano del lotto: l'espansione di `batch.json` in passi atomici, registrata nel log di intenti
/// **prima** di qualunque azione.
///
/// È la sola conoscenza che la macchina ha del lotto: il recupero la rilegge dal log e confronta il
/// disco con i digest e le posizioni che il piano dichiara.
public struct BatchPlan: Codable, Sendable, Equatable {
  /// Identità di questa esecuzione del lotto; nomina anche i file temporanei di copia.
  public let planId: UUID
  public let batchId: String
  /// UUID del volume che contiene `lotto/` quando il piano è stato costruito. Un passo `trash` si
  /// rifiuta di agire su una sorgente di un altro volume.
  public let volumeUUID: String
  /// Passi nell'ordine di esecuzione.
  public let steps: [PlannedStep]
  /// Cartelle padre delle destinazioni che non esistevano alla costruzione del piano, relative a
  /// `lotto/`, nell'ordine di creazione (prima le cartelle esterne).
  public let directoriesToCreate: [String]

  public init(
    planId: UUID, batchId: String, volumeUUID: String, steps: [PlannedStep],
    directoriesToCreate: [String]
  ) {
    self.planId = planId
    self.batchId = batchId
    self.volumeUUID = volumeUUID
    self.steps = steps
    self.directoriesToCreate = directoriesToCreate
  }

  /// Il passo con l'identificativo dato, se esiste.
  public func step(_ id: String) -> PlannedStep? {
    steps.first { $0.id == id }
  }

  /// Espande il lotto in passi leggendo dal volume digest e dimensione di ogni sorgente.
  ///
  /// Ogni operazione dà due passi, nell'ordine di `Fixtures.pairExtensions`: prima l'immagine
  /// (`.jpg`), poi il sidecar (`.xmp`). I passi sono numerati da `S01` nell'ordine delle
  /// operazioni. Esige il volume montato: un piano costruito sul volume ospite registrerebbe
  /// l'identità sbagliata.
  public static func make(definition: BatchDefinition, volume: WorkVolume) throws -> BatchPlan {
    guard volume.isMounted else {
      throw WorkVolumeError.notMounted(mountPoint: volume.mountPoint.fileSystemPath)
    }
    guard definition.root == volume.batchRoot.lastPathComponent else {
      throw BatchPlanError.rootMismatch(
        definition: definition.root, volume: volume.batchRoot.lastPathComponent)
    }

    var steps: [PlannedStep] = []
    for operation in definition.operations {
      for fileExtension in Fixtures.pairExtensions {
        let source = "\(operation.stem).\(fileExtension)"
        let sourceURL = volume.batchURL(source)
        steps.append(
          PlannedStep(
            id: String(format: "S%02d", steps.count + 1),
            opId: operation.id,
            kind: operation.kind,
            source: source,
            destination: operation.to.map { "\($0).\(fileExtension)" },
            sha256: try Fixtures.sha256Hex(ofFileAt: sourceURL),
            size: try fileSize(sourceURL)))
      }
    }

    // Ogni antenato di una destinazione che non esiste ancora, una volta sola, prima i più esterni.
    var directoriesToCreate: [String] = []
    for destination in steps.compactMap(\.destination) {
      var ancestor = ""
      for component in destination.split(separator: "/").dropLast() {
        ancestor = ancestor.isEmpty ? String(component) : "\(ancestor)/\(component)"
        guard !directoriesToCreate.contains(ancestor) else { continue }
        let path = volume.batchURL(ancestor).fileSystemPath
        var info = stat()
        if lstat(path, &info) == 0 { continue }
        let code = errno
        guard code == ENOENT else {
          throw WorkVolumeError.systemCallFailed(call: "lstat", path: path, errno: code)
        }
        directoriesToCreate.append(ancestor)
      }
    }

    return BatchPlan(
      planId: UUID(),
      batchId: definition.batchId,
      volumeUUID: try WorkVolume.volumeUUID(of: volume.batchRoot),
      steps: steps,
      directoriesToCreate: directoriesToCreate)
  }

  private static func fileSize(_ url: URL) throws -> Int64 {
    let path = url.fileSystemPath
    var info = stat()
    guard lstat(path, &info) == 0 else {
      throw WorkVolumeError.systemCallFailed(call: "lstat", path: path, errno: errno)
    }
    return Int64(info.st_size)
  }
}

extension WorkVolume {
  /// URL di un percorso relativo alla cartella del lotto (`lotto/`).
  public func batchURL(_ relativePath: String) -> URL {
    batchRoot.appending(path: relativePath, directoryHint: .inferFromPath)
  }

  /// Percorso di `url` relativo al punto di montaggio: `lotto/selezione/IMG_0002.jpg`,
  /// `.Trashes/502/IMG_0005.jpg`. Un percorso fuori dal punto di montaggio resta assoluto.
  ///
  /// Il confronto avviene sia sui percorsi così come sono sia con i collegamenti simbolici
  /// risolti: il Cestino può restituire `/private/tmp/…` per un punto di montaggio scritto
  /// `/tmp/…`.
  public func volumeRelativePath(of url: URL) -> String {
    let candidates = [
      (url.fileSystemPath, mountPoint.fileSystemPath),
      (
        url.resolvingSymlinksInPath().fileSystemPath,
        mountPoint.resolvingSymlinksInPath().fileSystemPath
      ),
    ]
    for (path, root) in candidates where path.hasPrefix(root + "/") {
      return String(path.dropFirst(root.count + 1))
    }
    return url.fileSystemPath
  }

  /// URL di un percorso relativo al punto di montaggio, l'inverso di `volumeRelativePath(of:)`.
  public func volumeURL(_ relativePath: String) -> URL {
    relativePath.hasPrefix("/")
      ? URL(filePath: relativePath)
      : mountPoint.appending(path: relativePath, directoryHint: .inferFromPath)
  }
}
