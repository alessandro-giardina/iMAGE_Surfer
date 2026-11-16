import CryptoKit
import Foundation
import Testing

@testable import BenchKit

@Suite("Generatore del dataset sul profilo smoke")
struct GeneratorTests {
  let config: DatasetConfig

  init() throws {
    config = try DatasetConfig.load(from: SpikePaths.defaultConfig)
  }

  @Test("il manifest esiste e dichiara 240 file nella cartella di scorrimento")
  func manifestTotals() async throws {
    let (directory, manifest) = try await SmokeDataset.prepared()
    let manifestURL = directory.appending(path: DatasetManifest.fileName)
    #expect(FileManager.default.fileExists(atPath: manifestURL.path))
    let (onDisk, digest) = try DatasetManifest.load(fromDataDirectory: directory)
    #expect(onDisk.totals.total == 240)
    #expect(onDisk.profile == .smoke)
    #expect(digest.count == 64)
    #expect(manifest.totals.total == 240)
    #expect(manifest.totals.uniqueTotal + manifest.totals.cloneTotal == 240)
    let configDigest = DatasetManifest.sha256Hex(try Data(contentsOf: SpikePaths.defaultConfig))
    #expect(onDisk.configDigest == configDigest)
  }

  @Test("i conteggi per cella combaciano con smokeProfile e con i file su disco")
  func cellCountsMatchSmokeProfile() async throws {
    let (directory, manifest) = try await SmokeDataset.prepared()
    let scroll = config.smokeProfile.scrollFolder
    #expect(manifest.cells.count == 12)
    for cell in manifest.cells {
      let key = DatasetCell(
        format: cell.format,
        resolutionClass: try #require(ResolutionClass(rawValue: cell.resolutionClass)))
      let declared = scroll.distribution.count(for: key)
      #expect(cell.totalCount == declared, "cella \(key)")
      #expect(cell.uniqueCount == min(scroll.uniquePerCell, declared), "cella \(key)")
      #expect(cell.uniqueCount + cell.cloneCount == cell.totalCount, "cella \(key)")
    }
    let files = try imageFiles(in: directory.appending(path: scroll.name))
    #expect(files.count == 240)
  }

  @Test("due cartelle di prima schermata da 24 file, tutti effettivamente unici")
  func firstScreenFilesAreUnique() async throws {
    let (directory, manifest) = try await SmokeDataset.prepared()
    #expect(manifest.folders.firstScreen.map(\.name) == ["p1-run-01", "p1-run-02"])
    var digests: [String: String] = [:]
    for folder in manifest.folders.firstScreen {
      #expect(folder.cloneCount == 0)
      let files = try imageFiles(in: directory.appending(path: folder.name))
      #expect(files.count == 24)
      for file in files {
        let handle = try FileHandle(forReadingFrom: file)
        let prefix = try handle.read(upToCount: 64 * 1_024) ?? Data()
        try handle.close()
        let digest = SHA256.hash(data: prefix).map { String(format: "%02x", $0) }.joined()
        #expect(digests[digest] == nil, "collisione fra \(file.path) e \(digests[digest] ?? "")")
        digests[digest] = file.path
      }
    }
    #expect(digests.count == 48)
  }

  @Test("i cloni della cartella di scorrimento hanno inode distinti e contenuto identico")
  func clonesAreDistinctFilesWithIdenticalContent() async throws {
    let (directory, manifest) = try await SmokeDataset.prepared()
    let index = try DatasetIndex.load(
      from: directory.appending(path: manifest.folders.scroll.indexFile))
    let bySource = Dictionary(grouping: index.filter(\.isClone)) { $0.cloneSource! }
    let (source, clones) = try #require(bySource.first { $0.value.count >= 2 })
    let folder = directory.appending(path: manifest.folders.scroll.name)
    let urls = [source, clones[0].name, clones[1].name].map { folder.appending(path: $0) }

    func inode(_ url: URL) throws -> UInt64 {
      var info = stat()
      guard stat(url.path, &info) == 0 else { throw CocoaError(.fileReadNoSuchFile) }
      return UInt64(info.st_ino)
    }
    let inodes = try urls.map(inode)
    #expect(Set(inodes).count == 3, "un clone deve essere un file distinto")
    let contents = try urls.map { try Data(contentsOf: $0) }
    #expect(!contents[0].isEmpty)
    #expect(contents[1] == contents[0])
    #expect(contents[2] == contents[0])
    #expect(manifest.cloneSupported)
  }

  @Test("JPEG e HEIC centrano i byte per megapixel oppure dichiarano toleranceMiss")
  func lossyCellsHitTargetOrDeclareMiss() async throws {
    let (directory, manifest) = try await SmokeDataset.prepared()
    let raw = try Data(contentsOf: directory.appending(path: DatasetManifest.fileName))
    let json = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
    let cells = try #require(json["cells"] as? [[String: Any]])
    for cell in cells {
      #expect(cell["toleranceMiss"] is Bool, "campo toleranceMiss assente: \(cell)")
      #expect(cell["bytesPerMegapixelAchieved"] is Double, "campo assente: \(cell)")
    }
    for cell in manifest.cells where cell.format.isLossy {
      let withinTolerance =
        abs(cell.bytesPerMegapixelAchieved - cell.bytesPerMegapixelTarget)
        <= cell.bytesPerMegapixelTarget * manifest.tolerance
      #expect(withinTolerance || cell.toleranceMiss, "cella \(cell.format)/\(cell.resolutionClass)")
      #expect(cell.encoderQuality != nil)
    }
  }

  @Test("il pre-volo rifiuta quando il libero è inferiore a 1,3 volte la stima")
  func preflightRefusesInsufficientSpace() throws {
    let estimated: Int64 = 100_000_000_000
    let error = try #require(throws: DatasetGenerationError.self) {
      try DatasetGenerator.preflight(estimatedBytes: estimated, availableBytes: 120_000_000_000)
    }
    #expect(
      error
        == .insufficientSpace(
          estimated: estimated, available: 120_000_000_000, required: 130_000_000_000))
    #expect(error.description.contains("100000000000"))
    #expect(error.description.contains("120000000000"))
    #expect(error.description.contains("firstScreenFolders.count"))
    try DatasetGenerator.preflight(estimatedBytes: estimated, availableBytes: 130_000_000_000)
  }

  @Test("senza --force il generatore non sovrascrive un dataset esistente")
  func refusesToOverwriteWithoutForce() async throws {
    let (directory, _) = try await SmokeDataset.prepared()
    let generator = try DatasetGenerator(
      configURL: SpikePaths.defaultConfig, profile: .smoke, outputDirectory: directory,
      force: false, log: { _ in })
    await #expect(throws: DatasetGenerationError.self) {
      _ = try await generator.generate()
    }
  }
}
