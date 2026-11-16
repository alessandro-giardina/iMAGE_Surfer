import AppKit
import QuartzCore

/// `bench first-screen`: tempo alla prima schermata di anteprime su una cartella da 3.000 immagini
/// (NFR-P1).
///
/// Ogni ripetizione usa una cartella di prima schermata diversa e mai letta prima, così parte a
/// cache fredda senza `sudo purge`. Definizioni registrate nel risultato:
/// - `t0`: istante in cui parte l'enumerazione della cartella;
/// - `firstUrlsReadyMs`: i primi `visibleCount` URL sono disponibili;
/// - `thumbnailsReadyMs`: assegnata l'anteprima dell'ultimo elemento che interseca la porta di
///   vista iniziale;
/// - `firstScreenMs`: completamento della transazione Core Animation in cui è stata assegnata
///   quell'ultima anteprima. È la «prima schermata visibile».
@MainActor
public final class FirstScreenBench {
  public static let name = "first-screen"

  private let options: BenchOptions
  private let dataset: LoadedDataset

  public init(options: BenchOptions) throws {
    self.options = options
    dataset = try LoadedDataset.load(options)
  }

  public func run() async throws -> MeasurementResult {
    let startedAt = Date()
    let repetitions = options.repetitions ?? 5
    let folders = try chooseFolders(count: repetitions)
    let host = HostFingerprint.collect(volumeContaining: dataset.directory)
    try host.assertComplete()
    let measurementId = MeasurementResult.newMeasurementId()
    let geometry = GridGeometry(viewport: options.window)
    let queueWidth = host.performanceCores

    // Baseline dell'host vuoto, dopo il riscaldamento dei framework: rientro fra ripetizioni.
    await BenchHost.warmUp(
      geometry: geometry, scale: options.thumbnailScale, queueWidth: queueWidth)
    let baseline = FootprintSampler.physFootprint()
    var results: [Repetition] = []
    var visibleCounts: Set<Int> = []
    var screen: [String: String] = [:]
    for (index, folder) in folders.enumerated() {
      let flags = RepetitionEnvironment.flags()
      let thermalAtStart = ThermalState.current
      let warm = dataset.wasTouched(folder)
      let outcome = try await measureOnce(
        folder: folder, geometry: geometry, queueWidth: queueWidth)
      try dataset.markTouched(folder, measurementId: measurementId)
      visibleCounts.insert(outcome.visibleCount)
      screen = outcome.screen
      let settle = await FootprintSettle.wait(
        toWithin: 0.10, of: baseline, timeout: .seconds(30))
      var repetitionFlags = flags
      repetitionFlags["footprintDidNotSettle"] = !settle.settled
      repetitionFlags["folderPreviouslyRead"] = warm
      repetitionFlags["windowVisible"] = outcome.windowVisible
      results.append(
        Repetition(
          index: index,
          values: [
            "firstUrlsReadyMs": outcome.firstUrlsReadyMs,
            "thumbnailsReadyMs": outcome.thumbnailsReadyMs,
            "firstScreenMs": outcome.firstScreenMs,
            "compositionMs": outcome.firstScreenMs - outcome.thumbnailsReadyMs,
            "visibleCount": Double(outcome.visibleCount),
            "thumbnailFailures": Double(outcome.failures),
            "footprintAfterTeardownBytes": Double(settle.footprint),
          ],
          flags: repetitionFlags, thermalStateAtStart: thermalAtStart,
          thermalStateAtEnd: .current))
      print(
        String(
          format: "  ripetizione %d su %@: prima schermata %.1f ms (anteprime pronte %.1f ms)",
          index + 1, folder, outcome.firstScreenMs, outcome.thumbnailsReadyMs))
    }

    var parameters = geometry.parameters
    parameters["folders"] = folders.joined(separator: ",")
    parameters["thumbnailPath"] = options.thumbnailPath.rawValue
    parameters["queueWidth"] = "\(queueWidth)"
    parameters.merge(screen) { first, _ in first }
    parameters["thumbnailScale"] = "\(options.thumbnailScale)"
    parameters["maxPixelSize"] = "\(Int((geometry.itemSide * options.thumbnailScale).rounded()))"
    parameters["baselineFootprintBytes"] = "\(baseline)"
    parameters["visibleCount"] = visibleCounts.sorted().map(String.init).joined(separator: ",")
    parameters["t0"] = "inizio dell'enumerazione della cartella"
    parameters["frameOracle"] =
      "completamento della transazione Core Animation (CATransaction.setCompletionBlock) "
      + "in cui viene assegnata l'anteprima dell'ultimo elemento che interseca la porta di "
      + "vista iniziale"
    parameters["coldCache"] =
      "una cartella diversa e mai letta per ripetizione; nessun sudo purge"
    return MeasurementResult(
      measurementId: measurementId, bench: Self.name, startedAt: startedAt, finishedAt: Date(),
      profile: options.profile.rawValue, datasetManifestDigest: dataset.manifestDigest,
      host: host, parameters: parameters, repetitions: results)
  }

  /// Sceglie le prime cartelle mai lette; nel profilo `smoke`, o con `--allow-warm`, ripiega su
  /// cartelle già lette segnalandolo nella ripetizione.
  private func chooseFolders(count: Int) throws -> [String] {
    let all = dataset.manifest.folders.firstScreen.map(\.name)
    if let explicit = options.extra["folders"] {
      let requested = explicit.split(separator: ",").map(String.init)
      guard requested.count == count, Set(requested).count == count else {
        throw BenchError.invalidOption(
          "--folders deve elencare \(count) cartelle diverse, una per ripetizione")
      }
      for folder in requested where !all.contains(folder) {
        throw BenchError.invalidOption("cartella di prima schermata sconosciuta: \(folder)")
      }
      let warm = requested.filter { dataset.wasTouched($0) }
      guard warm.isEmpty || options.profile == .smoke || options.allowWarm else {
        throw BenchError.notEnoughColdFolders(
          needed: count, available: requested.filter { !dataset.wasTouched($0) })
      }
      return requested
    }
    let cold = all.filter { !dataset.wasTouched($0) }
    if cold.count >= count { return Array(cold.prefix(count)) }
    guard options.profile == .smoke || options.allowWarm else {
      throw BenchError.notEnoughColdFolders(needed: count, available: cold)
    }
    let ordered = cold + all.filter { dataset.wasTouched($0) }
    guard ordered.count >= count else {
      throw BenchError.invalidOption(
        "richieste \(count) ripetizioni ma il dataset ha \(ordered.count) cartelle di prima "
          + "schermata: ogni ripetizione usa una cartella diversa")
    }
    return Array(ordered.prefix(count))
  }

  private struct Outcome {
    var firstUrlsReadyMs: Double
    var thumbnailsReadyMs: Double
    var firstScreenMs: Double
    var visibleCount: Int
    var failures: Int
    var screen: [String: String]
    var windowVisible = false
  }

  private func measureOnce(folder: String, geometry: GridGeometry, queueWidth: Int) async throws
    -> Outcome
  {
    let host = BenchHost(geometry: geometry)
    await host.show()
    let pipeline = ThumbnailPipeline(
      path: options.thumbnailPath, width: queueWidth, side: geometry.itemSide,
      scale: options.thumbnailScale)
    defer { host.close() }

    let folderURL = dataset.folderURL(folder)
    let analyticVisible = geometry.initialVisibleCount
    let probe = FirstScreenProbe()

    let outcome = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Outcome, any Error>) in
      probe.continuation = continuation
      let t0 = BenchClock.now()
      probe.t0 = t0

      // Enumerazione non bloccante: i primi URL arrivano a blocchi sul thread principale.
      // `DispatchQueue.main` e non `Task`: i blocchi devono arrivare nell'ordine di invio.
      FolderEnumerator.stream(folderURL, firstBatch: analyticVisible) { batch, isFirst in
        DispatchQueue.main.async {
          MainActor.assumeIsolated {
            if isFirst {
              probe.firstUrlsReady = BenchClock.now()
              host.setURLs(batch)
              let visible = host.visibleIndices()
              probe.pending = Set(visible)
              probe.visibleCount = visible.count
              for index in visible {
                let url = host.urls[index]
                pipeline.requestThumbnail(for: url, priority: .high) { image in
                  DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                      probe.deliver(image, index: index, host: host)
                    }
                  }
                }
              }
            } else {
              host.appendURLs(batch)
            }
          }
        }
      }
    }
    await pipeline.drain()
    return Outcome(
      firstUrlsReadyMs: outcome.firstUrlsReadyMs, thumbnailsReadyMs: outcome.thumbnailsReadyMs,
      firstScreenMs: outcome.firstScreenMs, visibleCount: outcome.visibleCount,
      failures: pipeline.failureCount, screen: host.screenParameters,
      windowVisible: host.isVisibleOnScreen)
  }

  /// Stato di una ripetizione, posseduto dal thread principale.
  @MainActor
  private final class FirstScreenProbe {
    var continuation: CheckedContinuation<Outcome, any Error>?
    var t0: UInt64 = 0
    var firstUrlsReady: UInt64 = 0
    var pending: Set<Int> = []
    var visibleCount = 0
    private var timeout: Task<Void, Never>?

    init() {
      timeout = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(120))
        guard let self, let continuation = self.continuation else { return }
        self.continuation = nil
        continuation.resume(
          throwing: BenchError.timeout("prima schermata non completata entro 120 s"))
      }
    }

    func deliver(_ image: CGImage?, index: Int, host: BenchHost) {
      host.assign(image, at: index)
      guard pending.remove(index) != nil, pending.isEmpty, continuation != nil else { return }
      // Ultima anteprima della porta di vista iniziale: l'oracolo è il completamento della
      // transazione Core Animation corrente, quella in cui l'anteprima è stata assegnata.
      let thumbnailsReady = BenchClock.now()
      let t0 = t0
      let firstUrlsReady = firstUrlsReady
      let visibleCount = visibleCount
      CATransaction.setCompletionBlock { [weak self] in
        let firstScreen = BenchClock.now()
        MainActor.assumeIsolated {
          guard let self, let continuation = self.continuation else { return }
          self.continuation = nil
          self.timeout?.cancel()
          continuation.resume(
            returning: Outcome(
              firstUrlsReadyMs: BenchClock.milliseconds(from: t0, to: firstUrlsReady),
              thumbnailsReadyMs: BenchClock.milliseconds(from: t0, to: thumbnailsReady),
              firstScreenMs: BenchClock.milliseconds(from: t0, to: firstScreen),
              visibleCount: visibleCount, failures: 0, screen: [:]))
        }
      }
    }
  }
}

/// Enumerazione di una cartella su un thread di fondo, consegnata a blocchi.
enum FolderEnumerator {
  /// Enumera `folder` (file immagine, senza nascosti) e consegna prima un blocco di
  /// `firstBatch` URL, poi il resto in un secondo blocco.
  static func stream(
    _ folder: URL, firstBatch: Int,
    deliver: @escaping @Sendable (_ batch: [URL], _ isFirst: Bool) -> Void
  ) {
    Thread.detachNewThread {
      let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
      guard
        let enumerator = FileManager.default.enumerator(
          at: folder, includingPropertiesForKeys: keys,
          options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants])
      else {
        deliver([], true)
        return
      }
      var batch: [URL] = []
      var deliveredFirst = false
      for case let url as URL in enumerator
      where ImageFormat(fileExtension: url.pathExtension) != nil {
        batch.append(url)
        if !deliveredFirst && batch.count == firstBatch {
          deliver(batch, true)
          deliveredFirst = true
          batch = []
        }
      }
      deliver(batch, !deliveredFirst)
    }
  }

  /// Enumerazione completa e sincrona, ordinata per nome.
  static func all(_ folder: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
    )
    .filter { ImageFormat(fileExtension: $0.pathExtension) != nil }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }
}
