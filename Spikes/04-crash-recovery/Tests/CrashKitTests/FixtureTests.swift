import Foundation
import Testing

@testable import CrashKit

@Suite("Fixture versionate del lotto di prova")
struct FixtureTests {
  private var batchURL: URL {
    CrashPaths.fixtures.appending(path: Fixtures.batchFileName, directoryHint: .notDirectory)
  }

  @Test("le fixture del repository coincidono con MANIFEST.json")
  func repositoryFixturesMatchManifest() throws {
    let manifest = try verifyFixtures(at: CrashPaths.fixtures)
    // batch.json più cinque coppie immagine+sidecar, ordinati per percorso.
    #expect(manifest.files.count == 1 + 2 * Fixtures.pairCount)
    #expect(manifest.files.map(\.path) == manifest.files.map(\.path).sorted())
    #expect(manifest.files.contains { $0.path == Fixtures.batchFileName })
    // Digest tutti diversi: il Cestino del banco cerca le voci per digest.
    #expect(Set(manifest.files.map(\.sha256)).count == manifest.files.count)
  }

  @Test("batch.json decodifica cinque operazioni rename, move, move, copy, trash, nell'ordine")
  func batchDefinitionDecodes() throws {
    let batch = try BatchDefinition.load(from: batchURL)
    #expect(batch.batchId == "lotto-di-prova")
    #expect(batch.root == "lotto")
    #expect(batch.operations.map(\.kind) == [.rename, .move, .move, .copy, .trash])
    #expect(batch.operations.map(\.id) == ["OP1", "OP2", "OP3", "OP4", "OP5"])
    #expect(batch.operations.map(\.stem) == Fixtures.stems)
    #expect(batch.operations.map(\.to).filter { $0 == nil }.count == 1)
    #expect(batch.operations.last?.to == nil)
  }

  @Test("ogni stem del lotto ha sia .jpg sia .xmp in folder/")
  func everyStemHasImageAndSidecar() throws {
    let batch = try BatchDefinition.load(from: batchURL)
    for operation in batch.operations {
      for fileExtension in Fixtures.pairExtensions {
        let name = "\(operation.stem).\(fileExtension)"
        let url = CrashPaths.fixtureFolder.appending(path: name, directoryHint: .notDirectory)
        #expect(
          FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
          "\(name) assente da folder/")
      }
    }
  }

  @Test("un byte modificato in IMG_0003.xmp fa fallire la verifica nominando quel file")
  func modifiedByteIsNamed() throws {
    let copy = try fixtureCopy()
    defer { try? FileManager.default.removeItem(at: copy) }
    // Controllo: la copia intatta passa, quindi il fallimento viene solo dalla modifica.
    try verifyFixtures(at: copy)

    let target = copy.appending(path: "folder/IMG_0003.xmp", directoryHint: .notDirectory)
    var data = try Data(contentsOf: target)
    data[data.startIndex + data.count / 2] ^= 0x01
    try data.write(to: target)

    let error = #expect(throws: FixtureError.self) { try verifyFixtures(at: copy) }
    #expect(error?.path == "folder/IMG_0003.xmp")
    #expect(error?.description.contains("folder/IMG_0003.xmp") == true)
  }

  @Test("un file in folder/ assente dal manifest fa fallire la verifica nominando quel file")
  func unlistedFileIsNamed() throws {
    let copy = try fixtureCopy()
    defer { try? FileManager.default.removeItem(at: copy) }
    try Data("estraneo\n".utf8).write(
      to: copy.appending(path: "folder/IMG_0006.xmp", directoryHint: .notDirectory))

    let error = #expect(throws: FixtureError.self) { try verifyFixtures(at: copy) }
    #expect(error == .unlistedFile(path: "folder/IMG_0006.xmp"))
  }

  @Test("la generazione rifiuta di sovrascrivere senza force, e con force riscrive il manifest")
  func generationRefusesOverwriteWithoutForce() throws {
    let copy = try fixtureCopy()
    defer { try? FileManager.default.removeItem(at: copy) }

    let refusal = #expect(throws: FixtureError.self) {
      try makeFixtures(into: copy, force: false)
    }
    #expect(refusal == .alreadyExists(path: "folder/IMG_0001.jpg"))

    let manifest = try makeFixtures(into: copy, force: true)
    #expect(try verifyFixtures(at: copy) == manifest)
  }
}
