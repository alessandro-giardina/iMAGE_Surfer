import Darwin
import Foundation

/// Impronta della macchina su cui gira il banco, riportata nel JSON di misura perché ogni esito
/// sia attribuito a un host, a una versione di macOS e a un utente dichiarati.
///
/// L'utente conta: il Cestino del volume di lavoro è `.Trashes/<uid>`.
public struct HostFingerprint: Codable, Sendable, Equatable {
  /// Modello della macchina, `sysctl hw.model` (es. `MacBookPro18,3`).
  public var model: String
  /// Versione di macOS leggibile, `ProcessInfo.operatingSystemVersionString`.
  public var osVersion: String
  /// Build di macOS, `sysctl kern.osversion`.
  public var osBuild: String
  /// Identificativo dell'utente che esegue il banco, `getuid()`.
  public var uid: UInt32

  public init(model: String, osVersion: String, osBuild: String, uid: UInt32) {
    self.model = model
    self.osVersion = osVersion
    self.osBuild = osBuild
    self.uid = uid
  }

  /// Impronta della macchina corrente. Una chiave `sysctl` che non risponde lascia il campo vuoto.
  public static func current() -> HostFingerprint {
    HostFingerprint(
      model: sysctlString("hw.model"),
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      osBuild: sysctlString("kern.osversion"),
      uid: getuid()
    )
  }

  /// Lettura di una stringa con `sysctlbyname`: una chiave assente restituisce la stringa vuota.
  private static func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
    return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
