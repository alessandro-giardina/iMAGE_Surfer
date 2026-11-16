import Foundation
import Testing

@testable import BenchKit

@Suite("Configurazione versionata del dataset")
struct DatasetConfigTests {
  @Test("dataset.json del repository dichiara 50.000 file, 3.000 per cartella e 12 celle")
  func repositoryConfigIsConsistent() throws {
    let config = try DatasetConfig.load(from: SpikePaths.defaultConfig)
    #expect(config.schema == DatasetConfig.schemaIdentifier)
    #expect(config.scrollFolder.total == 50_000)
    #expect(config.scrollFolder.distribution.total == 50_000)
    #expect(config.firstScreenFolders.size == 3_000)
    #expect(config.firstScreenFolders.distribution.total == 3_000)
    #expect(config.firstScreenFolders.count == 10)
    #expect(config.smokeProfile.scrollFolder.total == 240)
    #expect(config.smokeProfile.scrollFolder.distribution.total == 240)
    #expect(config.smokeProfile.firstScreenFolders.distribution.total == 24)
    #expect(DatasetCell.all.count == 12)
    #expect(config.scrollFolder.distribution.counts.count == 12)
    #expect(config.scrollFolder.distribution.counts.values.allSatisfy { $0 > 0 })
  }

  @Test("la stima di spazio del profilo pieno è nell'ordine dichiarato in PROCEDURE.md")
  func fullProfileEstimate() throws {
    let plan = try DatasetConfig.load(from: SpikePaths.defaultConfig).plan(for: .full)
    let gigabytes = Double(plan.estimatedRequiredBytes) / 1e9
    #expect(gigabytes > 200 && gigabytes < 260)
  }

  @Test("una distribuzione che non somma al totale è rifiutata nominando la cella")
  func inconsistentDistributionIsRejected() throws {
    let data = try Data(contentsOf: SpikePaths.defaultConfig)
    var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    var scroll = try #require(json["scrollFolder"] as? [String: Any])
    var distribution = try #require(scroll["distribution"] as? [String: [String: Int]])
    distribution["jpeg"]?["S"] = 6_001
    scroll["distribution"] = distribution
    json["scrollFolder"] = scroll
    let malformed = try JSONSerialization.data(withJSONObject: json)

    let error = try #require(throws: DatasetConfigError.self) {
      try JSONDecoder().decode(DatasetConfig.self, from: malformed)
    }
    guard case .inconsistentDistribution(let path, let declared, let sum, _) = error else {
      Issue.record("errore inatteso: \(error)")
      return
    }
    #expect(path == "scrollFolder.distribution")
    #expect(declared == 50_000)
    #expect(sum == 50_001)
    #expect(error.description.contains("scrollFolder.distribution"))
    #expect(error.description.contains("jpeg/S=6001"))
  }

  @Test("una cella sconosciuta è rifiutata nominandola")
  func unknownCellIsRejected() throws {
    let data = try Data(contentsOf: SpikePaths.defaultConfig)
    var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    var smoke = try #require(json["smokeProfile"] as? [String: Any])
    var scroll = try #require(smoke["scrollFolder"] as? [String: Any])
    var distribution = try #require(scroll["distribution"] as? [String: [String: Int]])
    distribution["webp"] = ["S": 1]
    scroll["distribution"] = distribution
    smoke["scrollFolder"] = scroll
    json["smokeProfile"] = smoke
    let malformed = try JSONSerialization.data(withJSONObject: json)

    let error = try #require(throws: DatasetConfigError.self) {
      try JSONDecoder().decode(DatasetConfig.self, from: malformed)
    }
    #expect(error.description.contains("webp"))
    #expect(error.description.contains("smokeProfile.scrollFolder"))
  }
}
