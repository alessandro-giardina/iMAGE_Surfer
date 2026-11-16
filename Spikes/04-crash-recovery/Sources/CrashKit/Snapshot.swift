import Darwin
import Foundation

/// Errori di cattura di un'istantanea: ciascuno nomina il percorso coinvolto.
public enum SnapshotError: Error, Equatable, CustomStringConvertible, LocalizedError {
  /// Una chiamata di sistema è fallita su una voce.
  case systemCallFailed(call: String, path: String, errno: Int32)
  /// La voce non è né un file regolare né una directory.
  case unsupportedEntry(path: String, mode: UInt16)

  public var description: String {
    switch self {
    case .systemCallFailed(let call, let path, let code):
      "\(call) fallita su \(path): \(String(cString: strerror(code))) (errno \(code))"
    case .unsupportedEntry(let path, let mode):
      "voce non supportata dall'istantanea (né file né directory): \(path), "
        + "st_mode \(String(mode, radix: 8))"
    }
  }

  public var errorDescription: String? { description }
}

/// Istantanea di una o più radici del disco: posizione, contenuto e metadati di ogni voce.
///
/// È la verità del banco, indipendente dalla macchina sotto test: ogni affermazione del recupero
/// viene confrontata con un'istantanea presa dal banco.
///
/// **Campi esclusi, in modo dichiarato.** `st_atime` e `st_ctime` non sono registrati: `atime`
/// cambia a ogni lettura, compresa quella dell'istantanea stessa, e `ctime` cambia a ogni
/// rinomina per costruzione. Nessun altro campo è escluso, e nessun nome è escluso: un `.DS_Store`
/// creato dal Cestino è uno scostamento da riportare.
public struct Snapshot: Codable, Sendable, Equatable {
  /// Tipo di una voce.
  public enum EntryKind: String, Codable, Sendable {
    case file
    case directory
  }

  /// Metadati di una voce.
  public struct Entry: Codable, Sendable, Equatable {
    public var kind: EntryKind
    /// `st_size`. Per una directory APFS dipende dal numero delle voci contenute.
    public var size: Int64
    /// SHA-256 del contenuto, solo per i file.
    public var sha256: String?
    /// `st_mode`, tipo compreso.
    public var mode: UInt16
    /// `st_flags` (per esempio `UF_IMMUTABLE`).
    public var flags: UInt32
    /// `st_mtimespec` in nanosecondi.
    public var mtime: Int64
    /// `st_birthtimespec` in nanosecondi.
    public var birthtime: Int64
    /// `st_ino`.
    public var inode: UInt64
    /// Attributi estesi: nome → SHA-256 del valore.
    public var xattrs: [String: String]

    public init(
      kind: EntryKind, size: Int64, sha256: String?, mode: UInt16, flags: UInt32, mtime: Int64,
      birthtime: Int64, inode: UInt64, xattrs: [String: String]
    ) {
      self.kind = kind
      self.size = size
      self.sha256 = sha256
      self.mode = mode
      self.flags = flags
      self.mtime = mtime
      self.birthtime = birthtime
      self.inode = inode
      self.xattrs = xattrs
    }
  }

  /// Chiave della radice della cartella di prova in `capture(volume:)`.
  public static let batchKey = "lotto"
  /// Chiave della radice del Cestino del volume in `capture(volume:)`.
  public static let trashKey = "@cestino"

  /// Voci per percorso relativo, prefissato dalla chiave della radice: la radice stessa ha per
  /// percorso la chiave (`lotto`), le voci contenute `lotto/IMG_0001.jpg`, `lotto/selezione/…`.
  public var entries: [String: Entry]

  public init(entries: [String: Entry] = [:]) {
    self.entries = entries
  }

  // MARK: - Cattura

  /// Cattura in modo ricorsivo ogni radice, voci nascoste comprese. Le chiavi prefissano i
  /// percorsi relativi. La radice di una chiave assente produce zero voci, non un errore.
  public static func capture(roots: [String: URL]) throws -> Snapshot {
    var entries: [String: Entry] = [:]
    for (key, root) in roots {
      let path = root.fileSystemPath
      var info = stat()
      guard lstat(path, &info) == 0 else {
        if errno == ENOENT { continue }
        throw SnapshotError.systemCallFailed(call: "lstat", path: path, errno: errno)
      }
      try collect(path: path, relative: key, into: &entries)
    }
    return Snapshot(entries: entries)
  }

  /// Cartella di prova e Cestino del volume di lavoro: equivale a
  /// `capture(roots: ["lotto": batchRoot, "@cestino": trashDirectory])`.
  ///
  /// Non verifica che il volume sia montato: con il volume smontato le radici sono percorsi del
  /// volume ospite.
  public static func capture(volume: WorkVolume) throws -> Snapshot {
    try capture(roots: [batchKey: volume.batchRoot, trashKey: volume.trashDirectory])
  }

  private static func collect(path: String, relative: String, into entries: inout [String: Entry])
    throws
  {
    var info = stat()
    guard lstat(path, &info) == 0 else {
      throw SnapshotError.systemCallFailed(call: "lstat", path: path, errno: errno)
    }
    let kind: EntryKind
    switch info.st_mode & S_IFMT {
    case S_IFREG: kind = .file
    case S_IFDIR: kind = .directory
    default: throw SnapshotError.unsupportedEntry(path: path, mode: info.st_mode)
    }
    entries[relative] = Entry(
      kind: kind,
      size: Int64(info.st_size),
      sha256: kind == .file ? try Fixtures.sha256Hex(ofFileAt: URL(filePath: path)) : nil,
      mode: info.st_mode,
      flags: info.st_flags,
      mtime: nanoseconds(info.st_mtimespec),
      birthtime: nanoseconds(info.st_birthtimespec),
      inode: info.st_ino,
      xattrs: try xattrDigests(path: path)
    )
    guard kind == .directory else { return }
    for name in try FileManager.default.contentsOfDirectory(atPath: path) {
      try collect(path: path + "/" + name, relative: relative + "/" + name, into: &entries)
    }
  }

  private static func nanoseconds(_ time: timespec) -> Int64 {
    Int64(time.tv_sec) * 1_000_000_000 + Int64(time.tv_nsec)
  }

  /// Attributi estesi di `path`, senza seguire collegamenti: nome → SHA-256 del valore.
  private static func xattrDigests(path: String) throws -> [String: String] {
    let listSize = listxattr(path, nil, 0, XATTR_NOFOLLOW)
    guard listSize >= 0 else {
      throw SnapshotError.systemCallFailed(call: "listxattr", path: path, errno: errno)
    }
    guard listSize > 0 else { return [:] }
    var names = [CChar](repeating: 0, count: listSize)
    let listed = listxattr(path, &names, listSize, XATTR_NOFOLLOW)
    guard listed >= 0 else {
      throw SnapshotError.systemCallFailed(call: "listxattr", path: path, errno: errno)
    }

    var digests: [String: String] = [:]
    // La lista è una sequenza di nomi terminati da NUL.
    for rawName in names.prefix(listed).split(separator: 0) {
      let name = String(decoding: rawName.map { UInt8(bitPattern: $0) }, as: UTF8.self)
      let valueSize = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
      guard valueSize >= 0 else {
        throw SnapshotError.systemCallFailed(call: "getxattr \(name)", path: path, errno: errno)
      }
      var value = [UInt8](repeating: 0, count: valueSize)
      let read = getxattr(path, name, &value, valueSize, 0, XATTR_NOFOLLOW)
      guard read >= 0 else {
        throw SnapshotError.systemCallFailed(call: "getxattr \(name)", path: path, errno: errno)
      }
      digests[name] = Fixtures.sha256Hex(of: Data(value.prefix(read)))
    }
    return digests
  }

  // MARK: - Confronto

  /// Scostamenti fra due istantanee, ordinati per percorso e per campo; vuoto se coincidono.
  ///
  /// Un percorso presente solo in `after` è `aggiunto`, solo in `before` è `rimosso`. Un percorso
  /// che cambia tipo è `rimosso` più `aggiunto`. Altrimenti ogni campo diverso è uno scostamento,
  /// e gli attributi estesi diversi formano un solo scostamento `xattr` che li nomina.
  public static func diff(_ before: Snapshot, _ after: Snapshot) -> [Deviation] {
    var deviations: [Deviation] = []
    for path in Set(before.entries.keys).union(after.entries.keys) {
      switch (before.entries[path], after.entries[path]) {
      case (nil, nil):
        break
      case (let old?, nil):
        deviations.append(.removed(path: path, kind: old.kind))
      case (nil, let new?):
        deviations.append(.added(path: path, kind: new.kind))
      case (let old?, let new?) where old.kind != new.kind:
        deviations.append(.removed(path: path, kind: old.kind))
        deviations.append(.added(path: path, kind: new.kind))
      case (let old?, let new?):
        deviations += fieldDeviations(path: path, old, new)
      }
    }
    return deviations.sorted { ($0.path, $0.field) < ($1.path, $1.field) }
  }

  private static func fieldDeviations(path: String, _ old: Entry, _ new: Entry) -> [Deviation] {
    var result: [Deviation] = []
    func compare(_ field: Deviation.Field, _ before: String?, _ after: String?) {
      guard before != after else { return }
      result.append(
        Deviation(path: path, field: field, kind: new.kind, before: before, after: after))
    }
    compare(.size, String(old.size), String(new.size))
    compare(.sha256, old.sha256, new.sha256)
    compare(.mode, String(old.mode, radix: 8), String(new.mode, radix: 8))
    compare(.flags, "0x" + String(old.flags, radix: 16), "0x" + String(new.flags, radix: 16))
    compare(.mtime, String(old.mtime), String(new.mtime))
    compare(.birthtime, String(old.birthtime), String(new.birthtime))
    compare(.inode, String(old.inode), String(new.inode))
    let changedNames = Set(old.xattrs.keys).union(new.xattrs.keys)
      .filter { old.xattrs[$0] != new.xattrs[$0] }
      .sorted()
    if !changedNames.isEmpty {
      func render(_ xattrs: [String: String]) -> String? {
        let present = changedNames.compactMap { name in xattrs[name].map { "\(name)=\($0)" } }
        return present.isEmpty ? nil : present.joined(separator: ", ")
      }
      result.append(
        Deviation(
          path: path, field: .xattr, kind: new.kind, before: render(old.xattrs),
          after: render(new.xattrs)))
    }
    return result
  }

  // MARK: - JSON

  /// JSON dell'istantanea con chiavi ordinate, terminato da un a capo.
  public func jsonData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(self)
    data.append(Data("\n".utf8))
    return data
  }

  /// Rilegge un'istantanea scritta da `jsonData()`.
  public static func load(from url: URL) throws -> Snapshot {
    try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
  }
}

/// Uno scostamento fra due istantanee, nominato per percorso e per campo.
public struct Deviation: Codable, Sendable, Equatable, CustomStringConvertible {
  /// Campo dello scostamento. L'ordine dei casi è l'ordine dell'elenco a parità di percorso.
  public enum Field: String, Codable, CaseIterable, Sendable, Comparable {
    case aggiunto
    case rimosso
    case size
    case sha256
    case mode
    case flags
    case mtime
    case birthtime
    case inode
    case xattr

    private var order: Int { Self.allCases.firstIndex(of: self)! }

    public static func < (lhs: Field, rhs: Field) -> Bool { lhs.order < rhs.order }
  }

  /// Percorso relativo prefissato dalla chiave della radice, come in `Snapshot.entries`.
  public let path: String
  public let field: Field
  /// Tipo della voce: per `rimosso` quello di prima, altrimenti quello di dopo.
  public let kind: Snapshot.EntryKind
  /// Valore prima, `nil` se assente. Per `aggiunto` e `rimosso` è il tipo della voce; `mode` è in
  /// ottale, `flags` in esadecimale, i tempi in nanosecondi; per `xattr` è l'elenco
  /// `nome=sha256` dei soli attributi diversi.
  public let before: String?
  /// Valore dopo, `nil` se assente, con le stesse convenzioni di `before`.
  public let after: String?

  public init(
    path: String, field: Field, kind: Snapshot.EntryKind, before: String?, after: String?
  ) {
    self.path = path
    self.field = field
    self.kind = kind
    self.before = before
    self.after = after
  }

  static func added(path: String, kind: Snapshot.EntryKind) -> Deviation {
    Deviation(path: path, field: .aggiunto, kind: kind, before: nil, after: kind.rawValue)
  }

  static func removed(path: String, kind: Snapshot.EntryKind) -> Deviation {
    Deviation(path: path, field: .rimosso, kind: kind, before: kind.rawValue, after: nil)
  }

  /// Vero per uno scostamento `mtime` su una directory: rinominare, aggiungere o togliere una voce
  /// aggiorna l'`mtime` della directory che la contiene.
  public var isDirectoryMtime: Bool { field == .mtime && kind == .directory }

  /// `percorso:campo`.
  public var key: String { "\(path):\(field.rawValue)" }

  public var description: String { "\(key) \(before ?? "—") → \(after ?? "—")" }
}
