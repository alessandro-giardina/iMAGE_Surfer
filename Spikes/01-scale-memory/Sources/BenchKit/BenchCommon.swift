import Foundation

/// Opzioni comuni a tutti i sottocomandi del banco.
public struct BenchOptions: Sendable {
  public var dataDirectory: URL = SpikePaths.defaultDataDirectory
  public var profile: DatasetProfile = .full
  /// Ripetizioni richieste; `nil` lascia il valore predefinito del sottocomando.
  public var repetitions: Int?
  public var outputDirectory: URL = ResultWriter.defaultRunsDirectory
  public var thumbnailPath: ThumbnailPath = .imageio
  public var window = CGSize(width: 1_512, height: 982)
  /// Fattore di scala delle anteprime. Fisso a 2, quello del display di riferimento della porta
  /// di vista 1512×982 (MacBook Pro 14" integrato), indipendentemente dallo schermo su cui si
  /// apre la finestra: così il costo di decodifica e memoria non dipende dal monitor collegato.
  public var thumbnailScale: CGFloat = 2
  /// Ammette cartelle di prima schermata già lette da un'esecuzione precedente (solo `full`).
  public var allowWarm = false
  /// Opzioni specifiche del sottocomando, come testo (es. `moves`, `long-session`).
  public var extra: [String: String] = [:]

  public init() {}
}

/// Errori del banco, con messaggi che dicono cosa fare.
public enum BenchError: Error, CustomStringConvertible {
  case datasetMissing(URL)
  case profileMismatch(expected: DatasetProfile, found: DatasetProfile)
  case notEnoughColdFolders(needed: Int, available: [String])
  case timeout(String)
  case invalidOption(String)
  case measurementFailed(String)

  public var description: String {
    switch self {
    case .datasetMissing(let url):
      "manifest del dataset assente in \(url.path): genera prima il dataset con "
        + "`swift run --package-path Spikes/01-scale-memory gen-dataset` (vedi PROCEDURE.md)"
    case .profileMismatch(let expected, let found):
      "il dataset in uso è del profilo \(found.rawValue), ma è stato richiesto il profilo "
        + "\(expected.rawValue): rigeneralo con gen-dataset --profile \(expected.rawValue)"
    case .notEnoughColdFolders(let needed, let available):
      "servono \(needed) cartelle di prima schermata mai lette, disponibili: "
        + "\(available.isEmpty ? "nessuna" : available.joined(separator: ", ")). Rigenera il "
        + "dataset, oppure usa --allow-warm dichiarando la cache calda in RESULT.md"
    case .timeout(let what):
      "scadenza superata: \(what)"
    case .invalidOption(let message):
      message
    case .measurementFailed(let message):
      "misura fallita: \(message)"
    }
  }
}

/// Dataset caricato e verificato prima di misurare.
public struct LoadedDataset: Sendable {
  public let directory: URL
  public let manifest: DatasetManifest
  public let manifestDigest: String

  /// Carica il manifest; fallisce con un messaggio che rimanda a `gen-dataset` se manca.
  public static func load(_ options: BenchOptions) throws -> LoadedDataset {
    let manifestURL = options.dataDirectory.appending(path: DatasetManifest.fileName)
    guard FileManager.default.fileExists(atPath: manifestURL.path) else {
      throw BenchError.datasetMissing(options.dataDirectory)
    }
    let (manifest, digest) = try DatasetManifest.load(fromDataDirectory: options.dataDirectory)
    guard manifest.profile == options.profile else {
      throw BenchError.profileMismatch(expected: options.profile, found: manifest.profile)
    }
    return LoadedDataset(
      directory: options.dataDirectory, manifest: manifest, manifestDigest: digest)
  }

  public func folderURL(_ name: String) -> URL {
    directory.appending(path: name, directoryHint: .isDirectory)
  }

  /// Indice TSV di una cartella del manifest.
  public func index(of folder: DatasetManifest.Folder) throws -> [DatasetIndexEntry] {
    try DatasetIndex.load(from: directory.appending(path: folder.indexFile))
  }

  // MARK: - Cartelle di prima schermata già lette

  private var touchedDirectory: URL {
    directory.appending(path: ".bench-touched", directoryHint: .isDirectory)
  }

  /// Vero se la cartella è già stata aperta da un'esecuzione di `first-screen`.
  public func wasTouched(_ folder: String) -> Bool {
    FileManager.default.fileExists(atPath: touchedDirectory.appending(path: folder).path)
  }

  /// Registra che la cartella è stata letta: le sue anteprime sono ora nella cache dei file.
  public func markTouched(_ folder: String, measurementId: String) throws {
    try FileManager.default.createDirectory(at: touchedDirectory, withIntermediateDirectories: true)
    try Data(measurementId.utf8).write(to: touchedDirectory.appending(path: folder))
  }
}

/// Stato dell'ambiente all'inizio di una ripetizione: alimentazione e modalità a basso consumo
/// sono registrate a ogni ripetizione, come lo stato termico.
public enum RepetitionEnvironment {
  public static func flags() -> [String: Bool] {
    var flags = ["lowPowerModeEnabled": ProcessInfo.processInfo.isLowPowerModeEnabled]
    if let onACPower = HostFingerprint.isOnACPower() {
      flags["onACPower"] = onACPower
    }
    return flags
  }
}

/// Orologio monotono del banco, in nanosecondi dall'avvio della macchina.
public enum BenchClock {
  public static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

  public static func milliseconds(from start: UInt64, to end: UInt64) -> Double {
    Double(Int64(bitPattern: end &- start)) / 1_000_000
  }
}

/// Attesa del rientro del footprint dopo la demolizione dell'host.
public enum FootprintSettle {
  /// Attende che `phys_footprint` torni entro `tolerance` (frazione) della baseline, con
  /// scadenza. Restituisce se è rientrato e l'ultimo footprint letto.
  @MainActor
  public static func wait(
    toWithin tolerance: Double, of baseline: UInt64, timeout: Duration
  ) async -> (settled: Bool, footprint: UInt64) {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    var current = FootprintSampler.physFootprint()
    while clock.now < deadline {
      current = FootprintSampler.physFootprint()
      if Double(current) <= Double(baseline) * (1 + tolerance) { return (true, current) }
      try? await Task.sleep(for: .milliseconds(100))
    }
    return (false, current)
  }
}

extension Dictionary where Key == String, Value == String {
  /// Valore intero di un'opzione specifica del sottocomando, con predefinito.
  public func int(_ key: String, default value: Int) throws -> Int {
    guard let raw = self[key] else { return value }
    guard let parsed = Int(raw), parsed > 0 else {
      throw BenchError.invalidOption("valore non valido per --\(key): \(raw)")
    }
    return parsed
  }

  /// Valore decimale di un'opzione specifica del sottocomando, con predefinito.
  public func double(_ key: String, default value: Double) throws -> Double {
    guard let raw = self[key] else { return value }
    guard let parsed = Double(raw), parsed > 0 else {
      throw BenchError.invalidOption("valore non valido per --\(key): \(raw)")
    }
    return parsed
  }
}
