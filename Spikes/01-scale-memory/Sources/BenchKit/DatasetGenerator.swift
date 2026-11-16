import Darwin
import Foundation

/// Generatore del dataset del cancello n°1.
///
/// Ordine di generazione: cartelle di prima schermata (`p1-run-01` …, file tutti unici e mai
/// clonati, disgiunte fra loro), cartella di scorrimento (`uniquePerCell` file unici per cella,
/// il resto con cloni APFS a nome distinto), pool del costo per elemento (`itemCostPool/`, tutti
/// unici) ed elementi anomali (`anomalous/`). Ogni cartella ha un indice TSV in `indexes/` e il
/// tutto è descritto da `dataset-manifest.json`.
public struct DatasetGenerator: Sendable {
  public let config: DatasetConfig
  public let configDigest: String
  public let plan: DatasetPlan
  public let outputDirectory: URL
  public let force: Bool
  private let log: @Sendable (String) -> Void

  public init(
    configURL: URL, profile: DatasetProfile, outputDirectory: URL, force: Bool,
    log: @escaping @Sendable (String) -> Void = { print($0) }
  ) throws {
    let data = try Data(contentsOf: configURL)
    config = try JSONDecoder().decode(DatasetConfig.self, from: data)
    configDigest = DatasetManifest.sha256Hex(data)
    plan = config.plan(for: profile)
    self.outputDirectory = outputDirectory.standardizedFileURL
    self.force = force
    self.log = log
  }

  // MARK: - Pre-volo

  /// Controllo preventivo dello spazio: fallisce se lo spazio libero è inferiore a 1,3 volte la
  /// stima. È una funzione pura, così il rifiuto è verificabile con una disponibilità iniettata.
  public static func preflight(estimatedBytes: Int64, availableBytes: Int64) throws {
    let required = Int64((Double(estimatedBytes) * 1.3).rounded(.up))
    guard availableBytes >= required else {
      throw DatasetGenerationError.insufficientSpace(
        estimated: estimatedBytes, available: availableBytes, required: required)
    }
  }

  /// Spazio disponibile sul volume che conterrà `url`, risalendo al primo antenato esistente.
  public static func availableCapacity(for url: URL) throws -> Int64 {
    var candidate = url.standardizedFileURL
    while !FileManager.default.fileExists(atPath: candidate.path) {
      let parent = candidate.deletingLastPathComponent()
      guard parent.path != candidate.path else { break }
      candidate = parent
    }
    let values = try candidate.resourceValues(forKeys: [
      .volumeAvailableCapacityForImportantUsageKey
    ])
    guard let available = values.volumeAvailableCapacityForImportantUsage else {
      throw DatasetGenerationError.capacityUnavailable(candidate.path)
    }
    return available
  }

  // MARK: - Generazione

  /// Genera il dataset e restituisce il manifest scritto su disco.
  public func generate() async throws -> DatasetManifest {
    let clock = ContinuousClock()
    let started = clock.now
    let fileManager = FileManager.default

    try prepareOutputDirectory()

    let estimated = plan.estimatedRequiredBytes
    let available = try Self.availableCapacity(for: outputDirectory)
    log(
      "pre-volo: stima \(Self.gigabytes(estimated)), disponibile \(Self.gigabytes(available)), "
        + "richiesto almeno \(Self.gigabytes(Int64(Double(estimated) * 1.3)))")
    try Self.preflight(estimatedBytes: estimated, availableBytes: available)

    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let cloneSupported = probeCloneSupport()
    if !cloneSupported {
      log(
        "AVVISO: il volume di uscita non accetta clonefile(2); i cloni della cartella di "
          + "scorrimento saranno copie piene e occuperanno spazio reale.")
    }

    let calibrations = try await calibrate()

    let layout = makeLayout(calibrations: calibrations)
    for folder in layout.folders {
      try fileManager.createDirectory(
        at: outputDirectory.appending(path: folder.name, directoryHint: .isDirectory),
        withIntermediateDirectories: true)
    }
    log("generazione di \(layout.uniqueJobs.count) file unici …")
    let sizes = try await encodeUniqueFiles(layout.uniqueJobs)
    log("clonazione di \(layout.cloneJobs.count) file …")
    let cloneSizes = try cloneFiles(layout.cloneJobs, supported: cloneSupported, sizes: sizes)
    let allSizes = sizes.merging(cloneSizes) { first, _ in first }

    let indexDirectory = outputDirectory.appending(path: "indexes", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
    var folders: [String: DatasetManifest.Folder] = [:]
    for folder in layout.folders {
      let indexFile = "indexes/\(folder.name).tsv"
      try DatasetIndex.encode(folder.entries).write(
        to: outputDirectory.appending(path: indexFile), atomically: true, encoding: .utf8)
      folders[folder.name] = summarize(
        folder, indexFile: indexFile, sizes: allSizes, calibrations: calibrations)
    }

    let scroll = folders[plan.scrollFolder.name]!
    let manifest = DatasetManifest(
      schema: DatasetManifest.schemaIdentifier, configDigest: configDigest, seed: plan.seed,
      profile: plan.profile, generatedAt: Date(),
      generationSeconds: Self.seconds(clock.now - started), cloneSupported: cloneSupported,
      tolerance: plan.tolerance,
      totals: .init(
        total: scroll.fileCount, uniqueTotal: scroll.uniqueCount, cloneTotal: scroll.cloneCount,
        bytesTotal: scroll.bytesTotal),
      cells: scroll.cells,
      calibration: calibrations.keys.sorted().map { cell in
        let calibration = calibrations[cell]!
        return .init(
          format: cell.format, resolutionClass: cell.resolutionClass.rawValue,
          pixels: plan.pixels(for: cell), quality: calibration.quality,
          sampleBytesPerMegapixel: calibration.sampleBytesPerMegapixel,
          iterations: calibration.iterations)
      },
      folders: .init(
        scroll: scroll, firstScreen: plan.firstScreenFolderNames.map { folders[$0]! },
        itemCostPool: folders[Self.itemCostFolder]!, anomalous: folders[Self.anomalousFolder]!))

    for folder in [scroll] + manifest.folders.firstScreen + [manifest.folders.itemCostPool] {
      for cell in folder.cells where cell.toleranceMiss {
        log(
          "AVVISO: \(folder.name) \(cell.format.rawValue)/\(cell.resolutionClass) fuori tolleranza: "
            + String(
              format: "%.3f MB/MP ottenuti contro %.3f dichiarati (±%.0f%%)",
              cell.bytesPerMegapixelAchieved, cell.bytesPerMegapixelTarget, plan.tolerance * 100))
      }
    }

    let manifestURL = outputDirectory.appending(path: DatasetManifest.fileName)
    try DatasetManifest.encoder().encode(manifest).write(to: manifestURL, options: .atomic)
    log(
      "dataset \(plan.profile.rawValue) generato in \(String(format: "%.1f", manifest.generationSeconds)) s: "
        + "scorrimento \(manifest.totals.total) file (\(manifest.totals.uniqueTotal) unici, "
        + "\(manifest.totals.cloneTotal) cloni), \(manifest.folders.firstScreen.count) cartelle "
        + "di prima schermata, manifest in \(manifestURL.path)")
    return manifest
  }

  // MARK: - Struttura del dataset

  static let itemCostFolder = "itemCostPool"
  static let anomalousFolder = "anomalous"

  struct UniqueJob: Sendable {
    let relativePath: String
    let format: ImageFormat
    let pixels: PixelSize
    let contentKey: String
    let quality: Double?
  }

  struct CloneJob: Sendable {
    let relativePath: String
    let sourceRelativePath: String
  }

  struct FolderLayout: Sendable {
    let name: String
    let role: String
    let entries: [DatasetIndexEntry]
  }

  struct Layout: Sendable {
    var folders: [FolderLayout] = []
    var uniqueJobs: [UniqueJob] = []
    var cloneJobs: [CloneJob] = []
  }

  private func makeLayout(calibrations: [DatasetCell: ImageSynthesis.Calibration]) -> Layout {
    var layout = Layout()

    // a. Cartelle di prima schermata: tutte uniche, disgiunte, nomi mescolati.
    for (runIndex, name) in plan.firstScreenFolderNames.enumerated() {
      var specs: [(cell: DatasetCell, ordinal: Int)] = []
      for cell in DatasetCell.all {
        for ordinal in 0..<plan.firstScreenFolders.distribution.count(for: cell) {
          specs.append((cell, ordinal))
        }
      }
      var rng = SplitMix64(seed: ImageSynthesis.contentSeed(base: plan.seed, key: "order:\(name)"))
      specs.shuffle(using: &rng)
      var entries: [DatasetIndexEntry] = []
      for (position, spec) in specs.enumerated() {
        let fileName = String(format: "IMG_%05d.", position + 1) + spec.cell.format.fileExtension
        let pixels = plan.pixels(for: spec.cell)
        entries.append(
          DatasetIndexEntry(
            name: fileName, format: spec.cell.format,
            resolutionClass: spec.cell.resolutionClass.rawValue, pixels: pixels, isClone: false,
            cloneSource: nil))
        layout.uniqueJobs.append(
          UniqueJob(
            relativePath: "\(name)/\(fileName)", format: spec.cell.format, pixels: pixels,
            contentKey: "firstScreen:\(runIndex + 1):\(spec.cell):\(spec.ordinal)",
            quality: calibrations[spec.cell]?.quality))
      }
      layout.folders.append(FolderLayout(name: name, role: "firstScreen", entries: entries))
    }

    // b. Cartella di scorrimento: unici per cella, poi cloni fino al conteggio dichiarato.
    let scrollName = plan.scrollFolder.name
    var scrollSpecs: [(cell: DatasetCell, ordinal: Int)] = []
    for cell in DatasetCell.all {
      for ordinal in 0..<plan.scrollFolder.distribution.count(for: cell) {
        scrollSpecs.append((cell, ordinal))
      }
    }
    var scrollRng = SplitMix64(
      seed: ImageSynthesis.contentSeed(base: plan.seed, key: "order:\(scrollName)"))
    scrollSpecs.shuffle(using: &scrollRng)
    var nameOf: [DatasetCell: [Int: String]] = [:]
    for (position, spec) in scrollSpecs.enumerated() {
      nameOf[spec.cell, default: [:]][spec.ordinal] =
        String(format: "IMG_%05d.", position + 1) + spec.cell.format.fileExtension
    }
    var scrollEntries: [DatasetIndexEntry] = []
    for spec in scrollSpecs {
      let fileName = nameOf[spec.cell]![spec.ordinal]!
      let pixels = plan.pixels(for: spec.cell)
      let uniqueCount = plan.scrollUniqueCount(for: spec.cell)
      if spec.ordinal < uniqueCount {
        scrollEntries.append(
          DatasetIndexEntry(
            name: fileName, format: spec.cell.format,
            resolutionClass: spec.cell.resolutionClass.rawValue, pixels: pixels, isClone: false,
            cloneSource: nil))
        layout.uniqueJobs.append(
          UniqueJob(
            relativePath: "\(scrollName)/\(fileName)", format: spec.cell.format, pixels: pixels,
            contentKey: "scroll:\(spec.cell):\(spec.ordinal)",
            quality: calibrations[spec.cell]?.quality))
      } else {
        // Il clone k della cella copia il file unico di ordinale k mod uniqueCount.
        let source = nameOf[spec.cell]![spec.ordinal % uniqueCount]!
        scrollEntries.append(
          DatasetIndexEntry(
            name: fileName, format: spec.cell.format,
            resolutionClass: spec.cell.resolutionClass.rawValue, pixels: pixels, isClone: true,
            cloneSource: source))
        layout.cloneJobs.append(
          CloneJob(
            relativePath: "\(scrollName)/\(fileName)",
            sourceRelativePath: "\(scrollName)/\(source)"))
      }
    }
    layout.folders.append(FolderLayout(name: scrollName, role: "scroll", entries: scrollEntries))

    // c. Pool del costo per elemento: tutti unici, nomi per cella.
    var poolEntries: [DatasetIndexEntry] = []
    for cell in DatasetCell.all {
      let pixels = plan.pixels(for: cell)
      for ordinal in 0..<plan.itemCostPool.uniquePerCell {
        let fileName =
          "\(cell.format.rawValue)-\(cell.resolutionClass.rawValue)-"
          + String(format: "%03d.", ordinal + 1) + cell.format.fileExtension
        poolEntries.append(
          DatasetIndexEntry(
            name: fileName, format: cell.format, resolutionClass: cell.resolutionClass.rawValue,
            pixels: pixels, isClone: false, cloneSource: nil))
        layout.uniqueJobs.append(
          UniqueJob(
            relativePath: "\(Self.itemCostFolder)/\(fileName)", format: cell.format,
            pixels: pixels, contentKey: "itemCost:\(cell):\(ordinal)",
            quality: calibrations[cell]?.quality))
      }
    }
    layout.folders.append(
      FolderLayout(name: Self.itemCostFolder, role: "itemCost", entries: poolEntries))

    // d. Elementi anomali, codificati senza calibrazione (TIFF senza compressione).
    var anomalousEntries: [DatasetIndexEntry] = []
    for item in plan.anomalousItems {
      for ordinal in 0..<item.count {
        let fileName =
          "\(item.format.rawValue)-\(item.pixels)-\(ordinal + 1)." + item.format.fileExtension
        anomalousEntries.append(
          DatasetIndexEntry(
            name: fileName, format: item.format, resolutionClass: "anomalous",
            pixels: item.pixels, isClone: false, cloneSource: nil))
        layout.uniqueJobs.append(
          UniqueJob(
            relativePath: "\(Self.anomalousFolder)/\(fileName)", format: item.format,
            pixels: item.pixels, contentKey: "anomalous:\(item.format):\(item.pixels):\(ordinal)",
            quality: item.format.isLossy ? 0.9 : nil))
      }
    }
    layout.folders.append(
      FolderLayout(name: Self.anomalousFolder, role: "anomalous", entries: anomalousEntries))
    return layout
  }

  // MARK: - Fasi

  private func prepareOutputDirectory() throws {
    let fileManager = FileManager.default
    let manifestURL = outputDirectory.appending(path: DatasetManifest.fileName)
    let generatedNames =
      [
        DatasetManifest.fileName, plan.scrollFolder.name, Self.itemCostFolder,
        Self.anomalousFolder, "indexes", ".bench-touched",
      ]
    let existing = (try? fileManager.contentsOfDirectory(atPath: outputDirectory.path)) ?? []
    let ours = existing.filter { name in
      generatedNames.contains(name) || name.hasPrefix("p1-run-")
    }
    guard !ours.isEmpty else { return }
    guard force else {
      throw DatasetGenerationError.outputNotEmpty(
        path: outputDirectory.path, manifestExists: fileManager.fileExists(atPath: manifestURL.path)
      )
    }
    for name in ours {
      try fileManager.removeItem(at: outputDirectory.appending(path: name))
    }
    log("--force: rimossi \(ours.count) elementi generati in precedenza da \(outputDirectory.path)")
  }

  private func probeCloneSupport() -> Bool {
    let source = outputDirectory.appending(path: ".clone-probe-source")
    let destination = outputDirectory.appending(path: ".clone-probe-clone")
    defer {
      try? FileManager.default.removeItem(at: source)
      try? FileManager.default.removeItem(at: destination)
    }
    try? FileManager.default.removeItem(at: destination)
    guard (try? Data(repeating: 0xA5, count: 16_384).write(to: source)) != nil else { return false }
    return clonefile(source.path, destination.path, 0) == 0
  }

  private func calibrate() async throws -> [DatasetCell: ImageSynthesis.Calibration] {
    let plan = plan
    log("calibrazione della qualità di codifica per \(DatasetCell.all.count) celle …")
    return try await withThrowingTaskGroup(
      of: (DatasetCell, ImageSynthesis.Calibration).self
    ) { group in
      for cell in DatasetCell.all {
        group.addTask {
          let calibration = try ImageSynthesis.calibrate(
            format: cell.format, pixels: plan.pixels(for: cell),
            target: plan.target(for: cell.format), tolerance: plan.tolerance,
            seed: ImageSynthesis.contentSeed(base: plan.seed, key: "calibration:\(cell)"))
          return (cell, calibration)
        }
      }
      var result: [DatasetCell: ImageSynthesis.Calibration] = [:]
      for try await (cell, calibration) in group {
        result[cell] = calibration
      }
      return result
    }
  }

  /// Codifica i file unici con un `TaskGroup` a larghezza limitata al numero di processori.
  private func encodeUniqueFiles(_ jobs: [UniqueJob]) async throws -> [String: Int64] {
    let outputDirectory = outputDirectory
    let seed = plan.seed
    let width = max(1, ProcessInfo.processInfo.activeProcessorCount)
    let clock = ContinuousClock()
    let started = clock.now
    return try await withThrowingTaskGroup(of: (String, Int64).self) { group in
      var sizes: [String: Int64] = [:]
      var next = 0
      func enqueue() {
        guard next < jobs.count else { return }
        let job = jobs[next]
        next += 1
        group.addTask {
          let url = outputDirectory.appending(path: job.relativePath)
          try autoreleasepool {
            let image = ImageSynthesis.makeImage(
              width: job.pixels.width, height: job.pixels.height,
              seed: ImageSynthesis.contentSeed(base: seed, key: job.contentKey))
            try ImageSynthesis.write(image, format: job.format, quality: job.quality, to: url)
          }
          let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
          return (job.relativePath, Int64(size))
        }
      }
      for _ in 0..<width { enqueue() }
      var completed = 0
      for try await (path, size) in group {
        sizes[path] = size
        completed += 1
        if completed % 500 == 0 {
          log(
            "  \(completed)/\(jobs.count) file unici in "
              + String(format: "%.0f s", Self.seconds(clock.now - started)))
        }
        enqueue()
      }
      return sizes
    }
  }

  private func cloneFiles(_ jobs: [CloneJob], supported: Bool, sizes: [String: Int64]) throws
    -> [String: Int64]
  {
    var result: [String: Int64] = [:]
    var warnedFallback = false
    for job in jobs {
      let source = outputDirectory.appending(path: job.sourceRelativePath)
      let destination = outputDirectory.appending(path: job.relativePath)
      if !supported || clonefile(source.path, destination.path, 0) != 0 {
        if supported && !warnedFallback {
          log("AVVISO: clonefile fallito (errno \(errno)); ricado sulla copia piena.")
          warnedFallback = true
        }
        try FileManager.default.copyItem(at: source, to: destination)
      }
      result[job.relativePath] = sizes[job.sourceRelativePath] ?? 0
    }
    return result
  }

  private func summarize(
    _ folder: FolderLayout, indexFile: String, sizes: [String: Int64],
    calibrations: [DatasetCell: ImageSynthesis.Calibration]
  ) -> DatasetManifest.Folder {
    var cells: [DatasetManifest.Cell] = []
    let groups = Dictionary(grouping: folder.entries) {
      "\($0.format.rawValue)|\($0.resolutionClass)|\($0.pixels)"
    }
    for entries in groups.values {
      let first = entries[0]
      let unique = entries.filter { !$0.isClone }
      let bytes = entries.reduce(Int64(0)) { $0 + (sizes["\(folder.name)/\($1.name)"] ?? 0) }
      let uniqueBytes = unique.reduce(Int64(0)) { $0 + (sizes["\(folder.name)/\($1.name)"] ?? 0) }
      let target = plan.target(for: first.format)
      let achieved =
        unique.isEmpty
        ? 0 : Double(uniqueBytes) / 1_000_000 / (Double(unique.count) * first.pixels.megapixels)
      let cell = ResolutionClass(rawValue: first.resolutionClass).map {
        DatasetCell(format: first.format, resolutionClass: $0)
      }
      let quality = cell.flatMap { calibrations[$0]?.quality }
      cells.append(
        DatasetManifest.Cell(
          format: first.format, resolutionClass: first.resolutionClass, pixels: first.pixels,
          uniqueCount: unique.count, cloneCount: entries.count - unique.count,
          totalCount: entries.count, bytesTotal: bytes, uniqueBytesTotal: uniqueBytes,
          bytesPerMegapixelTarget: target, bytesPerMegapixelAchieved: achieved,
          encoderQuality: first.resolutionClass == "anomalous" && first.format.isLossy
            ? 0.9 : quality,
          toleranceMiss: abs(achieved - target) > target * plan.tolerance))
    }
    cells.sort { lhs, rhs in
      (lhs.format, Self.classOrder(lhs.resolutionClass))
        < (rhs.format, Self.classOrder(rhs.resolutionClass))
    }
    let uniqueCount = cells.reduce(0) { $0 + $1.uniqueCount }
    return DatasetManifest.Folder(
      name: folder.name, role: folder.role, fileCount: folder.entries.count,
      uniqueCount: uniqueCount, cloneCount: folder.entries.count - uniqueCount,
      bytesTotal: cells.reduce(Int64(0)) { $0 + $1.bytesTotal }, indexFile: indexFile,
      cells: cells)
  }

  private static func classOrder(_ label: String) -> Int {
    ResolutionClass(rawValue: label).flatMap { ResolutionClass.allCases.firstIndex(of: $0) }
      ?? ResolutionClass.allCases.count
  }

  static func seconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1e18
  }

  static func gigabytes(_ bytes: Int64) -> String {
    String(format: "%.1f GB", Double(bytes) / 1e9)
  }
}

/// Errori del generatore, con messaggi che dicono cosa fare.
public enum DatasetGenerationError: Error, CustomStringConvertible, Equatable {
  case insufficientSpace(estimated: Int64, available: Int64, required: Int64)
  case capacityUnavailable(String)
  case outputNotEmpty(path: String, manifestExists: Bool)

  public var description: String {
    switch self {
    case .insufficientSpace(let estimated, let available, let required):
      "spazio insufficiente: stima \(DatasetGenerator.gigabytes(estimated)) (\(estimated) byte), "
        + "disponibile \(DatasetGenerator.gigabytes(available)) (\(available) byte), richiesto "
        + "almeno \(DatasetGenerator.gigabytes(required)) (stima × 1,3). Libera spazio oppure "
        + "riduci firstScreenFolders.count in dataset.json, documentando la riduzione in RESULT.md."
    case .capacityUnavailable(let path):
      "impossibile leggere lo spazio disponibile per \(path)"
    case .outputNotEmpty(let path, let manifestExists):
      "la directory \(path) contiene già un dataset"
        + (manifestExists ? " (con manifest)" : "") + ": usa --force per rigenerarlo"
    }
  }
}
