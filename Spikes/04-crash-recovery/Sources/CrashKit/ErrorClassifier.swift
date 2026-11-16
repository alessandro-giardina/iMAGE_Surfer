// Classificazione degli errori di un passo per ambito, non per errno.
//
// Perché l'ordine dei controlli conta. La sonda della baseline ha mostrato che, dopo l'espulsione
// del volume di lavoro, `rename` restituisce `ENOENT`: lo stesso errno di un file scomparso. Il
// punto di montaggio torna a essere una directory vuota del volume ospite, e ogni percorso del
// lotto semplicemente «non esiste». Un classificatore che guardasse prima l'errno, o le posizioni
// dei file sul disco, vedrebbe un file mancante dove manca l'intero volume, e tratterebbe da errore
// locale (passo saltato, lotto che prosegue) un errore sistemico (lotto sospeso in attesa
// dell'utente).
//
// Per questo si verificano prima le condizioni dell'ambiente che rendono ogni altra osservazione
// inaffidabile, e solo dopo le cause locali:
//   1. il volume: la radice del lotto esiste ed è sul volume registrato nel piano;
//   2. la scrittura: la radice del lotto e la cartella di destinazione del passo sono scrivibili;
//   3. lo spazio: l'errno è `ENOSPC` o `EDQUOT`;
//   4. le cause locali, dall'errno e da ciò che si osserva sul disco, nell'ordine di `ErrorClass`.
// La prima condizione che corrisponde decide. Un caso che non ha una regola resta
// `nonClassificato`: non viene mai ricondotto per somiglianza di errno a una classe vicina.

import Darwin
import Foundation

/// Ambito adottato di una classe di errore.
///
/// - `locale`: riguarda un solo file; il passo si salta e il lotto prosegue.
/// - `sistemico`: riguarda il volume o la cartella; il lotto si sospende in attesa dell'utente.
public enum ErrorScope: String, Codable, Sendable, CaseIterable {
  case locale
  case sistemico
}

/// Le otto classi di errore del cancello n°4, nell'ordine in cui il classificatore le verifica.
///
/// Il valore grezzo è il nome della classe nel piano, nel log e in `RESULT.md`.
public enum ErrorClass: String, Codable, Sendable, CaseIterable {
  /// La radice del lotto manca, o sta su un volume diverso da `plan.volumeUUID`.
  case volumeMissing = "G-volume-missing"
  /// `access(W_OK)` fallisce sulla radice del lotto o sulla cartella di destinazione del passo.
  case folderReadonly = "G-folder-readonly"
  /// Errno `ENOSPC` o `EDQUOT`.
  case spaceExhausted = "G-space-exhausted"
  /// `UF_IMMUTABLE` sul file del passo, con errno `EPERM` o errore Cocoa 513 (Cestino).
  case locked = "L-locked"
  /// Errno `EEXIST`, oppure un file estraneo nella posizione di arrivo con la sorgente intatta.
  case collision = "L-collision"
  /// Il file nella posizione attesa ha un digest diverso da quello del piano.
  case modified = "L-modified"
  /// In compensazione di un `trash`, nessuna voce del Cestino del volume ha il digest del piano.
  case trashEmptied = "L-trash-emptied"
  /// Il file non è in nessuna delle posizioni attese: origine, destinazione, Cestino.
  case missing = "L-missing"

  /// Ambito adottato della classe.
  public var scope: ErrorScope {
    switch self {
    case .volumeMissing, .folderReadonly, .spaceExhausted: .sistemico
    case .locked, .collision, .modified, .trashEmptied, .missing: .locale
    }
  }
}

/// Risultato della classificazione di un fallimento o di un'anomalia.
public enum Classification: Equatable, Sendable, CustomStringConvertible {
  case classified(ErrorClass)
  /// Nessuna regola corrisponde; la descrizione nomina il fallimento e le posizioni osservate.
  case nonClassificato(String)

  /// La classe, se il caso è classificato.
  public var errorClass: ErrorClass? {
    if case .classified(let errorClass) = self { errorClass } else { nil }
  }

  /// L'ambito della classe, se il caso è classificato.
  public var scope: ErrorScope? { errorClass?.scope }

  public var description: String {
    switch self {
    case .classified(let errorClass):
      "classe=\(errorClass.rawValue) ambito=\(errorClass.scope.rawValue)"
    case .nonClassificato(let description):
      "non-classificato: \(description)"
    }
  }
}

/// Classificatore degli errori dei passi, per ambito della precondizione violata.
public enum ErrorClassifier {
  /// Prefisso dell'errore Cocoa di uno spostamento nel Cestino rifiutato su un file con
  /// `UF_IMMUTABLE`. Baseline: `NSCocoaErrorDomain 513 / NSOSStatusErrorDomain -5000`, senza
  /// errno.
  static let lockedCocoaError = "NSCocoaErrorDomain 513"

  /// Classifica il fallimento di un passo, o l'anomalia osservata su di esso.
  ///
  /// I controlli seguono l'ordine dichiarato in testa al file, e il primo che corrisponde vince:
  ///
  /// | Classe | Regola |
  /// |---|---|
  /// | `G-volume-missing` | `batchRoot` assente, o il suo UUID di volume ≠ `plan.volumeUUID` |
  /// | `G-folder-readonly` | `access(W_OK)` fallito su `batchRoot` o cartella di destinazione |
  /// | `G-space-exhausted` | errno `ENOSPC` o `EDQUOT` |
  /// | `L-locked` | `UF_IMMUTABLE` sul file della chiamata fallita, ed `EPERM` o Cocoa 513 |
  /// | `L-collision` | `EEXIST`, o file estraneo all'arrivo con il digest del piano alla partenza |
  /// | `L-modified` | file con digest diverso dal piano nella posizione di partenza |
  /// | `L-trash-emptied` | compensazione di un `trash`, nessuna voce del Cestino con il digest |
  /// | `L-missing` | il digest del piano non è in origine, in destinazione né nel Cestino |
  ///
  /// Le posizioni dipendono dalla direzione. In avanti la partenza è l'origine e l'arrivo la
  /// destinazione (un `trash` non ha arrivo nel lotto). In compensazione la partenza è la
  /// destinazione, o per un `trash` le voci del Cestino con il digest, e l'arrivo è l'origine (una
  /// copia compensata va nel Cestino, e non ha arrivo nel lotto).
  ///
  /// - Parameters:
  ///   - failure: il fallimento grezzo del passo, se il passo è stato tentato.
  ///   - observation: lo stato osservato del passo. Se manca e c'è un fallimento, il classificatore
  ///     osserva il disco con `Steps.observe` per le regole che dipendono dalle posizioni.
  ///   - direction: la direzione in cui il passo è stato tentato, o in cui si recupera.
  /// - Returns: `.nonClassificato` anche quando non c'è nulla da classificare: nessun fallimento e
  ///   un'osservazione che non è un'anomalia.
  public static func classify(
    failure: StepFailure?, observation: StepObservation?, step: PlannedStep, plan: BatchPlan,
    volume: WorkVolume, direction: StepDirection
  ) -> Classification {
    if failure == nil {
      guard case .anomaly = observation else {
        return .nonClassificato("\(step.id): nessun fallimento e nessuna anomalia da classificare")
      }
    }

    // 1-3: l'ambiente, prima di qualunque osservazione del disco.
    if volumeIsMissing(plan: plan, volume: volume) { return .classified(.volumeMissing) }
    if readOnlyFolder(for: step, volume: volume) != nil { return .classified(.folderReadonly) }
    if let code = failure?.errno, code == ENOSPC || code == EDQUOT {
      return .classified(.spaceExhausted)
    }

    // 4: cause locali.
    if let failure, isLocked(failure) { return .classified(.locked) }
    if failure?.errno == EEXIST { return .classified(.collision) }

    let observed: StepObservation?
    var observeFailure: String?
    if let observation {
      observed = observation
    } else {
      do {
        observed = try Steps.observe(step, plan: plan, volume: volume)
      } catch {
        observed = nil
        observeFailure = "\(error)"
      }
    }
    if case .anomaly(let found) = observed,
      let errorClass = localClass(found: found, step: step, volume: volume, direction: direction)
    {
      return .classified(errorClass)
    }

    var parts = ["\(step.id) \(direction.rawValue)"]
    if let failure { parts.append(failure.description) }
    if case .anomaly(let found) = observed {
      parts.append("anomalia " + describe(found))
    } else if let observed {
      parts.append("osservazione \(observed)")
    }
    if let observeFailure { parts.append("osservazione fallita: \(observeFailure)") }
    return .nonClassificato(parts.joined(separator: "; "))
  }

  // MARK: - Ambiente

  /// Vero se la radice del lotto manca o non è sul volume del piano. Dopo un'espulsione il punto
  /// di montaggio è una directory vuota dell'ospite: la radice manca.
  static func volumeIsMissing(plan: BatchPlan, volume: WorkVolume) -> Bool {
    var info = stat()
    guard lstat(volume.batchRoot.fileSystemPath, &info) == 0 else { return true }
    return (try? WorkVolume.volumeUUID(of: volume.batchRoot)) != plan.volumeUUID
  }

  /// La prima cartella non scrivibile fra la radice del lotto e la cartella di destinazione del
  /// passo, se c'è. Una cartella che non esiste non è «in sola lettura».
  static func readOnlyFolder(for step: PlannedStep, volume: WorkVolume) -> String? {
    var folders = [volume.batchRoot.fileSystemPath]
    if let destination = step.destination {
      let folder = volume.batchURL(destination).deletingLastPathComponent().fileSystemPath
      if !folders.contains(folder) { folders.append(folder) }
    }
    for folder in folders where access(folder, W_OK) != 0 {
      let code = errno
      if code != ENOENT, code != ENOTDIR { return folder }
    }
    return nil
  }

  // MARK: - Cause locali

  /// `L-locked`: la chiamata fallita con `EPERM`, o con l'errore Cocoa 513 del Cestino, agiva su un
  /// file con `UF_IMMUTABLE`. `StepFailure.path` è il file su cui la chiamata ha agito: l'origine
  /// in avanti, la destinazione o la voce del Cestino in compensazione.
  static func isLocked(_ failure: StepFailure) -> Bool {
    let denied =
      failure.errno == EPERM
      || failure.cocoa.map {
        $0 == lockedCocoaError || $0.hasPrefix(lockedCocoaError + " ")
      } == true
    guard denied else { return false }
    var info = stat()
    guard lstat(failure.path, &info) == 0 else { return false }
    return info.st_flags & UInt32(UF_IMMUTABLE) != 0
  }

  /// Le regole locali che dipendono dalle posizioni di un'anomalia, nell'ordine di `ErrorClass`.
  static func localClass(
    found: [String: String?], step: PlannedStep, volume: WorkVolume, direction: StepDirection
  ) -> ErrorClass? {
    let sourceKey = volume.volumeRelativePath(of: volume.batchURL(step.source))
    let destinationKey = step.destination.map { volume.volumeRelativePath(of: volume.batchURL($0)) }
    // Per un `trash`, `observe` elenca oltre all'origine le sole voci del Cestino con il digest.
    let trashKeys = step.kind == .trash ? found.keys.filter { $0 != sourceKey }.sorted() : []
    func digest(_ key: String?) -> String? { key.flatMap { found[$0] ?? nil } }
    func isForeign(_ digest: String?) -> Bool {
      guard let digest else { return false }
      return digest != step.sha256 && digest != Steps.nonRegularDigest
    }

    let start: [String?]
    let arrival: String?
    switch direction {
    case .forward:
      start = [digest(sourceKey)]
      arrival = step.kind == .trash ? nil : digest(destinationKey)
    case .compensate:
      start = step.kind == .trash ? trashKeys.map { digest($0) } : [digest(destinationKey)]
      arrival = step.kind == .copy ? nil : digest(sourceKey)
    }

    if isForeign(arrival), start.contains(step.sha256) { return .collision }
    if start.contains(where: isForeign) { return .modified }
    if direction == .compensate, step.kind == .trash, trashKeys.isEmpty,
      digest(sourceKey) != step.sha256
    {
      return .trashEmptied
    }
    let expected = [digest(sourceKey), digest(destinationKey)] + trashKeys.map { digest($0) }
    if !expected.contains(step.sha256) { return .missing }
    return nil
  }

  /// `percorso=<digest abbreviato>|assente`, in ordine di percorso.
  static func describe(_ found: [String: String?]) -> String {
    found.keys.sorted().map { key in
      let value = (found[key] ?? nil).map { String($0.prefix(12)) } ?? "assente"
      return "\(key)=\(value)"
    }.joined(separator: " ")
  }
}
