import Darwin
import Foundation

/// Strategia di recupero chiesta dall'utente: riprendere in avanti o compensare all'indietro.
public enum RecoveryStrategy: String, Codable, Sendable, CaseIterable {
  case resume
  case compensate

  /// Direzione dei passi corrispondente alla strategia.
  public var direction: StepDirection {
    switch self {
    case .resume: .forward
    case .compensate: .compensate
    }
  }
}

/// Errori dell'applicazione o della rimozione di una perturbazione.
public enum PerturbationError: Error, Equatable, CustomStringConvertible, LocalizedError {
  /// Una perturbazione è già applicata: va rimossa prima di applicarne un'altra, altrimenti la
  /// rimozione non saprebbe più cosa annullare.
  case alreadyActive(ErrorClass)
  /// Una chiamata di sistema è fallita.
  case systemCallFailed(call: String, path: String, errno: Int32)
  /// La rimozione non può riportare il disco allo stato precedente senza scegliere al posto
  /// dell'utente: il percorso e il motivo dicono perché.
  case cannotUndo(path: String, reason: String)

  public var description: String {
    switch self {
    case .alreadyActive(let errorClass):
      "perturbazione \(errorClass.rawValue) già applicata: esegui prima `crashbench unperturb`"
    case .systemCallFailed(let call, let path, let code):
      "\(call) fallita su \(path): \(String(cString: strerror(code))) (errno \(code))"
    case .cannotUndo(let path, let reason):
      "impossibile annullare la perturbazione su \(path): \(reason)"
    }
  }

  public var errorDescription: String? { description }
}

/// Bersaglio di una perturbazione secondo la regola fissa di `Perturbations.target`.
public enum PerturbationTarget: Equatable, Sendable {
  /// Il passo su cui la classe agisce.
  case step(PlannedStep)
  /// La classe non ha un file bersaglio (`G-volume-missing`, `G-folder-readonly`).
  case noFileTarget
  /// Nessun passo a cui la classe si applica: non si applica nulla.
  case nonApplicabile(String)
}

/// Una modifica applicata da una perturbazione, con ciò che serve ad annullarla. I percorsi sono
/// relativi al punto di montaggio, così restano validi dopo un nuovo montaggio.
public enum PerturbationChange: Codable, Sendable, Equatable {
  /// `rename(from, to)`; si annulla con il `rename` di ritorno.
  case moved(from: String, to: String)
  /// File estraneo creato in `path`; si annulla spostandolo in `quarantinePath`.
  case created(path: String, quarantinePath: String)
  /// `UF_IMMUTABLE` aggiunto a `path`; si annulla riportando i flag a `originalFlags`.
  case locked(path: String, originalFlags: UInt32)
  /// Un byte aggiunto in coda a `path`; si annulla con `ftruncate` alla dimensione originale e
  /// `utimensat` alla `mtime` originale. L'inode resta lo stesso.
  case appended(path: String, originalSize: Int64, mtimeSeconds: Int, mtimeNanoseconds: Int)
  /// Volume espulso; si annulla rimontandolo.
  case ejected
  /// Cartella portata a `0555`; si annulla riportandola a `originalMode`.
  case madeReadOnly(path: String, originalMode: UInt16)
  /// File di riempimento che esaurisce lo spazio del volume; si annulla con `unlink`.
  case filled(path: String)
}

/// Esito di `Perturbations.apply`, e stato salvato in `<data>/state/perturbation.json` finché la
/// perturbazione non viene rimossa.
public struct PerturbationRecord: Codable, Sendable, Equatable {
  public let errorClass: ErrorClass
  public let strategy: RecoveryStrategy
  /// Passo bersaglio; `nil` per le classi senza file bersaglio e per le non applicabili.
  public let target: String?
  /// Motivo della non applicabilità; `nil` se la perturbazione è stata applicata.
  public let notApplicableReason: String?
  /// Modifiche nell'ordine di applicazione; la rimozione le annulla in ordine inverso.
  public let changes: [PerturbationChange]

  public init(
    errorClass: ErrorClass, strategy: RecoveryStrategy, target: String?,
    notApplicableReason: String?, changes: [PerturbationChange]
  ) {
    self.errorClass = errorClass
    self.strategy = strategy
    self.target = target
    self.notApplicableReason = notApplicableReason
    self.changes = changes
  }

  /// Una perturbazione non applicata, con il motivo.
  public static func notApplicable(
    _ errorClass: ErrorClass, strategy: RecoveryStrategy, reason: String
  ) -> PerturbationRecord {
    PerturbationRecord(
      errorClass: errorClass, strategy: strategy, target: nil, notApplicableReason: reason,
      changes: [])
  }

  public var isApplied: Bool { notApplicableReason == nil }

  /// La riga stampata da `crashbench perturb`:
  /// `PERTURBAZIONE <classe> bersaglio=<stepId>|nessuno ambito=<locale|sistemico>`, oppure
  /// `PERTURBAZIONE <classe> NON-APPLICABILE motivo=<…>`.
  public var line: String {
    if let notApplicableReason {
      return "PERTURBAZIONE \(errorClass.rawValue) NON-APPLICABILE motivo=\(notApplicableReason)"
    }
    return
      "PERTURBAZIONE \(errorClass.rawValue) bersaglio=\(target ?? "nessuno") "
      + "ambito=\(errorClass.scope.rawValue)"
  }
}

/// Le otto perturbazioni del cancello: ciascuna produce sul volume di lavoro, fra l'arresto e il
/// recupero, la condizione di una classe di errore, e si rimuove con un comando.
///
/// - `L-missing`: `rename` del file bersaglio in `quarantine`; rimozione: `rename` di ritorno.
/// - `L-locked`: `chflags(UF_IMMUTABLE)` sul file bersaglio; rimozione: i flag originali (`0`).
/// - `L-collision`: un file estraneo con contenuto `"estraneo"` nella posizione di arrivo;
///   rimozione: `rename` del file estraneo in `quarantine`.
/// - `L-modified`: salva dimensione e `mtime`, poi aggiunge un byte in coda; rimozione:
///   `ftruncate` alla dimensione originale e `utimensat` alla `mtime` originale, stesso inode.
/// - `L-trash-emptied`: `rename` della voce del Cestino con il digest in `quarantine`; rimozione:
///   `rename` di ritorno con lo stesso nome.
/// - `G-volume-missing`: `eject` del volume; rimozione: `attach`.
/// - `G-folder-readonly`: `chmod 0555` su `batchRoot` e sulle cartelle di destinazione esistenti;
///   rimozione: il modo originale (`0755`).
/// - `G-space-exhausted`: `<mnt>/.riempimento` scritto a blocchi da 1 MiB, dimezzati a ogni errore
///   fino a 1 byte, poi `fsync`; rimozione: `unlink`.
///
/// Lo stato sta in `<data>/state/perturbation.json`, sul volume ospite, ed è scritto **prima** di
/// toccare il disco: `remove` sa cosa annullare anche da un altro processo, e anche dopo
/// un'applicazione interrotta a metà. Ogni annullamento tollera una modifica mai avvenuta.
public enum Perturbations {
  /// Nome del file di stato nella directory di stato.
  public static let stateFileName = "perturbation.json"
  /// Nome del file di riempimento alla radice del volume di lavoro.
  public static let fillerName = ".riempimento"
  /// Contenuto del file estraneo di `L-collision`.
  public static let foreignContent = "estraneo"
  /// Dimensione iniziale dei blocchi di riempimento.
  static let fillBlockSize = 1 << 20

  /// Motivi di non applicabilità, una parola composta senza spazi.
  public enum Reason {
    public static let planNotInLog = "piano-assente-dal-log"
    public static let copiesOnResumeOnly = "solo-copie-in-ripresa"
    public static let executedTrashCompensationOnly = "solo-compensazione-di-trash-eseguito"
    public static let noPendingStep = "nessun-passo-non-eseguito-applicabile"
    public static let noExecutedStep = "nessun-passo-eseguito-applicabile"
  }

  /// `<data>/state/perturbation.json`.
  public static func stateURL(in volume: WorkVolume) -> URL {
    volume.stateDirectory.appending(path: stateFileName, directoryHint: .notDirectory)
  }

  /// `<mnt>/.riempimento`.
  public static func fillerURL(in volume: WorkVolume) -> URL {
    volume.mountPoint.appending(path: fillerName, directoryHint: .notDirectory)
  }

  /// La perturbazione applicata e non ancora rimossa, se c'è.
  public static func active(volume: WorkVolume) throws -> PerturbationRecord? {
    let url = stateURL(in: volume)
    guard FileManager.default.fileExists(atPath: url.fileSystemPath) else { return nil }
    return try JSONDecoder().decode(PerturbationRecord.self, from: Data(contentsOf: url))
  }

  /// Il piano registrato nel log (il primo record `plan`), se c'è. Un record troncato non è un
  /// piano; il log non viene riparato: la riparazione è del recupero.
  public static func plan(in log: IntentLog) throws -> BatchPlan? {
    for record in try log.read().records {
      if case .plan(let plan) = record { return plan }
    }
    return nil
  }

  // MARK: - Regola del bersaglio

  /// Sceglie il bersaglio della classe con una regola fissa, sullo stato dei passi osservato dal
  /// disco con `Steps.observe`:
  ///
  /// - in ripresa, il primo passo **non eseguito** (`.notDone` o `.partial`), in ordine di piano, a
  ///   cui la classe si applica;
  /// - in compensazione, il primo passo **eseguito** (`.done`), in ordine inverso.
  ///
  /// Restrizioni per classe:
  /// - `G-volume-missing` e `G-folder-readonly` non hanno un file bersaglio: `.noFileTarget`;
  /// - `G-space-exhausted` si applica solo ai passi `copy` in ripresa;
  /// - `L-locked` si applica solo a `rename`, `move` e `trash`;
  /// - `L-trash-emptied` si applica solo alla compensazione di un `trash` eseguito;
  /// - `L-collision` esige una posizione di arrivo libera nel lotto, in una cartella esistente: la
  ///   destinazione in ripresa (un `trash` non ne ha), l'origine in compensazione (quella di una
  ///   copia è occupata dalla sorgente).
  ///
  /// Il log deve contenere il piano: una perturbazione serve a un recupero, che conosce il lotto
  /// solo dal log. Senza bersaglio la regola restituisce `.nonApplicabile(motivo)`.
  public static func target(
    _ errorClass: ErrorClass, strategy: RecoveryStrategy, plan: BatchPlan, log: IntentLog,
    volume: WorkVolume
  ) throws -> PerturbationTarget {
    guard try log.read().records.contains(.plan(plan)) else {
      return .nonApplicabile(Reason.planNotInLog)
    }
    switch errorClass {
    case .volumeMissing, .folderReadonly:
      return .noFileTarget
    case .spaceExhausted where strategy != .resume:
      return .nonApplicabile(Reason.copiesOnResumeOnly)
    case .trashEmptied where strategy != .compensate:
      return .nonApplicabile(Reason.executedTrashCompensationOnly)
    default:
      break
    }

    let ordered = strategy == .resume ? plan.steps : plan.steps.reversed()
    for step in ordered {
      let observation = try Steps.observe(step, plan: plan, volume: volume)
      let candidate =
        switch (strategy, observation) {
        case (.resume, .notDone), (.resume, .partial), (.compensate, .done): true
        default: false
        }
      guard candidate,
        try applies(errorClass, to: step, strategy: strategy, volume: volume)
      else { continue }
      return .step(step)
    }
    return .nonApplicabile(strategy == .resume ? Reason.noPendingStep : Reason.noExecutedStep)
  }

  /// Vero se la classe si applica al passo candidato.
  private static func applies(
    _ errorClass: ErrorClass, to step: PlannedStep, strategy: RecoveryStrategy,
    volume: WorkVolume
  ) throws -> Bool {
    switch errorClass {
    case .volumeMissing, .folderReadonly: true
    case .spaceExhausted: step.kind == .copy
    case .locked: step.kind != .copy
    case .trashEmptied: step.kind == .trash
    case .missing, .modified: true
    case .collision: try arrivalURL(of: step, strategy: strategy, volume: volume) != nil
    }
  }

  /// Posizione di arrivo del passo nella direzione della strategia, se è libera e la sua cartella
  /// esiste: la destinazione in ripresa, l'origine in compensazione.
  private static func arrivalURL(
    of step: PlannedStep, strategy: RecoveryStrategy, volume: WorkVolume
  ) throws -> URL? {
    // Un `trash` non ha destinazione: in ripresa non ha arrivo nel lotto.
    guard let relative = strategy == .resume ? step.destination : step.source else { return nil }
    let arrival = volume.batchURL(relative)
    guard try status(arrival.fileSystemPath) == nil,
      try status(arrival.deletingLastPathComponent().fileSystemPath) != nil
    else { return nil }
    return arrival
  }

  /// Il file su cui agiscono `L-missing`, `L-locked`, `L-modified` e `L-trash-emptied`: l'origine
  /// di un passo non eseguito, il risultato (destinazione o voce del Cestino) di uno eseguito.
  private static func targetFile(
    of step: PlannedStep, plan: BatchPlan, volume: WorkVolume
  ) throws -> URL {
    switch try Steps.observe(step, plan: plan, volume: volume) {
    case .done(let resultPath): volume.volumeURL(resultPath)
    default: volume.batchURL(step.source)
    }
  }

  // MARK: - Applicazione

  /// Applica la perturbazione della classe al bersaglio scelto da `target`.
  ///
  /// Salva in `perturbation.json` le modifiche, con ciò che serve ad annullarle, **prima** di
  /// eseguirle. Senza bersaglio non applica nulla, non salva nulla e restituisce un record non
  /// applicato con il motivo.
  ///
  /// - Throws: `PerturbationError.alreadyActive` se una perturbazione è già applicata; errori di
  ///   sistema dell'applicazione. Un'applicazione fallita a metà resta in `perturbation.json`, e
  ///   `remove` la annulla.
  public static func apply(
    _ errorClass: ErrorClass, strategy: RecoveryStrategy, plan: BatchPlan, log: IntentLog,
    volume: WorkVolume
  ) throws -> PerturbationRecord {
    if let active = try active(volume: volume) {
      throw PerturbationError.alreadyActive(active.errorClass)
    }
    let step: PlannedStep?
    switch try target(errorClass, strategy: strategy, plan: plan, log: log, volume: volume) {
    case .nonApplicabile(let reason):
      return .notApplicable(errorClass, strategy: strategy, reason: reason)
    case .noFileTarget:
      step = nil
    case .step(let targetStep):
      step = targetStep
    }

    let changes = try plannedChanges(
      errorClass, step: step, strategy: strategy, plan: plan, volume: volume)
    let record = PerturbationRecord(
      errorClass: errorClass, strategy: strategy, target: step?.id, notApplicableReason: nil,
      changes: changes)
    try save(record, volume: volume)
    for change in changes { try perform(change, volume: volume) }
    return record
  }

  /// Le modifiche della classe sul bersaglio, con lo stato originale da ripristinare.
  private static func plannedChanges(
    _ errorClass: ErrorClass, step: PlannedStep?, strategy: RecoveryStrategy, plan: BatchPlan,
    volume: WorkVolume
  ) throws -> [PerturbationChange] {
    let relative = volume.volumeRelativePath(of:)
    switch errorClass {
    case .volumeMissing:
      return [.ejected]

    case .folderReadonly:
      var folders = [volume.batchRoot]
      for destination in plan.steps.compactMap(\.destination) {
        let folder = volume.batchURL(destination).deletingLastPathComponent()
        if !folders.contains(where: { $0.fileSystemPath == folder.fileSystemPath }) {
          folders.append(folder)
        }
      }
      var changes: [PerturbationChange] = []
      for folder in folders {
        guard let info = try status(folder.fileSystemPath) else { continue }
        changes.append(.madeReadOnly(path: relative(folder), originalMode: info.st_mode & 0o7777))
      }
      return changes

    case .spaceExhausted:
      return [.filled(path: relative(fillerURL(in: volume)))]

    case .missing, .trashEmptied, .locked, .modified, .collision:
      guard let step else { return [] }
      if errorClass == .collision {
        guard let arrival = try arrivalURL(of: step, strategy: strategy, volume: volume) else {
          return []
        }
        let quarantined = volume.quarantine.appending(
          path: "\(foreignContent)-\(UUID().uuidString)-\(arrival.lastPathComponent)",
          directoryHint: .notDirectory)
        return [.created(path: relative(arrival), quarantinePath: relative(quarantined))]
      }
      let file = try targetFile(of: step, plan: plan, volume: volume)
      guard let info = try status(file.fileSystemPath) else {
        throw PerturbationError.systemCallFailed(
          call: "lstat", path: file.fileSystemPath, errno: ENOENT)
      }
      switch errorClass {
      case .locked:
        return [.locked(path: relative(file), originalFlags: info.st_flags)]
      case .modified:
        return [
          .appended(
            path: relative(file), originalSize: Int64(info.st_size),
            mtimeSeconds: info.st_mtimespec.tv_sec, mtimeNanoseconds: info.st_mtimespec.tv_nsec)
        ]
      default:
        // `L-missing` e `L-trash-emptied`: in quarantena con lo stesso nome, che il ritorno
        // ripristina (nel Cestino il nome porta il suffisso orario di una collisione).
        let quarantined = volume.quarantine.appending(
          path: file.lastPathComponent, directoryHint: .notDirectory)
        return [.moved(from: relative(file), to: relative(quarantined))]
      }
    }
  }

  /// Esegue una modifica.
  private static func perform(_ change: PerturbationChange, volume: WorkVolume) throws {
    switch change {
    case .moved(let from, let to):
      try ensureQuarantine(volume)
      try rename(volume.volumeURL(from).fileSystemPath, to: volume.volumeURL(to).fileSystemPath)

    case .created(let path, _):
      let fullPath = volume.volumeURL(path).fileSystemPath
      let descriptor = open(fullPath, O_WRONLY | O_CREAT | O_EXCL, 0o644)
      guard descriptor >= 0 else { throw systemCallFailed("open", fullPath) }
      try writeAll(Array(foreignContent.utf8), to: descriptor, path: fullPath)

    case .locked(let path, let originalFlags):
      let fullPath = volume.volumeURL(path).fileSystemPath
      guard chflags(fullPath, originalFlags | UInt32(UF_IMMUTABLE)) == 0 else {
        throw systemCallFailed("chflags", fullPath)
      }

    case .appended(let path, _, _, _):
      let fullPath = volume.volumeURL(path).fileSystemPath
      let descriptor = open(fullPath, O_WRONLY | O_APPEND)
      guard descriptor >= 0 else { throw systemCallFailed("open", fullPath) }
      try writeAll([UInt8(ascii: "+")], to: descriptor, path: fullPath)

    case .ejected:
      try volume.eject()

    case .madeReadOnly(let path, _):
      let fullPath = volume.volumeURL(path).fileSystemPath
      guard chmod(fullPath, 0o555) == 0 else { throw systemCallFailed("chmod", fullPath) }

    case .filled(let path):
      try fill(volume.volumeURL(path).fileSystemPath)
    }
  }

  /// Riempie il volume: blocchi da 1 MiB; a ogni errore di spazio il blocco si dimezza, fino a
  /// 1 byte; poi `fsync`. Una scrittura parziale non è un errore: si riprova con lo stesso blocco.
  private static func fill(_ path: String) throws {
    let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
    guard descriptor >= 0 else { throw systemCallFailed("open", path) }
    let buffer = [UInt8](repeating: 0, count: fillBlockSize)
    var block = fillBlockSize
    var failure: PerturbationError?
    while true {
      let written = buffer.withUnsafeBytes { write(descriptor, $0.baseAddress, block) }
      if written > 0 { continue }
      let code = written < 0 ? errno : ENOSPC
      if code == EINTR { continue }
      guard code == ENOSPC || code == EDQUOT else {
        failure = .systemCallFailed(call: "write", path: path, errno: code)
        break
      }
      if block == 1 { break }
      block /= 2
    }
    if failure == nil, fsync(descriptor) != 0 {
      failure = .systemCallFailed(call: "fsync", path: path, errno: errno)
    }
    let closed = close(descriptor)
    let closeErrno = errno
    if let failure { throw failure }
    guard closed == 0 else {
      throw PerturbationError.systemCallFailed(call: "close", path: path, errno: closeErrno)
    }
  }

  // MARK: - Rimozione

  /// Rimuove la perturbazione applicata, annullandone le modifiche in ordine inverso, poi cancella
  /// `perturbation.json`. Idempotente: senza perturbazione applicata non fa nulla e restituisce
  /// `nil`. Con una perturbazione applicata e il volume smontato, prima lo rimonta.
  ///
  /// Il volume torna all'istantanea precedente all'applicazione, salvo la `mtime` delle directory
  /// toccate da un `rename` o da una creazione.
  ///
  /// - Throws: se un annullamento fallisce `perturbation.json` resta, e `remove` si può ripetere.
  @discardableResult
  public static func remove(volume: WorkVolume) throws -> PerturbationRecord? {
    guard let record = try active(volume: volume) else { return nil }
    if !volume.isMounted { try volume.attach() }
    for change in record.changes.reversed() { try undo(change, volume: volume) }
    try FileManager.default.removeItem(at: stateURL(in: volume))
    return record
  }

  /// La riga stampata da `crashbench unperturb`: `RIMOZIONE <classe> bersaglio=<stepId>|nessuno`,
  /// oppure `RIMOZIONE nessuna` se non c'era nulla da rimuovere.
  public static func removalLine(_ removed: PerturbationRecord?) -> String {
    guard let removed else { return "RIMOZIONE nessuna" }
    return "RIMOZIONE \(removed.errorClass.rawValue) bersaglio=\(removed.target ?? "nessuno")"
  }

  /// Annulla una modifica; una modifica mai eseguita, o già annullata, non è un errore.
  private static func undo(_ change: PerturbationChange, volume: WorkVolume) throws {
    switch change {
    case .moved(let from, let to):
      let original = volume.volumeURL(from).fileSystemPath
      let moved = volume.volumeURL(to).fileSystemPath
      switch (try status(original) != nil, try status(moved) != nil) {
      case (false, true):
        // Fra l'applicazione e la rimozione, la compensazione del recupero può aver rimosso con
        // `rmdir`, perché vuota, la cartella creata dal lotto che conteneva il file (rilevato
        // dalla matrice: `S06-b/compensate/L-missing` e `selezione/`). Il `rename` di ritorno
        // fallirebbe con `ENOENT`: la cartella si ricrea, come la crea la preparazione del lotto.
        try ensureParentDirectory(of: original)
        try rename(moved, to: original)
      case (true, false): break
      case (true, true):
        throw PerturbationError.cannotUndo(
          path: original, reason: "la posizione originale è occupata e il file è in \(moved)")
      case (false, false):
        throw PerturbationError.cannotUndo(
          path: original, reason: "il file non è né nella posizione originale né in \(moved)")
      }

    case .created(let path, let quarantinePath):
      let fullPath = volume.volumeURL(path).fileSystemPath
      guard try status(fullPath) != nil else { return }
      guard
        try Steps.digest(of: URL(filePath: fullPath), stepId: "perturbazione")
          == Fixtures.sha256Hex(of: Data(foreignContent.utf8))
      else {
        throw PerturbationError.cannotUndo(
          path: fullPath, reason: "il file non è più quello estraneo creato dalla perturbazione")
      }
      try ensureQuarantine(volume)
      try rename(fullPath, to: volume.volumeURL(quarantinePath).fileSystemPath)

    case .locked(let path, let originalFlags):
      let fullPath = volume.volumeURL(path).fileSystemPath
      guard let info = try status(fullPath) else {
        throw PerturbationError.cannotUndo(path: fullPath, reason: "il file bloccato non c'è più")
      }
      if info.st_flags != originalFlags, chflags(fullPath, originalFlags) != 0 {
        throw systemCallFailed("chflags", fullPath)
      }

    case .appended(let path, let originalSize, let mtimeSeconds, let mtimeNanoseconds):
      let fullPath = volume.volumeURL(path).fileSystemPath
      guard let info = try status(fullPath) else {
        throw PerturbationError.cannotUndo(path: fullPath, reason: "il file modificato non c'è più")
      }
      if Int64(info.st_size) != originalSize {
        let descriptor = open(fullPath, O_WRONLY)
        guard descriptor >= 0 else { throw systemCallFailed("open", fullPath) }
        let truncated = ftruncate(descriptor, off_t(originalSize))
        let truncateErrno = errno
        let closed = close(descriptor)
        let closeErrno = errno
        guard truncated == 0 else {
          throw PerturbationError.systemCallFailed(
            call: "ftruncate", path: fullPath, errno: truncateErrno)
        }
        guard closed == 0 else {
          throw PerturbationError.systemCallFailed(call: "close", path: fullPath, errno: closeErrno)
        }
      }
      // Dopo `close`: la `mtime` va ripristinata per ultima.
      let times = [
        timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)),
        timespec(tv_sec: mtimeSeconds, tv_nsec: mtimeNanoseconds),
      ]
      let restored = times.withUnsafeBufferPointer {
        utimensat(AT_FDCWD, fullPath, $0.baseAddress, AT_SYMLINK_NOFOLLOW)
      }
      guard restored == 0 else { throw systemCallFailed("utimensat", fullPath) }

    case .ejected:
      try volume.attach()

    case .madeReadOnly(let path, let originalMode):
      let fullPath = volume.volumeURL(path).fileSystemPath
      guard try status(fullPath) != nil else { return }
      guard chmod(fullPath, mode_t(originalMode)) == 0 else {
        throw systemCallFailed("chmod", fullPath)
      }

    case .filled(let path):
      let fullPath = volume.volumeURL(path).fileSystemPath
      guard unlink(fullPath) == 0 || errno == ENOENT else {
        throw systemCallFailed("unlink", fullPath)
      }
    }
  }

  // MARK: - Supporto

  private static func save(_ record: PerturbationRecord, volume: WorkVolume) throws {
    try FileManager.default.createDirectory(
      at: volume.stateDirectory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(record).write(to: stateURL(in: volume), options: .atomic)
  }

  /// `lstat`, `nil` se il percorso non esiste.
  private static func status(_ path: String) throws -> stat? {
    var info = stat()
    guard lstat(path, &info) == 0 else {
      let code = errno
      if code == ENOENT || code == ENOTDIR { return nil }
      throw PerturbationError.systemCallFailed(call: "lstat", path: path, errno: code)
    }
    return info
  }

  /// `renamex_np(from, to, RENAME_EXCL)`: non sovrascrive mai.
  private static func rename(_ from: String, to: String) throws {
    guard renamex_np(from, to, UInt32(RENAME_EXCL)) == 0 else {
      throw systemCallFailed("renamex_np", from)
    }
  }

  /// Scrive tutti i byte e chiude il descrittore.
  private static func writeAll(_ bytes: [UInt8], to descriptor: Int32, path: String) throws {
    let written = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
    let writeErrno = errno
    let closed = close(descriptor)
    let closeErrno = errno
    guard written == bytes.count else {
      throw PerturbationError.systemCallFailed(
        call: "write", path: path, errno: written < 0 ? writeErrno : EIO)
    }
    guard closed == 0 else {
      throw PerturbationError.systemCallFailed(call: "close", path: path, errno: closeErrno)
    }
  }

  /// Ricrea, se manca, la cartella che conteneva `path`, con il modo `0755` della preparazione.
  private static func ensureParentDirectory(of path: String) throws {
    let parent = URL(filePath: path).deletingLastPathComponent()
    guard try status(parent.fileSystemPath) == nil else { return }
    try FileManager.default.createDirectory(
      at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
  }

  /// La quarantena esiste dopo ogni ripristino della cartella; la si ricrea se manca.
  private static func ensureQuarantine(_ volume: WorkVolume) throws {
    try FileManager.default.createDirectory(
      at: volume.quarantine, withIntermediateDirectories: true)
  }

  private static func systemCallFailed(_ call: String, _ path: String) -> PerturbationError {
    .systemCallFailed(call: call, path: path, errno: errno)
  }
}
