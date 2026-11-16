import AppKit
import QuartzCore

/// `bench selection-latency`: latenza dello spostamento della selezione mentre il lavoro in
/// sottofondo è attivo (NFR-P3), su `scroll-50k`.
///
/// Prima di misurare satura le code: produzione delle anteprime di tutta la cartella (code `io` e
/// del percorso scelto) e un carico di visione artificiale sugli elementi di classe M (coda
/// `vision`). Poi invia `moves` frecce con `NSApp.postEvent` a cadenza fissa, a serpentina perché
/// la freccia destra non va a capo a fine riga: misurare
/// dall'evento inviato, e non chiamando l'API di selezione, include la contesa del ciclo di
/// eventi. Ogni spostamento è misurato fino al completamento della transazione Core Animation in
/// cui la selezione riflette il nuovo elemento.
@MainActor
public final class SelectionLatencyBench {
  public static let name = "selection-latency"
  static let thresholdMs = 100.0

  private let options: BenchOptions
  private let dataset: LoadedDataset

  public init(options: BenchOptions) throws {
    self.options = options
    dataset = try LoadedDataset.load(options)
  }

  public func run() async throws -> MeasurementResult {
    let startedAt = Date()
    let moves = try options.extra.int("moves", default: options.profile == .full ? 200 : 40)
    let cadenceMs = try options.extra.int("cadence-ms", default: 150)
    let host = HostFingerprint.collect(volumeContaining: dataset.directory)
    try host.assertComplete()
    let geometry = GridGeometry(viewport: options.window)
    let queueWidth = host.performanceCores

    let scrollFolder = dataset.manifest.folders.scroll
    let urls = try FolderEnumerator.all(dataset.folderURL(scrollFolder.name))
    let index = try dataset.index(of: scrollFolder)
    let mediumClass = Set(index.filter { $0.resolutionClass == "M" }.map(\.name))
    guard urls.count > moves else {
      throw BenchError.invalidOption(
        "la cartella ha \(urls.count) file: servono più elementi dei \(moves) spostamenti")
    }

    let benchHost = BenchHost(geometry: geometry)
    await benchHost.show()
    benchHost.setURLs(urls)
    let pipeline = ThumbnailPipeline(
      path: options.thumbnailPath, width: queueWidth, side: geometry.itemSide,
      scale: options.thumbnailScale)
    defer { benchHost.close() }

    // Gli elementi che entrano in vista chiedono la propria anteprima con priorità alta.
    var requested: Set<Int> = []
    func request(_ item: Int, priority: Operation.QueuePriority) {
      guard requested.insert(item).inserted else { return }
      pipeline.requestThumbnail(for: urls[item], priority: priority) { image in
        DispatchQueue.main.async {
          MainActor.assumeIsolated {
            // Solo gli elementi in vista trattengono l'anteprima: 50.000 anteprime non entrano
            // in memoria, ed è il lavoro di consegna al thread principale che conta qui.
            if benchHost.distanceInScreens(ofRow: benchHost.row(of: item)) == 0 {
              benchHost.assign(image, at: item)
            }
          }
        }
      }
    }
    benchHost.onCellShown = { item in request(item, priority: .high) }
    for item in benchHost.visibleIndices() { request(item, priority: .high) }

    // Saturazione: anteprime di tutta la cartella e visione sugli elementi di classe M.
    for item in urls.indices { request(item, priority: .low) }
    for url in urls where mediumClass.contains(url.lastPathComponent) {
      pipeline.requestVision(for: url)
    }
    let usedQueues: [PipelineQueueKind] = [.io, options.thumbnailPath.queue, .vision]
    let saturatedAt = try await waitForSaturation(pipeline, queues: usedQueues, width: queueWidth)

    // Selezione iniziale sul primo elemento, finestra chiave e vista della collezione in ascolto.
    benchHost.window.makeKeyAndOrderFront(nil)
    benchHost.window.makeFirstResponder(benchHost.collectionView)
    benchHost.collectionView.selectItems(
      at: [IndexPath(item: 0, section: 0)], scrollPosition: .top)
    await benchHost.nextFrame()

    let visibleAtStart = benchHost.isVisibleOnScreen
    let probe = SelectionProbe()
    benchHost.onSelectionChanged = { selection in probe.selectionChanged(selection) }
    var repetitions: [Repetition] = []
    var current = 0
    for move in 0..<moves {
      try? await Task.sleep(for: .milliseconds(cadenceMs))
      let thermalAtStart = ThermalState.current
      let arrow = Self.serpentineStep(from: current, columns: geometry.columns)
      let expected = current + arrow.delta(columns: geometry.columns)
      let timing = try await probe.measure(expected: expected) {
        Self.post(arrow, to: benchHost.window)
      }
      current = expected
      repetitions.append(
        Repetition(
          index: move,
          values: [
            "selectionLatencyMs": timing.frameMs,
            "selectionHandledMs": timing.handledMs,
          ],
          flags: [
            "overThreshold": timing.frameMs > Self.thresholdMs,
            "rightArrow": arrow == .right, "leftArrow": arrow == .left, "downArrow": arrow == .down,
          ],
          thermalStateAtStart: thermalAtStart, thermalStateAtEnd: .current))
    }
    let depthsAtEnd = pipeline.depths()
    let visibleAtEnd = benchHost.isVisibleOnScreen
    await pipeline.drain()

    let over = repetitions.filter { ($0.values["selectionLatencyMs"] ?? 0) > Self.thresholdMs }
    var parameters = geometry.parameters
    parameters.merge(benchHost.screenParameters) { first, _ in first }
    parameters["thumbnailScale"] = "\(options.thumbnailScale)"
    parameters["thumbnailPath"] = options.thumbnailPath.rawValue
    parameters["queueWidth"] = "\(queueWidth)"
    parameters["moves"] = "\(moves)"
    parameters["cadenceMs"] = "\(cadenceMs)"
    parameters["folder"] = scrollFolder.name
    parameters["items"] = "\(urls.count)"
    parameters["visionItems"] = "\(mediumClass.count)"
    parameters["event"] =
      "NSEvent keyDown/keyUp di frecce via NSApp.postEvent, percorso a serpentina: destra lungo "
      + "le righe pari, sinistra lungo le dispari, giù a fine riga (NSCollectionView non va a "
      + "capo con la freccia destra)"
    parameters["frameOracle"] =
      "completamento della transazione Core Animation (CATransaction.setCompletionBlock) in cui "
      + "selectionIndexPaths riflette il nuovo elemento"
    for (kind, depth) in saturatedAt {
      parameters["queueDepthAtStart.\(kind.rawValue)"] = "\(depth)"
    }
    for (kind, depth) in depthsAtEnd { parameters["queueDepthAtEnd.\(kind.rawValue)"] = "\(depth)" }
    let environment = RepetitionEnvironment.flags()
    return MeasurementResult(
      bench: Self.name, startedAt: startedAt, finishedAt: Date(),
      profile: options.profile.rawValue, datasetManifestDigest: dataset.manifestDigest,
      host: host, parameters: parameters, repetitions: repetitions,
      derived: [
        "movesOver100ms": .int(over.count),
        "thresholdMs": .number(Self.thresholdMs),
        "queuesSaturatedAtStart": .bool(true),
        "queueDepthAtStart": .object(
          Dictionary(
            uniqueKeysWithValues: saturatedAt.map { ($0.key.rawValue, JSONValue.int($0.value)) })),
        "queueDepthAtEnd": .object(
          Dictionary(
            uniqueKeysWithValues: depthsAtEnd.map { ($0.key.rawValue, JSONValue.int($0.value)) })),
        "environmentAtEnd": .object(environment.mapValues(JSONValue.bool)),
        "windowVisibleAtStart": .bool(visibleAtStart),
        "windowVisibleAtEnd": .bool(visibleAtEnd),
      ])
  }

  /// Attende che ogni coda usata abbia lavoro in attesa oltre la propria larghezza.
  private func waitForSaturation(
    _ pipeline: ThumbnailPipeline, queues: [PipelineQueueKind], width: Int
  ) async throws -> [PipelineQueueKind: Int] {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(60)
    while clock.now < deadline {
      let depths = pipeline.depths()
      if queues.allSatisfy({ (depths[$0] ?? 0) > width }) { return depths }
      try? await Task.sleep(for: .milliseconds(50))
    }
    throw BenchError.measurementFailed(
      "code non sature entro 60 s: profondità \(pipeline.depths())")
  }

  /// Freccia inviata a ogni spostamento.
  enum Arrow: Equatable {
    case right
    case left
    case down

    var keyCode: UInt16 {
      switch self {
      case .right: 124
      case .left: 123
      case .down: 125
      }
    }

    var functionKey: Int {
      switch self {
      case .right: NSRightArrowFunctionKey
      case .left: NSLeftArrowFunctionKey
      case .down: NSDownArrowFunctionKey
      }
    }

    func delta(columns: Int) -> Int {
      switch self {
      case .right: 1
      case .left: -1
      case .down: columns
      }
    }
  }

  /// Percorso a serpentina: destra sulle righe pari, sinistra sulle dispari, giù a fine riga.
  static func serpentineStep(from item: Int, columns: Int) -> Arrow {
    let row = item / columns
    let column = item % columns
    if row.isMultiple(of: 2) {
      return column < columns - 1 ? .right : .down
    }
    return column > 0 ? .left : .down
  }

  /// Invia una freccia attraverso la coda degli eventi dell'applicazione.
  static func post(_ arrow: Arrow, to window: NSWindow) {
    let characters = String(UnicodeScalar(UInt16(arrow.functionKey))!)
    for type in [NSEvent.EventType.keyDown, .keyUp] {
      let event = NSEvent.keyEvent(
        with: type, location: .zero, modifierFlags: [.numericPad, .function],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, characters: characters, charactersIgnoringModifiers: characters,
        isARepeat: false, keyCode: arrow.keyCode)
      if let event { NSApp.postEvent(event, atStart: false) }
    }
  }

  struct MoveTiming {
    var handledMs: Double
    var frameMs: Double
  }

  /// Misura di un singolo spostamento, posseduta dal thread principale.
  @MainActor
  final class SelectionProbe {
    private var expected = -1
    private var posted: UInt64 = 0
    private var continuation: CheckedContinuation<MoveTiming, any Error>?

    func measure(expected: Int, post: () -> Void) async throws -> MoveTiming {
      try await withCheckedThrowingContinuation { continuation in
        self.expected = expected
        self.continuation = continuation
        let deadline = Task { @MainActor [weak self] in
          try? await Task.sleep(for: .seconds(5))
          guard let self, self.expected == expected, let pending = self.continuation else {
            return
          }
          self.continuation = nil
          pending.resume(
            throwing: BenchError.timeout(
              "la selezione non ha raggiunto l'elemento \(expected) entro 5 s: la finestra "
                + "riceve gli eventi da tastiera? (applicazione attiva e finestra chiave)"))
        }
        _ = deadline
        posted = BenchClock.now()
        post()
      }
    }

    func selectionChanged(_ selection: Set<IndexPath>) {
      guard continuation != nil, selection.contains(IndexPath(item: expected, section: 0)) else {
        return
      }
      let handled = BenchClock.now()
      let posted = posted
      CATransaction.setCompletionBlock { [weak self] in
        let frame = BenchClock.now()
        MainActor.assumeIsolated {
          guard let self, let continuation = self.continuation else { return }
          self.continuation = nil
          continuation.resume(
            returning: MoveTiming(
              handledMs: BenchClock.milliseconds(from: posted, to: handled),
              frameMs: BenchClock.milliseconds(from: posted, to: frame)))
        }
      }
    }
  }
}
