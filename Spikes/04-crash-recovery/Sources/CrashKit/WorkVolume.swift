import Darwin
import Foundation

extension URL {
  /// Percorso del file system, senza codifica percentuale e senza la barra finale che
  /// `path(percentEncoded:)` aggiunge agli URL di directory: `/a/b/lotto`, non `/a/b/lotto/`.
  public var fileSystemPath: String {
    var path = self.path(percentEncoded: false)
    while path.count > 1, path.hasSuffix("/") { path.removeLast() }
    return path
  }
}

/// Errori del volume di lavoro: ciascuno nomina il percorso o il comando coinvolto.
public enum WorkVolumeError: Error, Equatable, CustomStringConvertible, LocalizedError {
  /// Un comando esterno (`diskutil`) è uscito con stato diverso da 0, o per un segnale.
  case commandFailed(command: [String], status: Int32, stdout: String, stderr: String)
  /// Il volume non è montato sul punto di montaggio: nessuna azione è stata eseguita.
  case notMounted(mountPoint: String)
  /// `diskutil image attach` è riuscito, ma il punto di montaggio è ancora del volume ospite.
  case attachDidNotMount(mountPoint: String)
  /// `diskutil eject` è riuscito, ma il punto di montaggio è ancora di un volume diverso dall'ospite.
  case ejectLeftMounted(mountPoint: String)
  /// L'UUID del volume di un percorso non è disponibile.
  case volumeUUIDUnavailable(path: String)
  /// Una chiamata di sistema è fallita su un percorso del volume di lavoro.
  case systemCallFailed(call: String, path: String, errno: Int32)

  public var description: String {
    switch self {
    case .commandFailed(let command, let status, let stdout, let stderr):
      "comando fallito con stato \(status): \(command.joined(separator: " "))\n"
        + "stdout: \(stdout.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        + "stderr: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
    case .notMounted(let mountPoint):
      "volume di lavoro non montato su \(mountPoint): esegui prima `crashbench setup`"
    case .attachDidNotMount(let mountPoint):
      "dopo `diskutil image attach` il punto di montaggio \(mountPoint) è ancora del volume ospite"
    case .ejectLeftMounted(let mountPoint):
      "dopo `diskutil eject` il punto di montaggio \(mountPoint) è ancora montato"
    case .volumeUUIDUnavailable(let path):
      "UUID del volume non disponibile per \(path)"
    case .systemCallFailed(let call, let path, let code):
      "\(call) fallita su \(path): \(String(cString: strerror(code))) (errno \(code))"
    }
  }

  public var errorDescription: String? { description }
}

/// Volume APFS di lavoro su immagine disco, creato, montato ed espulso senza privilegi con
/// `diskutil image` (mai `hdiutil`, deprecato su macOS 27.2, mai `sudo`).
///
/// Tutto lo stato sta sotto `dataDirectory`:
/// - `work.asif`, l'immagine disco da 64 MB;
/// - `mnt/`, il punto di montaggio, che dopo l'espulsione resta come directory vuota del volume
///   ospite;
/// - `state/`, lo stato durevole del banco (log di intenti, istantanee), sul volume **ospite**:
///   espellere o riempire il volume di lavoro non lo tocca.
///
/// Il Cestino del volume è `<mnt>/.Trashes/<uid>`, sul volume stesso: il Cestino dell'utente non
/// viene mai toccato.
public struct WorkVolume: Sendable {
  /// Nome del volume APFS nell'immagine.
  public static let volumeName = "CrashBench"
  /// Dimensione dell'immagine, nella sintassi di `diskutil image create --size`.
  public static let imageSize = "64m"
  static let diskutil = "/usr/sbin/diskutil"
  /// Tentativi di `diskutil eject` prima di arrendersi, e pausa fra due tentativi.
  static let ejectAttempts = 5
  static let ejectRetryDelay: TimeInterval = 0.5
  /// Tentativi di `diskutil image attach` prima di arrendersi, e pausa fra due tentativi.
  static let attachAttempts = 5
  static let attachRetryDelay: TimeInterval = 1.0

  public let dataDirectory: URL

  public init(dataDirectory: URL = CrashPaths.defaultDataDirectory) {
    self.dataDirectory = dataDirectory
  }

  // MARK: - Percorsi

  /// `<data>/work.asif`.
  public var imageURL: URL {
    dataDirectory.appending(path: "work.asif", directoryHint: .notDirectory)
  }

  /// `<data>/mnt`.
  public var mountPoint: URL {
    dataDirectory.appending(path: "mnt", directoryHint: .isDirectory)
  }

  /// `<data>/state`, sul volume ospite.
  public var stateDirectory: URL {
    dataDirectory.appending(path: "state", directoryHint: .isDirectory)
  }

  /// `<mnt>/lotto`, la cartella di prova ripristinata dalle fixture.
  public var batchRoot: URL {
    mountPoint.appending(path: "lotto", directoryHint: .isDirectory)
  }

  /// `<mnt>/.quarantena`: sta sullo stesso volume, così spostare un file in quarantena e
  /// riportarlo conserva l'inode.
  public var quarantine: URL {
    mountPoint.appending(path: ".quarantena", directoryHint: .isDirectory)
  }

  /// `<mnt>/.Trashes/<getuid()>`, il Cestino del volume di lavoro. `.Trashes` non è elencabile,
  /// `.Trashes/<uid>` sì. Esiste solo dopo il primo spostamento nel Cestino del volume.
  public var trashDirectory: URL {
    mountPoint.appending(path: ".Trashes/\(getuid())", directoryHint: .isDirectory)
  }

  // MARK: - Identità del volume

  /// UUID del volume che contiene `url`, da `URLResourceValues.volumeUUIDString`.
  ///
  /// I valori in cache dell'URL vengono scartati prima della lettura: dopo un montaggio o
  /// un'espulsione lo stesso percorso appartiene a un altro volume.
  public static func volumeUUID(of url: URL) throws -> String {
    var fresh = URL(filePath: url.fileSystemPath)
    fresh.removeAllCachedResourceValues()
    guard let uuid = try fresh.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    else {
      throw WorkVolumeError.volumeUUIDUnavailable(path: url.fileSystemPath)
    }
    return uuid
  }

  /// Vero se il punto di montaggio appartiene a un volume diverso da quello di `dataDirectory`.
  /// Un punto di montaggio assente, o un UUID illeggibile, vale «non montato».
  public var isMounted: Bool {
    guard let mountUUID = try? Self.volumeUUID(of: mountPoint),
      let hostUUID = try? Self.volumeUUID(of: dataDirectory)
    else { return false }
    return mountUUID != hostUUID
  }

  // MARK: - Ciclo di vita

  /// Crea l'immagine disco se `work.asif` manca; altrimenti non fa nulla.
  public func ensureImage() throws {
    let fileManager = FileManager.default
    guard !fileManager.fileExists(atPath: imageURL.path(percentEncoded: false)) else { return }
    try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    try Self.run(
      Self.diskutil,
      [
        "image", "create", "blank", "--format", "ASIF", "--size", Self.imageSize,
        "--volumeName", Self.volumeName, "--fs", "APFS", imageURL.path(percentEncoded: false),
      ])
  }

  /// Monta l'immagine su `mnt/`, senza mostrarla nel Finder. Idempotente: se il volume è già
  /// montato non fa nulla.
  ///
  /// Con molti volumi agganciati in parallelo (la suite di test), `diskutil image attach` può
  /// fallire per un istante con «Failed to attach disk image». Come per `eject()`, un aggancio
  /// fallito si ripete fino a `attachAttempts` volte, a `attachRetryDelay` secondi l'una
  /// dall'altra; l'ultimo fallimento si propaga con stdout e stderr.
  public func attach() throws {
    try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
    for attempt in 1...Self.attachAttempts {
      guard !isMounted else { return }
      do {
        try Self.run(
          Self.diskutil,
          [
            "image", "attach", "--nobrowse", "--mountPoint", mountPoint.fileSystemPath,
            imageURL.path(percentEncoded: false),
          ])
      } catch WorkVolumeError.commandFailed where attempt < Self.attachAttempts {
        Thread.sleep(forTimeInterval: Self.attachRetryDelay)
        continue
      }
      guard isMounted else {
        throw WorkVolumeError.attachDidNotMount(mountPoint: mountPoint.fileSystemPath)
      }
      return
    }
  }

  /// Espelle il volume se è montato; altrimenti non fa nulla. Il punto di montaggio resta come
  /// directory vuota del volume ospite.
  ///
  /// Subito dopo un ripristino, un servizio di sistema può tenere occupato il volume per un istante
  /// (`diskutil` risponde «at least one volume could not be unmounted»). Un `diskutil eject`
  /// fallito si ripete quindi fino a `ejectAttempts` volte, a `ejectRetryDelay` secondi l'una
  /// dall'altra; l'ultimo fallimento si propaga con stdout e stderr. Nessuna espulsione forzata.
  public func eject() throws {
    for attempt in 1...Self.ejectAttempts {
      guard isMounted else { return }
      do {
        try Self.run(Self.diskutil, ["eject", mountPoint.fileSystemPath])
      } catch WorkVolumeError.commandFailed where attempt < Self.ejectAttempts {
        Thread.sleep(forTimeInterval: Self.ejectRetryDelay)
        continue
      }
      guard !isMounted else {
        throw WorkVolumeError.ejectLeftMounted(mountPoint: mountPoint.fileSystemPath)
      }
      return
    }
  }

  /// Ripristina la cartella di prova dalle fixture versionate.
  ///
  /// Con il volume smontato fallisce con `WorkVolumeError.notMounted` senza toccare nulla: il
  /// punto di montaggio sarebbe una directory del volume ospite.
  ///
  /// Altrimenti rimuove `batchRoot`, il contenuto di `trashDirectory` (se esiste), `quarantine` e il
  /// contenuto di `state/`; poi ricrea `batchRoot` copiando `fixtures/folder/*` con
  /// `copyfile(..., COPYFILE_ALL)`, e crea `quarantine` e `state/`. Come il glob `*`, la copia
  /// esclude i nomi nascosti.
  ///
  /// Prima di rimuovere, toglie `UF_IMMUTABLE` e `UF_APPEND` e rende scrivibili le directory sul
  /// volume di lavoro: una perturbazione rimasta applicata non impedisce il ripristino.
  public func resetBatchFolder() throws {
    guard isMounted else {
      throw WorkVolumeError.notMounted(mountPoint: mountPoint.fileSystemPath)
    }
    let fileManager = FileManager.default

    try Self.removeOnVolume(batchRoot)
    if fileManager.fileExists(atPath: trashDirectory.fileSystemPath) {
      for name in try fileManager.contentsOfDirectory(atPath: trashDirectory.fileSystemPath) {
        try Self.removeOnVolume(trashDirectory.appending(path: name))
      }
    }
    try Self.removeOnVolume(quarantine)
    if fileManager.fileExists(atPath: stateDirectory.fileSystemPath) {
      for name in try fileManager.contentsOfDirectory(atPath: stateDirectory.fileSystemPath) {
        try fileManager.removeItem(at: stateDirectory.appending(path: name))
      }
    }

    try fileManager.createDirectory(at: batchRoot, withIntermediateDirectories: false)
    let sources = try fileManager.contentsOfDirectory(
      atPath: CrashPaths.fixtureFolder.fileSystemPath
    )
    .filter { !$0.hasPrefix(".") }
    .sorted()
    for name in sources {
      let source = CrashPaths.fixtureFolder.appending(path: name, directoryHint: .notDirectory)
      let destination = batchRoot.appending(path: name, directoryHint: .notDirectory)
      guard
        copyfile(
          source.path(percentEncoded: false), destination.path(percentEncoded: false), nil,
          copyfile_flags_t(COPYFILE_ALL)) == 0
      else {
        throw WorkVolumeError.systemCallFailed(
          call: "copyfile", path: destination.path(percentEncoded: false), errno: errno)
      }
    }
    try fileManager.createDirectory(at: quarantine, withIntermediateDirectories: false)
    try fileManager.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
  }

  // MARK: - Supporto

  /// Rimuove `url` dal volume di lavoro, se esiste, dopo averlo reso rimovibile.
  private static func removeOnVolume(_ url: URL) throws {
    let path = url.fileSystemPath
    var info = stat()
    guard lstat(path, &info) == 0 else {
      if errno == ENOENT { return }
      throw WorkVolumeError.systemCallFailed(call: "lstat", path: path, errno: errno)
    }
    try makeRemovable(path)
    try FileManager.default.removeItem(atPath: path)
  }

  /// Toglie `UF_IMMUTABLE` e `UF_APPEND` da `path` e da tutto ciò che contiene, e aggiunge
  /// `rwx` per il proprietario alle directory, così che `removeItem` possa procedere.
  private static func makeRemovable(_ path: String) throws {
    var info = stat()
    guard lstat(path, &info) == 0 else {
      throw WorkVolumeError.systemCallFailed(call: "lstat", path: path, errno: errno)
    }
    let locks = UInt32(UF_IMMUTABLE | UF_APPEND)
    if info.st_flags & locks != 0, chflags(path, info.st_flags & ~locks) != 0 {
      throw WorkVolumeError.systemCallFailed(call: "chflags", path: path, errno: errno)
    }
    guard info.st_mode & S_IFMT == S_IFDIR else { return }
    if info.st_mode & S_IRWXU != S_IRWXU, chmod(path, (info.st_mode & 0o7777) | S_IRWXU) != 0 {
      throw WorkVolumeError.systemCallFailed(call: "chmod", path: path, errno: errno)
    }
    for name in try FileManager.default.contentsOfDirectory(atPath: path) {
      try makeRemovable(path + "/" + name)
    }
  }

  /// Esegue un comando e attende che esca. Uno stato diverso da 0 produce
  /// `WorkVolumeError.commandFailed` con stdout e stderr.
  ///
  /// Le due uscite vanno su file temporanei e non su pipe: nessuna delle due può riempirsi e
  /// bloccare il comando mentre si attende la sua fine.
  @discardableResult
  static func run(_ executable: String, _ arguments: [String]) throws -> String {
    let fileManager = FileManager.default
    let scratch = fileManager.temporaryDirectory.appending(
      path: "crashbench-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: scratch) }
    let outURL = scratch.appending(path: "stdout", directoryHint: .notDirectory)
    let errURL = scratch.appending(path: "stderr", directoryHint: .notDirectory)
    fileManager.createFile(atPath: outURL.path(percentEncoded: false), contents: nil)
    fileManager.createFile(atPath: errURL.path(percentEncoded: false), contents: nil)
    let outHandle = try FileHandle(forWritingTo: outURL)
    defer { try? outHandle.close() }
    let errHandle = try FileHandle(forWritingTo: errURL)
    defer { try? errHandle.close() }

    let process = Process()
    process.executableURL = URL(filePath: executable)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = outHandle
    process.standardError = errHandle
    try process.run()
    process.waitUntilExit()

    let stdout = String(decoding: try Data(contentsOf: outURL), as: UTF8.self)
    let stderr = String(decoding: try Data(contentsOf: errURL), as: UTF8.self)
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw WorkVolumeError.commandFailed(
        command: [executable] + arguments, status: process.terminationStatus, stdout: stdout,
        stderr: stderr)
    }
    return stdout
  }
}
