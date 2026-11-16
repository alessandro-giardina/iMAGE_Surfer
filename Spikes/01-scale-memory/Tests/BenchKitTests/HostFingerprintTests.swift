import Foundation
import Testing

@testable import BenchKit

@Suite("Impronta hardware")
struct HostFingerprintTests {
  @Test("l'impronta raccolta su questa macchina è completa")
  func collectedFingerprintIsComplete() throws {
    let host = HostFingerprint.collect(volumeContaining: SpikePaths.packageRoot)
    try host.assertComplete()
    #expect(host.physicalMemoryBytes > 0)
    #expect(host.activeProcessorCount > 0)
    #expect(!host.model.isEmpty)
    #expect(!host.osBuildVersion.isEmpty)
    #expect(!host.volumeFileSystemType.isEmpty)
    #expect(host.volumeIsSolidState != nil)
  }

  @Test("un'impronta con il modello vuoto fa fallire assertComplete nominando model")
  func emptyModelIsNamed() throws {
    var host = HostFingerprint.collect(volumeContaining: SpikePaths.packageRoot)
    host.model = ""
    #expect(host.missingFields == ["model"])
    let error = try #require(throws: HostFingerprint.IncompleteError.self) {
      try host.assertComplete()
    }
    #expect(error.missingFields == ["model"])
    #expect(error.description.contains("model"))
  }

  @Test("ogni campo vuoto o nullo viene nominato")
  func everyMissingFieldIsNamed() {
    var host = HostFingerprint.collect(volumeContaining: SpikePaths.packageRoot)
    host.physicalMemoryBytes = 0
    host.volumeFileSystemType = " "
    host.volumeIsSolidState = nil
    #expect(
      host.missingFields == ["physicalMemoryBytes", "volumeFileSystemType", "volumeIsSolidState"])
  }
}
