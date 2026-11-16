import Darwin
import Foundation
import Testing

@testable import CrashKit

/// Volume di lavoro reale su immagine disco: ogni test monta un proprio volume ed è eseguito in
/// serie, perché `diskutil` serializza comunque i montaggi.
@Suite("Volume di lavoro su immagine disco APFS", .serialized)
struct WorkVolumeTests {
  /// Nome → SHA-256 dei file di `fixtures/folder/` secondo `MANIFEST.json`.
  private func manifestDigests() throws -> [String: String] {
    let manifest = try JSONDecoder().decode(
      FixtureManifest.self,
      from: Data(
        contentsOf: CrashPaths.fixtures.appending(
          path: Fixtures.manifestFileName, directoryHint: .notDirectory)))
    let prefix = "\(Fixtures.folderName)/"
    return Dictionary(
      uniqueKeysWithValues: manifest.files
        .filter { $0.path.hasPrefix(prefix) }
        .map { (String($0.path.dropFirst(prefix.count)), $0.sha256) })
  }

  /// Verifica che `batchRoot` contenga esattamente i file della fixture, con i digest del manifest.
  private func expectPristineBatchFolder(_ volume: WorkVolume) throws {
    let expected = try manifestDigests()
    #expect(expected.count == 2 * Fixtures.pairCount)
    let present = try FileManager.default.contentsOfDirectory(
      atPath: volume.batchRoot.path(percentEncoded: false))
    #expect(present.sorted() == expected.keys.sorted())
    for (name, digest) in expected {
      let url = volume.batchRoot.appending(path: name, directoryHint: .notDirectory)
      #expect(try Fixtures.sha256Hex(ofFileAt: url) == digest, "digest diverso per \(name)")
    }
  }

  @Test(
    "dopo l'apertura il volume è montato su un volume diverso dall'ospite, e attach è idempotente")
  func openedVolumeIsMounted() throws {
    let test = try TestVolume(name: "work-volume-open")
    defer { test.close() }
    let volume = test.volume

    #expect(volume.isMounted)
    let mountUUID = try WorkVolume.volumeUUID(of: volume.mountPoint)
    let hostUUID = try WorkVolume.volumeUUID(of: volume.dataDirectory)
    #expect(mountUUID != hostUUID)
    #expect(try WorkVolume.volumeUUID(of: volume.batchRoot) == mountUUID)
    // Lo stato durevole sta sull'ospite, non sul volume di lavoro.
    #expect(try WorkVolume.volumeUUID(of: volume.stateDirectory) == hostUUID)

    try volume.attach()
    #expect(volume.isMounted)
    #expect(try WorkVolume.volumeUUID(of: volume.mountPoint) == mountUUID)
  }

  @Test("batchRoot contiene esattamente i 10 file della fixture, con i digest del manifest")
  func batchFolderMatchesManifest() throws {
    let test = try TestVolume(name: "work-volume-fixture")
    defer { test.close() }
    try expectPristineBatchFolder(test.volume)
  }

  @Test("trashItem su lotto/IMG_0005.jpg mette il file nel Cestino del volume")
  func trashItemLandsInVolumeTrash() throws {
    let test = try TestVolume(name: "work-volume-trash")
    defer { test.close() }
    let volume = test.volume
    let source = volume.batchRoot.appending(path: "IMG_0005.jpg", directoryHint: .notDirectory)
    let digest = try Fixtures.sha256Hex(ofFileAt: source)

    var resulting: NSURL?
    try FileManager.default.trashItem(at: source, resultingItemURL: &resulting)
    let trashed = try #require(resulting as URL?)

    let trashPath = volume.trashDirectory.resolvingSymlinksInPath().fileSystemPath
    let trashedPath = trashed.resolvingSymlinksInPath().fileSystemPath
    #expect(trashedPath.hasPrefix(trashPath + "/"), "\(trashedPath) fuori da \(trashPath)")
    #expect(!FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
    #expect(try Fixtures.sha256Hex(ofFileAt: trashed) == digest)
    #expect(
      try WorkVolume.volumeUUID(of: trashed) == WorkVolume.volumeUUID(of: volume.mountPoint))

    // L'istantanea del volume vede la voce nel Cestino, con il suo digest, e non più nel lotto.
    let snapshot = try Snapshot.capture(volume: volume)
    #expect(snapshot.entries["\(Snapshot.trashKey)/\(trashed.lastPathComponent)"]?.sha256 == digest)
    #expect(snapshot.entries["\(Snapshot.batchKey)/IMG_0005.jpg"] == nil)
  }

  @Test("dopo eject il volume è smontato e mnt è una directory del volume ospite")
  func ejectLeavesHostDirectory() throws {
    let test = try TestVolume(name: "work-volume-eject")
    defer { test.close() }
    let volume = test.volume

    try volume.eject()
    #expect(!volume.isMounted)
    var isDirectory: ObjCBool = false
    #expect(
      FileManager.default.fileExists(
        atPath: volume.mountPoint.path(percentEncoded: false), isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
    #expect(
      try WorkVolume.volumeUUID(of: volume.mountPoint)
        == WorkVolume.volumeUUID(of: volume.dataDirectory))
    #expect(
      try FileManager.default.contentsOfDirectory(
        atPath: volume.mountPoint.path(percentEncoded: false)
      ).isEmpty)

    // Espellere un volume già smontato non fa nulla.
    try volume.eject()
    #expect(!volume.isMounted)
  }

  @Test("resetBatchFolder con il volume smontato lancia un errore e non crea lotto sull'ospite")
  func resetRefusesUnmountedVolume() throws {
    let test = try TestVolume(name: "work-volume-unmounted")
    defer { test.close() }
    let volume = test.volume

    try volume.eject()
    let error = #expect(throws: WorkVolumeError.self) { try volume.resetBatchFolder() }
    #expect(error == .notMounted(mountPoint: volume.mountPoint.fileSystemPath))
    #expect(!FileManager.default.fileExists(atPath: volume.batchRoot.path(percentEncoded: false)))
    #expect(
      !FileManager.default.fileExists(atPath: volume.quarantine.path(percentEncoded: false)))
  }

  @Test("resetBatchFolder ripristina la fixture e svuota Cestino, quarantena e state/")
  func resetRestoresFixture() throws {
    let test = try TestVolume(name: "work-volume-reset")
    defer { test.close() }
    let volume = test.volume
    let fileManager = FileManager.default

    // Un lotto a metà: una rinomina, un file nel Cestino, uno in quarantena, un file estraneo, un
    // record di stato, più le perturbazioni che impedirebbero una rimozione ingenua.
    try fileManager.moveItem(
      at: volume.batchRoot.appending(path: "IMG_0001.jpg"),
      to: volume.batchRoot.appending(path: "2026-08-24_evento_001.jpg"))
    try fileManager.trashItem(
      at: volume.batchRoot.appending(path: "IMG_0005.jpg"), resultingItemURL: nil)
    try fileManager.moveItem(
      at: volume.batchRoot.appending(path: "IMG_0002.xmp"),
      to: volume.quarantine.appending(path: "IMG_0002.xmp"))
    try Data("estraneo".utf8).write(to: volume.batchRoot.appending(path: "estraneo.txt"))
    try Data("{}\n".utf8).write(to: volume.stateDirectory.appending(path: "intent-log.jsonl"))
    let locked = volume.batchRoot.appending(path: "IMG_0003.jpg").path(percentEncoded: false)
    #expect(chflags(locked, UInt32(UF_IMMUTABLE)) == 0)
    #expect(chmod(volume.batchRoot.path(percentEncoded: false), 0o555) == 0)

    try volume.resetBatchFolder()

    try expectPristineBatchFolder(volume)
    #expect(
      try fileManager.contentsOfDirectory(atPath: volume.trashDirectory.path(percentEncoded: false))
        .isEmpty)
    #expect(
      try fileManager.contentsOfDirectory(atPath: volume.quarantine.path(percentEncoded: false))
        .isEmpty)
    #expect(
      try fileManager.contentsOfDirectory(atPath: volume.stateDirectory.path(percentEncoded: false))
        .isEmpty)
  }
}
