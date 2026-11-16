import Darwin
import Foundation
import IOKit
import IOKit.ps

/// Stato termico del sistema, da `ProcessInfo.processInfo.thermalState`.
public enum ThermalState: String, Codable, Sendable, CaseIterable {
  case nominal
  case fair
  case serious
  case critical
  /// Valore che questa versione del banco non sa interpretare.
  case unknown

  /// Stato termico corrente.
  public static var current: ThermalState {
    ThermalState(ProcessInfo.processInfo.thermalState)
  }

  /// Converte lo stato termico di Foundation.
  public init(_ state: ProcessInfo.ThermalState) {
    switch state {
    case .nominal: self = .nominal
    case .fair: self = .fair
    case .serious: self = .serious
    case .critical: self = .critical
    @unknown default: self = .unknown
    }
  }

  /// `true` solo per `.nominal`: qualunque altro stato rende la misura sospetta.
  public var isNominal: Bool { self == .nominal }
}

/// Impronta dell'hardware e dell'ambiente su cui gira una misura, raccolta a ogni esecuzione.
///
/// AC-2 chiede che ogni cifra sia attribuita a una configurazione dichiarata: un campo vuoto
/// è un'attribuzione mancante, e `assertComplete()` la rende un errore esplicito.
public struct HostFingerprint: Codable, Sendable, Equatable {
  /// Modello della macchina, `sysctl hw.model` (es. `MacBookPro18,3`).
  public var model: String
  /// Processore, `sysctl machdep.cpu.brand_string` (es. `Apple M1 Pro`).
  public var cpuBrand: String
  /// Memoria fisica in byte, `sysctl hw.memsize`.
  public var physicalMemoryBytes: UInt64
  /// Core logici ad alte prestazioni, `sysctl hw.perflevel0.logicalcpu`.
  public var performanceCores: Int
  /// Core logici ad alta efficienza, `sysctl hw.perflevel1.logicalcpu`.
  public var efficiencyCores: Int
  /// Processori attivi, `ProcessInfo.activeProcessorCount`.
  public var activeProcessorCount: Int
  /// Versione di macOS, `major.minor.patch` da `ProcessInfo.operatingSystemVersion`.
  public var osProductVersion: String
  /// Build di macOS, `sysctl kern.osversion`.
  public var osBuildVersion: String
  /// Versione del compilatore Swift che ha costruito il banco, fissata a tempo di compilazione
  /// con precisione `major.minor`.
  public var swiftVersion: String
  /// Versione dell'SDK, `xcrun --show-sdk-version`; vuota solo se il comando fallisce.
  public var sdkVersion: String
  /// Tipo di filesystem del volume che contiene il dataset (es. `apfs`), da `statfs`.
  public var volumeFileSystemType: String
  /// `true` se il volume del dataset risiede su un dispositivo a stato solido, secondo
  /// `Device Characteristics` → `Medium Type` nel registro IOKit. `nil` se non determinabile.
  public var volumeIsSolidState: Bool?
  /// Byte disponibili sul volume del dataset al momento della raccolta, da `statfs`.
  public var volumeAvailableBytes: UInt64
  /// Stato termico al momento della raccolta.
  public var thermalState: ThermalState
  /// Modalità a basso consumo attiva al momento della raccolta.
  public var lowPowerModeEnabled: Bool
  /// `true` se alimentata dalla rete, `false` se a batteria, secondo
  /// `IOPSGetProvidingPowerSourceType`. `nil` se non determinabile.
  public var onACPower: Bool?

  /// Crea un'impronta con valori dati (per i test).
  public init(
    model: String,
    cpuBrand: String,
    physicalMemoryBytes: UInt64,
    performanceCores: Int,
    efficiencyCores: Int,
    activeProcessorCount: Int,
    osProductVersion: String,
    osBuildVersion: String,
    swiftVersion: String,
    sdkVersion: String,
    volumeFileSystemType: String,
    volumeIsSolidState: Bool?,
    volumeAvailableBytes: UInt64,
    thermalState: ThermalState,
    lowPowerModeEnabled: Bool,
    onACPower: Bool?
  ) {
    self.model = model
    self.cpuBrand = cpuBrand
    self.physicalMemoryBytes = physicalMemoryBytes
    self.performanceCores = performanceCores
    self.efficiencyCores = efficiencyCores
    self.activeProcessorCount = activeProcessorCount
    self.osProductVersion = osProductVersion
    self.osBuildVersion = osBuildVersion
    self.swiftVersion = swiftVersion
    self.sdkVersion = sdkVersion
    self.volumeFileSystemType = volumeFileSystemType
    self.volumeIsSolidState = volumeIsSolidState
    self.volumeAvailableBytes = volumeAvailableBytes
    self.thermalState = thermalState
    self.lowPowerModeEnabled = lowPowerModeEnabled
    self.onACPower = onACPower
  }

  /// Raccoglie l'impronta della macchina corrente.
  ///
  /// La raccolta non fallisce: una sonda che non risponde lascia il campo vuoto, a zero o
  /// `nil`, e `assertComplete()` lo nomina.
  ///
  /// - Parameter path: un percorso sul volume che contiene il dataset. Se non esiste ancora,
  ///   vale il volume del suo antenato esistente più vicino.
  public static func collect(volumeContaining path: URL) -> HostFingerprint {
    let processInfo = ProcessInfo.processInfo
    let os = processInfo.operatingSystemVersion
    let volume = VolumeProbe(containing: path)
    return HostFingerprint(
      model: Sysctl.string("hw.model"),
      cpuBrand: Sysctl.string("machdep.cpu.brand_string"),
      physicalMemoryBytes: Sysctl.unsignedInteger("hw.memsize"),
      performanceCores: Int(clamping: Sysctl.unsignedInteger("hw.perflevel0.logicalcpu")),
      efficiencyCores: Int(clamping: Sysctl.unsignedInteger("hw.perflevel1.logicalcpu")),
      activeProcessorCount: processInfo.activeProcessorCount,
      osProductVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
      osBuildVersion: Sysctl.string("kern.osversion"),
      swiftVersion: compilerVersion,
      sdkVersion: sdkVersionFromXcrun(),
      volumeFileSystemType: volume?.fileSystemType ?? "",
      volumeIsSolidState: volume.flatMap { isSolidState(bsdName: $0.bsdName) },
      volumeAvailableBytes: volume?.availableBytes ?? 0,
      thermalState: .current,
      lowPowerModeEnabled: processInfo.isLowPowerModeEnabled,
      onACPower: isOnACPower()
    )
  }

  /// Errore di `assertComplete()`: nomina ogni campo vuoto, a zero o non determinato.
  public struct IncompleteError: Error, Equatable, CustomStringConvertible, LocalizedError {
    /// Nomi dei campi mancanti, come compaiono nel JSON.
    public let missingFields: [String]

    public var description: String {
      "impronta hardware incompleta, campi vuoti o non determinati: "
        + missingFields.joined(separator: ", ")
    }

    public var errorDescription: String? { description }
  }

  /// Campi vuoti, pari a zero o non determinati, nell'ordine in cui compaiono nel tipo.
  public var missingFields: [String] {
    let checks: [(name: String, isMissing: Bool)] = [
      ("model", model.isBlank),
      ("cpuBrand", cpuBrand.isBlank),
      ("physicalMemoryBytes", physicalMemoryBytes == 0),
      ("performanceCores", performanceCores == 0),
      ("efficiencyCores", efficiencyCores == 0),
      ("activeProcessorCount", activeProcessorCount == 0),
      ("osProductVersion", osProductVersion.isBlank),
      ("osBuildVersion", osBuildVersion.isBlank),
      ("swiftVersion", swiftVersion.isBlank),
      ("sdkVersion", sdkVersion.isBlank),
      ("volumeFileSystemType", volumeFileSystemType.isBlank),
      ("volumeIsSolidState", volumeIsSolidState == nil),
      ("volumeAvailableBytes", volumeAvailableBytes == 0),
      ("thermalState", thermalState == .unknown),
      ("onACPower", onACPower == nil),
    ]
    return checks.filter(\.isMissing).map(\.name)
  }

  /// Fallisce nominando ogni campo vuoto, pari a zero o non determinato.
  ///
  /// I booleani determinati (`false` compreso) sono valori validi: `onACPower == false`
  /// dichiara la batteria, non un'assenza.
  public func assertComplete() throws {
    let missing = missingFields
    guard missing.isEmpty else { throw IncompleteError(missingFields: missing) }
  }

  /// Versione del compilatore Swift, fissata a tempo di compilazione.
  static let compilerVersion: String = {
    #if compiler(>=7.0)
      return "7.0+"
    #elseif compiler(>=6.9)
      return "6.9"
    #elseif compiler(>=6.8)
      return "6.8"
    #elseif compiler(>=6.7)
      return "6.7"
    #elseif compiler(>=6.6)
      return "6.6"
    #elseif compiler(>=6.5)
      return "6.5"
    #elseif compiler(>=6.4)
      return "6.4"
    #elseif compiler(>=6.3)
      return "6.3"
    #elseif compiler(>=6.2)
      return "6.2"
    #elseif compiler(>=6.1)
      return "6.1"
    #else
      return "6.0"
    #endif
  }()

  private static func sdkVersionFromXcrun() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["--show-sdk-version"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return ""
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return "" }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Risale il registro IOKit dal dispositivo BSD del volume (per APFS: volume, contenitore,
  /// archivio fisico, disco) fino a `Device Characteristics` del supporto fisico.
  private static func isSolidState(bsdName: String) -> Bool? {
    guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else { return nil }
    let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    guard service != IO_OBJECT_NULL else { return nil }
    defer { IOObjectRelease(service) }
    let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
    guard
      let property = IORegistryEntrySearchCFProperty(
        service,
        kIOServicePlane,
        "Device Characteristics" as CFString,
        kCFAllocatorDefault,
        options
      ),
      let characteristics = property as? [String: Any],
      let medium = characteristics["Medium Type"] as? String
    else { return nil }
    return medium == "Solid State"
  }

  static func isOnACPower() -> Bool? {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
    else { return nil }
    return (source as String) == kIOPMACPowerKey
  }
}

/// Filesystem, dispositivo e spazio libero del volume che contiene un percorso.
private struct VolumeProbe {
  let fileSystemType: String
  let bsdName: String
  let availableBytes: UInt64

  init?(containing path: URL) {
    var candidate = path.standardizedFileURL
    while !FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
      let parent = candidate.deletingLastPathComponent()
      guard parent.path(percentEncoded: false) != candidate.path(percentEncoded: false) else {
        return nil
      }
      candidate = parent
    }
    var info = statfs()
    guard statfs(candidate.path(percentEncoded: false), &info) == 0 else { return nil }
    fileSystemType = withUnsafeBytes(of: info.f_fstypename) { String(cStringBytes: $0) }
    let device = withUnsafeBytes(of: info.f_mntfromname) { String(cStringBytes: $0) }
    bsdName = device.hasPrefix("/dev/") ? String(device.dropFirst("/dev/".count)) : device
    availableBytes = UInt64(info.f_bavail) * UInt64(info.f_bsize)
  }
}

/// Lettura di `sysctlbyname` senza eccezioni: una chiave assente restituisce vuoto o zero.
private enum Sysctl {
  static func string(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
    return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func unsignedInteger(_ name: String) -> UInt64 {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return 0 }
    switch size {
    case MemoryLayout<UInt32>.size:
      var value: UInt32 = 0
      guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return 0 }
      return UInt64(value)
    case MemoryLayout<UInt64>.size:
      var value: UInt64 = 0
      guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return 0 }
      return value
    default:
      return 0
    }
  }
}

extension String {
  fileprivate var isBlank: Bool {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Decodifica una stringa C a lunghezza fissa (terminata da zero o dalla fine del buffer).
  fileprivate init(cStringBytes bytes: UnsafeRawBufferPointer) {
    self = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
  }
}
