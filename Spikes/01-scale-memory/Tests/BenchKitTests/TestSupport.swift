import Foundation

@testable import BenchKit

/// Dataset `smoke` condiviso dall'intera suite: generato in-process una sola volta per processo
/// di test, in una directory temporanea fissa che `--force` riscrive a ogni esecuzione.
enum SmokeDataset {
  static let directory = FileManager.default.temporaryDirectory
    .appending(path: "spike01-tests-smoke", directoryHint: .isDirectory)

  /// Generazione condivisa: il primo test che la attende la avvia, gli altri ne riusano l'esito.
  static let generation = Task<DatasetManifest, any Error> {
    let generator = try DatasetGenerator(
      configURL: SpikePaths.defaultConfig, profile: .smoke, outputDirectory: directory,
      force: true, log: { _ in })
    return try await generator.generate()
  }

  static func prepared() async throws -> (directory: URL, manifest: DatasetManifest) {
    (directory, try await generation.value)
  }
}

/// File immagine di una cartella del dataset, esclusi gli indici e i file nascosti.
func imageFiles(in folder: URL) throws -> [URL] {
  try FileManager.default.contentsOfDirectory(
    at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
  )
  .filter { ImageFormat(fileExtension: $0.pathExtension) != nil }
  .sorted { $0.lastPathComponent < $1.lastPathComponent }
}
