import Darwin
import Foundation

/// Fallimento grezzo di un passo: la chiamata fallita, il suo errno e il percorso. Non porta una
/// classe di errore: la classificazione per ambito è del classificatore degli errori.
///
/// `errno` è assente quando l'errore non viene da POSIX. È il caso di `FileManager.trashItem` su un
/// file con `UF_IMMUTABLE`, che produce `NSCocoaErrorDomain 513 / NSOSStatusErrorDomain -5000`
/// senza alcun errno (baseline): allora `cocoa` porta dominio e codice dell'errore e di quello
/// sottostante.
///
/// Un passo che si rifiuta di agire senza tentare una chiamata di sistema ha `errno` e `cocoa`
/// assenti e per `syscall` uno dei rifiuti: `StepFailure.digestCheck`, `.volumeCheck`,
/// `.trashLookup`, `.planCheck`.
public struct StepFailure: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
  /// Rifiuto: il file su cui il passo dovrebbe agire non ha il digest del piano.
  public static let digestCheck = "verifica-digest"
  /// Rifiuto: la sorgente di un passo `trash` sta su un volume diverso da `plan.volumeUUID`.
  public static let volumeCheck = "verifica-volume"
  /// Rifiuto: in compensazione di un `trash`, il Cestino non ha una e una sola voce con il digest.
  public static let trashLookup = "cerca-nel-cestino"
  /// Rifiuto: il passo non è coerente con il suo tipo (per esempio una copia senza destinazione).
  public static let planCheck = "verifica-piano"

  public let stepId: String
  /// Chiamata fallita (`renamex_np`, `copyfile`, `trashItem`, `rmdir`, …) o rifiuto.
  public let syscall: String
  public let errno: Int32?
  /// `"<dominio> <codice>"`, seguito da `" / <dominio sottostante> <codice>"` se c'è un errore
  /// sottostante; solo quando l'errore non ha un errno.
  public let cocoa: String?
  /// Percorso assoluto su cui la chiamata è fallita.
  public let path: String

  public init(stepId: String, syscall: String, errno: Int32?, cocoa: String? = nil, path: String) {
    self.stepId = stepId
    self.syscall = syscall
    self.errno = errno
    self.cocoa = cocoa
    self.path = path
  }

  /// Fallimento da un errore di Foundation. Se l'`NSError`, o il suo `NSUnderlyingErrorKey`, è in
  /// `NSPOSIXErrorDomain`, `errno` è quel codice; altrimenti `errno` è assente e `cocoa` nomina
  /// dominio e codice dell'errore e di quello sottostante.
  public init(stepId: String, syscall: String, path: String, error: any Error) {
    let error = error as NSError
    let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
    if error.domain == NSPOSIXErrorDomain {
      self.init(stepId: stepId, syscall: syscall, errno: Int32(error.code), path: path)
    } else if let underlying, underlying.domain == NSPOSIXErrorDomain {
      self.init(stepId: stepId, syscall: syscall, errno: Int32(underlying.code), path: path)
    } else {
      let cocoa =
        "\(error.domain) \(error.code)"
        + (underlying.map { " / \($0.domain) \($0.code)" } ?? "")
      self.init(stepId: stepId, syscall: syscall, errno: nil, cocoa: cocoa, path: path)
    }
  }

  public var description: String {
    let cause =
      if let errno {
        "\(String(cString: strerror(errno))) (errno \(errno))"
      } else if let cocoa {
        "errore Cocoa \(cocoa)"
      } else {
        "rifiuto senza chiamata di sistema"
      }
    return "passo \(stepId): \(syscall) fallita su \(path): \(cause)"
  }

  public var errorDescription: String? { description }
}

/// Stato di un passo osservato sul disco, non dedotto dal log.
///
/// I percorsi sono relativi al punto di montaggio del volume (`lotto/…`, `.Trashes/<uid>/…`).
public enum StepObservation: Equatable, Sendable {
  /// Il passo non è stato eseguito: il file è nella posizione di origine con il digest del piano.
  case notDone
  /// Il passo è stato eseguito: il file è in `resultPath` con il digest del piano.
  case done(resultPath: String)
  /// Copia interrotta: la destinazione manca e il file temporaneo di copia esiste.
  case partial(tempPath: String)
  /// Nessuno degli stati attesi: posizione ispezionata → digest trovato, `nil` se assente.
  case anomaly(found: [String: String?])
}

/// Passi idempotenti del lotto: osservazione dal disco, esecuzione e compensazione.
///
/// Ogni funzione osserva il disco prima di agire e non agisce se il passo è già nello stato
/// voluto: `execute` su un passo fatto, o `compensate` su un passo non fatto, non toccano nulla.
/// Le chiamate non sovrascrivono mai (`RENAME_EXCL`, `COPYFILE_EXCL`) e non eliminano mai un file
/// del lotto (NFR-A1): una copia da compensare va nel Cestino. Si eliminano con `unlink` solo i
/// file temporanei di copia, artefatti del banco.
///
/// Su uno stato anomalo il passo tenta comunque la chiamata, così che l'errore reale (`ENOENT`,
/// `EEXIST`, …) arrivi al classificatore, ma non agisce mai su un file con un digest diverso da
/// quello del piano: in quel caso lancia uno `StepFailure` di rifiuto senza toccare il disco.
///
/// Ogni chiamata fallita lancia uno `StepFailure`.
public enum Steps {
  /// `stepId` dei fallimenti di `compensatePrepare(created:volume:)`.
  public static let prepareStepId = "prepare"
  /// Valore di `StepObservation.anomaly` per una posizione occupata da una voce che non è un file
  /// regolare.
  public static let nonRegularDigest = "non-regolare"

  // MARK: - Osservazione

  /// File temporaneo di copia del passo: `.<nome destinazione>.partial-<planId>`, nella cartella di
  /// destinazione; `nil` per un passo senza destinazione.
  public static func tempURL(for step: PlannedStep, plan: BatchPlan, volume: WorkVolume) -> URL? {
    step.destination.map { tempURL(destination: volume.batchURL($0), plan: plan) }
  }

  private static func tempURL(destination: URL, plan: BatchPlan) -> URL {
    destination.deletingLastPathComponent().appending(
      path: ".\(destination.lastPathComponent).partial-\(plan.planId.uuidString)",
      directoryHint: .notDirectory)
  }

  /// Stato del passo letto dal disco.
  ///
  /// | Tipo | Stato osservato | Risultato |
  /// |---|---|---|
  /// | `rename`, `move` | sorgente con il digest e destinazione assente | `.notDone` |
  /// | `rename`, `move` | destinazione con il digest e sorgente assente | `.done` |
  /// | `copy` | destinazione con il digest | `.done` |
  /// | `copy` | sorgente con il digest, destinazione assente, temporaneo presente | `.partial` |
  /// | `copy` | sorgente con il digest, destinazione assente | `.notDone` |
  /// | `trash` | sorgente con il digest | `.notDone` |
  /// | `trash` | sorgente assente, **una sola** voce del Cestino con il digest | `.done` |
  ///
  /// Ogni altra combinazione è `.anomaly`, con le posizioni ispezionate. Nel Cestino si cerca per
  /// digest, non per nome: una collisione rinomina la voce con un suffisso orario.
  public static func observe(
    _ step: PlannedStep, plan: BatchPlan, volume: WorkVolume
  ) throws -> StepObservation {
    let source = volume.batchURL(step.source)
    let sourceDigest = try digest(of: source, stepId: step.id)
    let relative = volume.volumeRelativePath(of:)

    switch step.kind {
    case .rename, .move:
      let destination = try destinationURL(of: step, volume: volume)
      let destinationDigest = try digest(of: destination, stepId: step.id)
      if sourceDigest == step.sha256, destinationDigest == nil { return .notDone }
      if destinationDigest == step.sha256, sourceDigest == nil {
        return .done(resultPath: relative(destination))
      }
      return .anomaly(found: [
        relative(source): sourceDigest, relative(destination): destinationDigest,
      ])

    case .copy:
      let destination = try destinationURL(of: step, volume: volume)
      let destinationDigest = try digest(of: destination, stepId: step.id)
      if destinationDigest == step.sha256 { return .done(resultPath: relative(destination)) }
      let temp = tempURL(destination: destination, plan: plan)
      let tempDigest = try digest(of: temp, stepId: step.id)
      if destinationDigest == nil, sourceDigest == step.sha256 {
        return tempDigest == nil ? .notDone : .partial(tempPath: relative(temp))
      }
      var found: [String: String?] = [
        relative(source): sourceDigest, relative(destination): destinationDigest,
      ]
      if let tempDigest { found[relative(temp)] = .some(tempDigest) }
      return .anomaly(found: found)

    case .trash:
      if sourceDigest == step.sha256 { return .notDone }
      let entries = try trashEntries(withDigest: step.sha256, stepId: step.id, volume: volume)
      if sourceDigest == nil, entries.count == 1 {
        return .done(resultPath: relative(entries[0]))
      }
      var found: [String: String?] = [relative(source): sourceDigest]
      for entry in entries { found[relative(entry)] = .some(step.sha256) }
      return .anomaly(found: found)
    }
  }

  /// Voci di primo livello del Cestino del volume (`.Trashes/<uid>`) che sono file regolari con il
  /// digest dato, ordinate per nome. Un Cestino che non esiste ancora non ha voci.
  public static func trashEntries(
    withDigest sha256: String, stepId: String, volume: WorkVolume
  ) throws -> [URL] {
    let trash = volume.trashDirectory
    let trashPath = trash.fileSystemPath
    var info = stat()
    guard lstat(trashPath, &info) == 0 else {
      let code = errno
      if code == ENOENT || code == ENOTDIR { return [] }
      throw StepFailure(stepId: stepId, syscall: "lstat", errno: code, path: trashPath)
    }
    let names: [String]
    do {
      names = try FileManager.default.contentsOfDirectory(atPath: trashPath)
    } catch {
      throw StepFailure(
        stepId: stepId, syscall: "contentsOfDirectory", path: trashPath, error: error)
    }
    var matches: [URL] = []
    for name in names.sorted() {
      let entry = trash.appending(path: name, directoryHint: .notDirectory)
      if try digest(of: entry, stepId: stepId) == sha256 { matches.append(entry) }
    }
    return matches
  }

  // MARK: - Esecuzione

  /// Esegue il passo, se non è già fatto, e restituisce il percorso del risultato relativo al punto
  /// di montaggio: la destinazione, o per `trash` il `resultingItemURL` del Cestino.
  ///
  /// - `rename`, `move`: `renamex_np(sorgente, destinazione, RENAME_EXCL)`.
  /// - `copy`: se la copia era interrotta, prima `unlink` del temporaneo; poi
  ///   `copyfile(sorgente, temporaneo, COPYFILE_ALL | COPYFILE_EXCL)`, `afterTempWritten()` e
  ///   `renamex_np(temporaneo, destinazione, RENAME_EXCL)`.
  /// - `trash`: verifica che il volume della sorgente sia `plan.volumeUUID`, altrimenti rifiuta
  ///   senza agire; poi `FileManager.trashItem`.
  ///
  /// - Parameter afterTempWritten: gancio fra la scrittura del temporaneo di copia e la sua
  ///   pubblicazione (punti `Sxx-m`). Un errore che lancia si propaga invariato, senza alcuna
  ///   pulizia: il disco resta come lo lascerebbe un arresto in quel punto.
  /// - Throws: `StepFailure` per ogni chiamata fallita o rifiuto.
  @discardableResult
  public static func execute(
    _ step: PlannedStep, plan: BatchPlan, volume: WorkVolume,
    afterTempWritten: () throws -> Void = {}
  ) throws -> String {
    let observation = try observe(step, plan: plan, volume: volume)
    if case .done(let resultPath) = observation { return resultPath }
    let source = volume.batchURL(step.source)
    try refuseForeignContent(at: source, in: observation, step: step, volume: volume)

    switch step.kind {
    case .rename, .move:
      let destination = try destinationURL(of: step, volume: volume)
      try rename(source, to: destination, stepId: step.id)
      return volume.volumeRelativePath(of: destination)

    case .copy:
      let destination = try destinationURL(of: step, volume: volume)
      let temp = tempURL(destination: destination, plan: plan)
      if case .partial = observation { try unlinkTemp(temp, stepId: step.id) }
      guard
        copyfile(
          source.fileSystemPath, temp.fileSystemPath, nil,
          copyfile_flags_t(COPYFILE_ALL | COPYFILE_EXCL)) == 0
      else {
        throw StepFailure(
          stepId: step.id, syscall: "copyfile", errno: errno, path: source.fileSystemPath)
      }
      try afterTempWritten()
      try rename(temp, to: destination, stepId: step.id)
      return volume.volumeRelativePath(of: destination)

    case .trash:
      try requirePlanVolume(source, plan: plan, step: step)
      return volume.volumeRelativePath(of: try moveToTrash(source, stepId: step.id))
    }
  }

  // MARK: - Compensazione

  /// Riporta il passo all'origine, se non è già non fatto, e restituisce il percorso relativo al
  /// punto di montaggio che la compensazione ha prodotto: l'origine del file, o per `copy` la voce
  /// del Cestino in cui è finita la copia (l'origine se non c'era nulla da spostare).
  ///
  /// - `rename`, `move`: `renamex_np(destinazione, sorgente, RENAME_EXCL)`.
  /// - `copy`: `trashItem` della copia, mai `unlink` (NFR-A1), dopo la stessa verifica del volume
  ///   del passo `trash`; una copia interrotta perde solo il temporaneo, con `unlink`.
  /// - `trash`: `renamex_np(<voce del Cestino trovata per digest>, sorgente, RENAME_EXCL)`.
  ///
  /// - Throws: `StepFailure` per ogni chiamata fallita o rifiuto.
  @discardableResult
  public static func compensate(
    _ step: PlannedStep, plan: BatchPlan, volume: WorkVolume
  ) throws -> String {
    let observation = try observe(step, plan: plan, volume: volume)
    let source = volume.batchURL(step.source)
    let sourcePath = volume.volumeRelativePath(of: source)
    if observation == .notDone { return sourcePath }

    switch step.kind {
    case .rename, .move:
      let destination = try destinationURL(of: step, volume: volume)
      try refuseForeignContent(at: destination, in: observation, step: step, volume: volume)
      try rename(destination, to: source, stepId: step.id)
      return sourcePath

    case .copy:
      if case .partial(let tempPath) = observation {
        try unlinkTemp(volume.volumeURL(tempPath), stepId: step.id)
        return sourcePath
      }
      let destination = try destinationURL(of: step, volume: volume)
      try refuseForeignContent(at: destination, in: observation, step: step, volume: volume)
      try requirePlanVolume(destination, plan: plan, step: step)
      return volume.volumeRelativePath(of: try moveToTrash(destination, stepId: step.id))

    case .trash:
      let entry: URL
      switch observation {
      case .done(let entryPath):
        entry = volume.volumeURL(entryPath)
      case .anomaly(let found):
        // Una sola voce con il digest e l'origine occupata: si tenta, e `RENAME_EXCL` fallisce.
        let entries = found.keys.filter { $0 != sourcePath }.sorted()
        guard entries.count == 1 else {
          throw StepFailure(
            stepId: step.id, syscall: StepFailure.trashLookup, errno: nil,
            path: volume.trashDirectory.fileSystemPath)
        }
        entry = volume.volumeURL(entries[0])
      case .notDone, .partial:
        return sourcePath
      }
      try rename(entry, to: source, stepId: step.id)
      return sourcePath
    }
  }

  /// Compensa la preparazione del lotto: `rmdir` delle sole cartelle di `created` (relative a
  /// `lotto/`, quelle che il record `prepare` dice create dal lotto), dalla più interna.
  ///
  /// Una cartella non vuota resta dov'è. Una cartella già assente conta come rimossa, purché la
  /// cartella che la conteneva esista: se manca anche quella (volume espulso) l'`ENOENT` è un
  /// fallimento.
  ///
  /// - Returns: le cartelle mantenute perché non vuote, nell'ordine di `created`.
  /// - Throws: `StepFailure` con `stepId` `Steps.prepareStepId`.
  @discardableResult
  public static func compensatePrepare(created: [String], volume: WorkVolume) throws -> [String] {
    var kept: [String] = []
    for directory in created.reversed() {
      let url = volume.batchURL(directory)
      let path = url.fileSystemPath
      if rmdir(path) == 0 { continue }
      let code = errno
      switch code {
      case ENOTEMPTY, EEXIST:
        kept.insert(directory, at: 0)
      case ENOENT:
        var info = stat()
        guard lstat(url.deletingLastPathComponent().fileSystemPath, &info) == 0 else {
          throw StepFailure(stepId: prepareStepId, syscall: "rmdir", errno: code, path: path)
        }
      default:
        throw StepFailure(stepId: prepareStepId, syscall: "rmdir", errno: code, path: path)
      }
    }
    return kept
  }

  // MARK: - Supporto

  /// SHA-256 del file in `url`, `nil` se la posizione è vuota; `nonRegularDigest` se è occupata da
  /// una voce che non è un file regolare. Letto con `open`/`read`, così che un fallimento porti il
  /// suo errno.
  static func digest(of url: URL, stepId: String) throws -> String? {
    let path = url.fileSystemPath
    var info = stat()
    guard lstat(path, &info) == 0 else {
      let code = errno
      if code == ENOENT || code == ENOTDIR { return nil }
      throw StepFailure(stepId: stepId, syscall: "lstat", errno: code, path: path)
    }
    guard info.st_mode & S_IFMT == S_IFREG else { return nonRegularDigest }

    let descriptor = open(path, O_RDONLY)
    guard descriptor >= 0 else {
      throw StepFailure(stepId: stepId, syscall: "open", errno: errno, path: path)
    }
    var content = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    var readFailure: Int32?
    while true {
      let count = read(descriptor, &buffer, buffer.count)
      if count < 0 {
        readFailure = errno
        break
      }
      if count == 0 { break }
      content.append(contentsOf: buffer[0..<count])
    }
    let closed = close(descriptor)
    let closeErrno = errno
    if let readFailure {
      throw StepFailure(stepId: stepId, syscall: "read", errno: readFailure, path: path)
    }
    guard closed == 0 else {
      throw StepFailure(stepId: stepId, syscall: "close", errno: closeErrno, path: path)
    }
    return Fixtures.sha256Hex(of: content)
  }

  /// Destinazione del passo; un passo che ne ha bisogno e non ce l'ha è un rifiuto.
  private static func destinationURL(of step: PlannedStep, volume: WorkVolume) throws -> URL {
    guard let destination = step.destination, step.kind != .trash else {
      throw StepFailure(
        stepId: step.id, syscall: StepFailure.planCheck, errno: nil,
        path: volume.batchURL(step.source).fileSystemPath)
    }
    return volume.batchURL(destination)
  }

  /// Rifiuta di agire su `url` se, in uno stato anomalo, vi si trova un file con un digest diverso
  /// da quello del piano: il passo non sposta, non copia e non cestina mai un file estraneo.
  private static func refuseForeignContent(
    at url: URL, in observation: StepObservation, step: PlannedStep, volume: WorkVolume
  ) throws {
    guard case .anomaly(let found) = observation,
      let digest = found[volume.volumeRelativePath(of: url)] ?? nil,
      digest != step.sha256
    else { return }
    throw StepFailure(
      stepId: step.id, syscall: StepFailure.digestCheck, errno: nil, path: url.fileSystemPath)
  }

  /// Regola di sicurezza del Cestino: `url` deve stare sul volume registrato nel piano, così il
  /// Cestino dell'utente non viene mai toccato.
  private static func requirePlanVolume(_ url: URL, plan: BatchPlan, step: PlannedStep) throws {
    let volumeUUID: String
    do {
      volumeUUID = try WorkVolume.volumeUUID(of: url)
    } catch {
      throw StepFailure(
        stepId: step.id, syscall: "volumeUUID", path: url.fileSystemPath, error: error)
    }
    guard volumeUUID == plan.volumeUUID else {
      throw StepFailure(
        stepId: step.id, syscall: StepFailure.volumeCheck, errno: nil, path: url.fileSystemPath)
    }
  }

  /// `renamex_np(from, to, RENAME_EXCL)`: non sovrascrive mai.
  private static func rename(_ from: URL, to: URL, stepId: String) throws {
    guard renamex_np(from.fileSystemPath, to.fileSystemPath, UInt32(RENAME_EXCL)) == 0 else {
      throw StepFailure(
        stepId: stepId, syscall: "renamex_np", errno: errno, path: from.fileSystemPath)
    }
  }

  /// `FileManager.trashItem`, unico punto del banco che usa il Cestino.
  private static func moveToTrash(_ url: URL, stepId: String) throws -> URL {
    var result: NSURL?
    do {
      try FileManager.default.trashItem(at: url, resultingItemURL: &result)
    } catch {
      throw StepFailure(
        stepId: stepId, syscall: "trashItem", path: url.fileSystemPath, error: error)
    }
    guard let result else {
      throw StepFailure(
        stepId: stepId, syscall: StepFailure.trashLookup, errno: nil, path: url.fileSystemPath)
    }
    return result as URL
  }

  /// `unlink` di un file temporaneo di copia; uno già assente conta come rimosso.
  private static func unlinkTemp(_ url: URL, stepId: String) throws {
    guard unlink(url.fileSystemPath) == 0 else {
      let code = errno
      if code == ENOENT { return }
      throw StepFailure(stepId: stepId, syscall: "unlink", errno: code, path: url.fileSystemPath)
    }
  }
}
