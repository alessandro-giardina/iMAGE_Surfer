import AppKit

/// `bench retention-band`: spazzolamento delle soglie della banda di ritenzione (NFR-P6,
/// NFR-P12, AC-5).
///
/// Per ogni coppia `enterBand ∈ {0,5; 1; 2; 3; 4}` × `exitBand = enterBand + delta`,
/// `delta ∈ {0,5; 1; 2}` porta la vista al centro di `scroll-50k`, attende il regime, poi misura
/// quante anteprime vengono ricalcolate da un'oscillazione piccola (±0,25 schermate, 10 cicli) e
/// media (±1 schermata, 10 cicli). La coppia raccomandata è la più piccola che azzera il ricalcolo
/// sull'oscillazione piccola. Come riferimento misura anche la banda **senza isteresi**
/// (`exitBand == enterBand`), cioè il rilascio immediato che la banda evita.
@MainActor
public final class RetentionBandBench {
  public static let name = "retention-band"
  static let enterBands = [0.5, 1, 2, 3, 4]
  static let deltas = [0.5, 1, 2]
  /// Riferimenti senza isteresi (`exitBand == enterBand`): zero e ogni soglia di entrata.
  static let referenceBands = [0.0] + enterBands
  /// Righe supplementari con `delta = 0,25`, il caso limite rispetto all'oscillazione piccola.
  static let supplementaryDelta = 0.25

  private let options: BenchOptions
  private let dataset: LoadedDataset

  public init(options: BenchOptions) throws {
    self.options = options
    dataset = try LoadedDataset.load(options)
  }

  public func run() async throws -> MeasurementResult {
    let startedAt = Date()
    let speed = try options.extra.double("scroll-speed", default: 3)
    let cycles = try options.extra.int("cycles", default: options.profile == .full ? 10 : 3)
    let host = HostFingerprint.collect(volumeContaining: dataset.directory)
    try host.assertComplete()
    let geometry = GridGeometry(viewport: options.window)
    let queueWidth = host.performanceCores
    let urls = try FolderEnumerator.all(dataset.folderURL(dataset.manifest.folders.scroll.name))

    await BenchHost.warmUp(
      geometry: geometry, scale: options.thumbnailScale, queueWidth: queueWidth)
    let benchHost = BenchHost(geometry: geometry)
    await benchHost.show()
    benchHost.setURLs(urls)
    let pipeline = ThumbnailPipeline(
      path: options.thumbnailPath, width: queueWidth, side: geometry.itemSide,
      scale: options.thumbnailScale)
    let center = benchHost.maxOffset / 2

    var rows: [Repetition] = []
    for enter in Self.enterBands {
      for delta in Self.deltas {
        let thermalAtStart = ThermalState.current
        let flags = RepetitionEnvironment.flags()
        let row = try await measure(
          enter: enter, exit: enter + delta, host: benchHost, pipeline: pipeline,
          center: center, speed: speed, cycles: cycles)
        rows.append(
          Repetition(
            index: rows.count, values: row, flags: flags, thermalStateAtStart: thermalAtStart,
            thermalStateAtEnd: .current))
        print(
          String(
            format:
              "  entrata %.1f, uscita %.1f: regime %.1f MB, rigenerate %.0f (±0,25) e %.0f (±1)",
            enter, enter + delta, (row["steadyFootprintBytes"] ?? 0) / 1e6,
            row["regeneratedSmall"] ?? 0, row["regeneratedMedium"] ?? 0))
      }
    }
    var references: [JSONValue] = []
    for band in Self.referenceBands {
      let row = try await measure(
        enter: band, exit: band, host: benchHost, pipeline: pipeline, center: center,
        speed: speed, cycles: cycles)
      references.append(.object(row.mapValues(JSONValue.number)))
      print(
        String(
          format: "  riferimento senza isteresi %.1f/%.1f: rigenerate %.0f (±0,25) e %.0f (±1)",
          band, band, row["regeneratedSmall"] ?? 0, row["regeneratedMedium"] ?? 0))
    }
    var supplementary: [JSONValue] = []
    for enter in Self.enterBands {
      let row = try await measure(
        enter: enter, exit: enter + Self.supplementaryDelta, host: benchHost, pipeline: pipeline,
        center: center, speed: speed, cycles: cycles)
      supplementary.append(.object(row.mapValues(JSONValue.number)))
      print(
        String(
          format: "  supplementare %.1f/%.2f: rigenerate %.0f (±0,25) e %.0f (±1)",
          enter, enter + Self.supplementaryDelta, row["regeneratedSmall"] ?? 0,
          row["regeneratedMedium"] ?? 0))
    }
    let visibleAtEnd = benchHost.isVisibleOnScreen
    await pipeline.drain()
    benchHost.close()

    var parameters = geometry.parameters
    parameters.merge(benchHost.screenParameters) { first, _ in first }
    parameters["thumbnailPath"] = options.thumbnailPath.rawValue
    parameters["thumbnailScale"] = "\(options.thumbnailScale)"
    parameters["queueWidth"] = "\(queueWidth)"
    parameters["scrollSpeedScreensPerSecond"] = "\(speed)"
    parameters["cycles"] = "\(cycles)"
    parameters["items"] = "\(urls.count)"
    parameters["position"] = "centro della cartella"
    parameters["smallOscillation"] = "±0,25 schermate"
    parameters["mediumOscillation"] = "±1 schermata"
    parameters["enterBands"] = Self.enterBands.map { "\($0)" }.joined(separator: ",")
    parameters["deltas"] = Self.deltas.map { "\($0)" }.joined(separator: ",")
    let recommendation = Self.recommend(rows)
    return MeasurementResult(
      bench: Self.name, startedAt: startedAt, finishedAt: Date(),
      profile: options.profile.rawValue, datasetManifestDigest: dataset.manifestDigest,
      host: host, parameters: parameters, repetitions: rows,
      derived: [
        "recommendation": recommendation.value,
        "recommendationReason": .string(recommendation.reason),
        "recommendationRule":
          .string(
            "la coppia con regeneratedSmall == 0 e soglia di uscita minima, a parità la soglia "
              + "di entrata minima"),
        "noHysteresisReference": .array(references),
        "supplementaryRows": .array(supplementary),
        "supplementaryNote": .string(
          "righe con exitBand = enterBand + 0,25, fuori dallo spazzolamento dichiarato: "
            + "mostrano dove l'oscillazione di ±0,25 comincia a rigenerare"),
        "geometryNote": .string(
          "con delta >= 0,5 un'oscillazione di ±0,25 (escursione 0,5 schermate) non può portare "
            + "un elemento oltre la soglia di uscita: regeneratedSmall = 0 è atteso per "
            + "costruzione; la motivazione misurata viene dai riferimenti senza isteresi"),
        "windowVisibleAtEnd": .bool(visibleAtEnd),
      ])
  }

  /// La più piccola coppia che azzera il ricalcolo sull'oscillazione piccola, oppure `null` con
  /// il motivo. Un esito nullo è legittimo e non va aggirato allargando lo spazzolamento.
  static func recommend(_ rows: [Repetition]) -> (value: JSONValue, reason: String) {
    let candidates = rows.filter { $0.values["regeneratedSmall"] == 0 }
      .sorted {
        ($0.values["exitBand"]!, $0.values["enterBand"]!)
          < ($1.values["exitBand"]!, $1.values["enterBand"]!)
      }
    guard let best = candidates.first else {
      return (
        .null,
        "nessuna delle \(rows.count) coppie azzera le anteprime ricalcolate sull'oscillazione di "
          + "±0,25 schermate"
      )
    }
    return (
      .object(best.values.mapValues(JSONValue.number)),
      "\(candidates.count) coppie su \(rows.count) azzerano il ricalcolo sull'oscillazione "
        + "piccola; scelta quella con soglia di uscita minima"
    )
  }

  private func measure(
    enter: Double, exit: Double, host: BenchHost, pipeline: ThumbnailPipeline, center: CGFloat,
    speed: Double, cycles: Int
  ) async throws -> [String: Double] {
    let band = RetentionBand(host: host, pipeline: pipeline, enterBand: enter, exitBand: exit)
    defer { band.clear() }
    // Il campionatore riserva la propria memoria alla costruzione: prima di ogni baseline.
    let sampler = FootprintSampler(intervalMs: 50, reservedSamples: 20_000)
    var ticks: [ScrollDriver.Tick] = []
    ticks.reserveCapacity(4_096)
    host.scroll(to: center)
    band.update()
    try await ScrollDriver.waitForSteady(band, timeout: .seconds(300))
    let steady = await ScrollDriver.steadyFootprint()
    let retained = band.retainedCount

    var row: [String: Double] = [
      "enterBand": enter, "exitBand": exit, "steadyFootprintBytes": Double(steady),
      "retainedCount": Double(retained),
    ]
    for (label, amplitude) in [("Small", 0.25), ("Medium", 1.0)] {
      band.resetCounters()
      sampler.start(baseline: steady)
      let start = BenchClock.now()
      let swing = CGFloat(amplitude) * host.screenHeight
      for _ in 0..<cycles {
        await ScrollDriver.scroll(
          host, band: band, to: center + swing, screensPerSecond: speed, ticks: &ticks)
        await ScrollDriver.scroll(
          host, band: band, to: center - swing, screensPerSecond: speed, ticks: &ticks)
      }
      await ScrollDriver.scroll(
        host, band: band, to: center, screensPerSecond: speed, ticks: &ticks)
      let scrolled = BenchClock.now()
      try await ScrollDriver.waitForSteady(band, timeout: .seconds(300))
      let end = BenchClock.now()
      let trace = sampler.stop()
      ticks.removeAll(keepingCapacity: true)
      row["regenerated\(label)"] = Double(band.regeneratedCount)
      row["produced\(label)"] = Double(band.producedCount)
      row["cancelled\(label)"] = Double(band.cancelledCount)
      row["oscillationScroll\(label)Ms"] = BenchClock.milliseconds(from: start, to: scrolled)
      row["oscillationTotal\(label)Ms"] = BenchClock.milliseconds(from: start, to: end)
      // Costo di parete della rigenerazione: il tempo che la pipeline impiega, finito lo
      // scorrimento (di durata fissa), per tornare a regime.
      row["regenerationWallClock\(label)Ms"] = BenchClock.milliseconds(from: scrolled, to: end)
      row["regenerationMemory\(label)Bytes"] = Double(max(0, trace.peakAboveBaseline))
    }
    row["regenerationWallClockMs"] = row["regenerationWallClockSmallMs"]
    return row
  }
}
