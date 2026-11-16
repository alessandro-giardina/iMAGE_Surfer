import AppKit

/// Scorrimento programmatico della griglia a velocità dichiarata, con la banda aggiornata a ogni
/// passo.
@MainActor
enum ScrollDriver {
  /// Un passo registrato: istante monotono e scostamento verticale.
  struct Tick {
    var time: UInt64
    var offset: CGFloat
  }

  /// Scorre fino a `target` a `screensPerSecond` schermate al secondo. Il passo è calcolato sul
  /// tempo trascorso realmente, così la velocità non dipende dalla cadenza dei fotogrammi.
  /// I passi sono registrati al più a 20 Hz (uno ogni 50 ms, come il campionatore), così la
  /// memoria della strumentazione non cresce in modo apprezzabile durante corse lunghe;
  /// `observe` è chiamato alla stessa cadenza.
  static func scroll(
    _ host: BenchHost, band: RetentionBand, to target: CGFloat, screensPerSecond: Double,
    ticks: inout [Tick], observe: (() -> Void)? = nil
  ) async {
    let destination = min(max(0, target), host.maxOffset)
    var last = BenchClock.now()
    var lastTick: UInt64 = 0
    var stalled = 0
    while abs(host.offset - destination) > 0.5 {
      try? await Task.sleep(for: .milliseconds(8))
      let now = BenchClock.now()
      let step = CGFloat(screensPerSecond) * host.screenHeight * CGFloat(now - last) / 1e9
      last = now
      let before = host.offset
      let next =
        host.offset < destination
        ? min(destination, host.offset + step) : max(destination, host.offset - step)
      host.scroll(to: next)
      band.update()
      if now &- lastTick >= 50_000_000 {
        lastTick = now
        ticks.append(Tick(time: now, offset: host.offset))
        observe?()
      }
      // Una destinazione che la vista non raggiunge (cornice più corta del previsto) non deve
      // bloccare il banco: dopo mezzo secondo senza progresso lo scorrimento si ferma.
      stalled = abs(host.offset - before) < 0.01 ? stalled + 1 : 0
      if stalled > 60 { break }
    }
  }

  /// Attende che la banda non abbia richieste in corso, con scadenza.
  static func waitForSteady(_ band: RetentionBand, timeout: Duration) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while band.inFlightCount > 0 {
      guard clock.now < deadline else {
        throw BenchError.timeout(
          "la banda ha ancora \(band.inFlightCount) anteprime in corso dopo \(timeout)")
      }
      try? await Task.sleep(for: .milliseconds(20))
    }
  }

  /// Mediana di `count` letture del footprint, una ogni 50 ms.
  static func steadyFootprint(count: Int = 20) async -> UInt64 {
    var readings: [Double] = []
    for _ in 0..<count {
      readings.append(Double(FootprintSampler.physFootprint()))
      try? await Task.sleep(for: .milliseconds(50))
    }
    return UInt64(Dispersion(readings)?.median ?? 0)
  }
}

/// Regressione lineare ai minimi quadrati con semiampiezza dell'intervallo al 95% della pendenza.
public enum LinearFit {
  public static func fit(x: [Double], y: [Double]) -> (slope: Double, halfWidth95: Double)? {
    let n = Double(x.count)
    guard x.count == y.count, x.count >= 3 else { return nil }
    let meanX = x.reduce(0, +) / n
    let meanY = y.reduce(0, +) / n
    var sxx = 0.0
    var sxy = 0.0
    for (xi, yi) in zip(x, y) {
      sxx += (xi - meanX) * (xi - meanX)
      sxy += (xi - meanX) * (yi - meanY)
    }
    guard sxx > 0 else { return nil }
    let slope = sxy / sxx
    let intercept = meanY - slope * meanX
    var residuals = 0.0
    for (xi, yi) in zip(x, y) {
      let residual = yi - (intercept + slope * xi)
      residuals += residual * residual
    }
    let standardError = (residuals / (n - 2) / sxx).squareRoot()
    return (slope, 1.96 * standardError)
  }
}

extension Dispersion {
  /// La dispersione come valore JSON, per le grandezze derivate.
  public var json: JSONValue {
    .object([
      "n": .int(n), "min": .number(min), "median": .number(median), "p95": .number(p95),
      "max": .number(max), "mean": .number(mean), "stddev": .number(stddev), "iqr": .number(iqr),
    ])
  }
}

extension FootprintTrace {
  /// Serie ridotta a un punto al secondo (massimo del secondo), da conservare nel JSON: le
  /// grandezze sono calcolate su tutti i campioni, la serie ridotta serve a rileggerle.
  public func downsampledPerSecond() -> JSONValue {
    guard let start = samples.first?.uptimeNanoseconds else { return .array([]) }
    var buckets: [Int: UInt64] = [:]
    for sample in samples {
      let second = Int((sample.uptimeNanoseconds &- start) / 1_000_000_000)
      buckets[second] = Swift.max(buckets[second] ?? 0, sample.physFootprintBytes)
    }
    return .array(
      buckets.keys.sorted().map { .array([.int($0), .number(Double(buckets[$0]!))]) })
  }

  /// Campioni compresi fra due istanti.
  func samples(from start: UInt64, to end: UInt64) -> [FootprintSample] {
    samples.filter { $0.uptimeNanoseconds >= start && $0.uptimeNanoseconds <= end }
  }
}

/// `bench scroll-memory`: occupazione di picco su `scroll-50k` con scorrimento continuo, e
/// andamento in una sessione di lunga durata (NFR-P9).
@MainActor
public final class ScrollMemoryBench {
  public static let name = "scroll-memory"

  private let options: BenchOptions
  private let dataset: LoadedDataset

  public init(options: BenchOptions) throws {
    self.options = options
    dataset = try LoadedDataset.load(options)
  }

  public func run() async throws -> MeasurementResult {
    let startedAt = Date()
    let repetitions = options.repetitions ?? 5
    let speed = try options.extra.double("scroll-speed", default: 3)
    let longMinutes = try options.extra.double(
      "long-session", default: options.profile == .full ? 60 : 1)
    let enterBand = try options.extra.double("enter-band", default: 1)
    let exitBand = try options.extra.double("exit-band", default: 2)
    guard exitBand > enterBand else {
      throw BenchError.invalidOption("--exit-band deve essere maggiore di --enter-band")
    }
    let host = HostFingerprint.collect(volumeContaining: dataset.directory)
    try host.assertComplete()
    let geometry = GridGeometry(viewport: options.window)
    let queueWidth = host.performanceCores
    let urls = try FolderEnumerator.all(dataset.folderURL(dataset.manifest.folders.scroll.name))

    await BenchHost.warmUp(
      geometry: geometry, scale: options.thumbnailScale, queueWidth: queueWidth)
    // Il campionatore riserva la propria memoria alla costruzione: va creato prima della
    // baseline ed è riusato da tutte le ripetizioni.
    let sampler = FootprintSampler(intervalMs: 50)
    let baseline = await ScrollDriver.steadyFootprint()

    var results: [Repetition] = []
    var traces: [JSONValue] = []
    var screen: [String: String] = [:]
    for index in 0..<repetitions {
      let flags = RepetitionEnvironment.flags()
      let thermalAtStart = ThermalState.current
      let session = Session(
        urls: urls, geometry: geometry, options: options, queueWidth: queueWidth,
        enterBand: enterBand, exitBand: exitBand)
      sampler.start(baseline: baseline)
      try await session.open()
      screen = session.host.screenParameters
      let visibleAtStart = session.host.isVisibleOnScreen
      var ticks: [ScrollDriver.Tick] = []
      let expectedTicks = Int(2 * session.host.maxOffset / session.host.screenHeight / speed * 20)
      ticks.reserveCapacity(expectedTicks + 1_000)
      var retainedCounts: [Double] = []
      var filledFractions: [Double] = []
      retainedCounts.reserveCapacity(expectedTicks + 1_000)
      filledFractions.reserveCapacity(expectedTicks + 1_000)
      let host = session.host
      let band = session.band
      let observe = {
        retainedCounts.append(Double(band.retainedCount))
        filledFractions.append(host.visibleFilledFraction())
      }
      let start = BenchClock.now()
      await ScrollDriver.scroll(
        session.host, band: session.band, to: session.host.maxOffset, screensPerSecond: speed,
        ticks: &ticks, observe: observe)
      let bottom = BenchClock.now()
      await ScrollDriver.scroll(
        session.host, band: session.band, to: 0, screensPerSecond: speed, ticks: &ticks,
        observe: observe)
      let end = BenchClock.now()
      let trace = sampler.stop()
      let visibleAtEnd = session.host.isVisibleOnScreen
      let counters = session.counters
      await session.close()
      let settle = await FootprintSettle.wait(toWithin: 0.10, of: baseline, timeout: .seconds(30))

      let lastThird = trace.samples(from: start + (end - start) * 2 / 3, to: end)
      let plateau = Dispersion(lastThird.map { Double($0.physFootprintBytes) })?.median ?? 0
      let marginal = Self.marginalBytesPer1000Items(
        trace: trace, ticks: ticks, from: start + (bottom - start) / 3,
        to: start + (bottom - start) * 2 / 3, geometry: geometry)
      var repetitionFlags = flags
      repetitionFlags["footprintDidNotSettle"] = !settle.settled
      repetitionFlags["windowVisibleAtStart"] = visibleAtStart
      repetitionFlags["windowVisibleAtEnd"] = visibleAtEnd
      let retained = Dispersion(retainedCounts)
      let filled = Dispersion(filledFractions)
      results.append(
        Repetition(
          index: index,
          values: [
            "retainedCountMedian": retained?.median ?? 0,
            "retainedCountMax": retained?.max ?? 0,
            "visibleFilledFractionMedian": filled?.median ?? 0,
            "visibleFilledFractionMin": filled?.min ?? 0,
            "peakFootprintBytes": Double(trace.peak),
            "peakAboveBaselineBytes": Double(trace.peakAboveBaseline),
            "plateauFootprintBytes": plateau,
            "marginalBytesPer1000Items": marginal,
            "durationSeconds": Double(end - start) / 1e9,
            "thumbnailsProduced": Double(counters.produced),
            "thumbnailsRegenerated": Double(counters.regenerated),
            "requestsCancelled": Double(counters.cancelled),
            "thumbnailFailures": Double(counters.failures),
          ],
          flags: repetitionFlags, thermalStateAtStart: thermalAtStart,
          thermalStateAtEnd: .current))
      traces.append(trace.downsampledPerSecond())
      print(
        String(
          format:
            "  ripetizione %d: picco %.1f MB, regime %.1f MB, %.0f s, in vista con anteprima %.0f%%",
          index + 1, Double(trace.peak) / 1e6, plateau / 1e6, Double(end - start) / 1e9,
          (filled?.median ?? 0) * 100))
    }

    let longSession = try await runLongSession(
      minutes: longMinutes, speed: speed, urls: urls, geometry: geometry,
      queueWidth: queueWidth, baseline: baseline, enterBand: enterBand, exitBand: exitBand)

    var parameters = geometry.parameters
    parameters.merge(screen) { first, _ in first }
    parameters["thumbnailPath"] = options.thumbnailPath.rawValue
    parameters["thumbnailScale"] = "\(options.thumbnailScale)"
    parameters["queueWidth"] = "\(queueWidth)"
    parameters["scrollSpeedScreensPerSecond"] = "\(speed)"
    parameters["enterBand"] = "\(enterBand)"
    parameters["exitBand"] = "\(exitBand)"
    parameters["items"] = "\(urls.count)"
    parameters["samplingIntervalMs"] = "50"
    parameters["memoryMetric"] = "phys_footprint (task_info TASK_VM_INFO)"
    parameters["pass"] = "dall'inizio alla fine della cartella e ritorno all'inizio"
    parameters["plateau"] = "mediana dei campioni dell'ultimo terzo della corsa"
    parameters["marginal"] =
      "pendenza del footprint sugli elementi percorsi nel terzo centrale della discesa, × 1000"
    parameters["longSessionMinutes"] = "\(longMinutes)"
    return MeasurementResult(
      bench: Self.name, startedAt: startedAt, finishedAt: Date(),
      profile: options.profile.rawValue, datasetManifestDigest: dataset.manifestDigest,
      host: host, parameters: parameters, repetitions: results,
      derived: [
        "baselineFootprintBytes": .number(Double(baseline)),
        "longSession": longSession,
        "repetitionTracesPerSecond": .array(traces),
      ])
  }

  /// Sessione di lunga durata: raffiche di scorrimento e quiete in proporzione dichiarata, con
  /// campionamento a 50 ms per tutta la durata. La conclusione si formula sull'intervallo di
  /// confidenza della pendenza, non sul suo segno.
  private func runLongSession(
    minutes: Double, speed: Double, urls: [URL], geometry: GridGeometry, queueWidth: Int,
    baseline: UInt64, enterBand: Double, exitBand: Double
  ) async throws -> JSONValue {
    let burstSeconds = min(20.0, minutes * 60 / 6)
    let quietSeconds = burstSeconds / 2
    let windows = 6
    let session = Session(
      urls: urls, geometry: geometry, options: options, queueWidth: queueWidth,
      enterBand: enterBand, exitBand: exitBand)
    let reserved = Int(minutes * 60 * 1_000 / 50) + 2_000
    let sampler = FootprintSampler(intervalMs: 50, reservedSamples: reserved)
    sampler.start(baseline: baseline)
    try await session.open()
    let visibleAtStart = session.host.isVisibleOnScreen
    let start = BenchClock.now()
    let duration = UInt64(minutes * 60 * 1e9)
    var direction: CGFloat = 1
    var ticks: [ScrollDriver.Tick] = []
    var bursts = 0
    while BenchClock.now() - start < duration {
      // Raffica: scorre nella direzione corrente per `burstSeconds`, rimbalzando agli estremi.
      let burstEnd = min(start + duration, BenchClock.now() + UInt64(burstSeconds * 1e9))
      while BenchClock.now() < burstEnd {
        let target = direction > 0 ? session.host.maxOffset : 0
        if abs(session.host.offset - target) < 1 { direction = -direction }
        let remaining = Double(burstEnd &- BenchClock.now()) / 1e9
        guard remaining > 0.02 else { break }
        let step = CGFloat(min(remaining, 1) * speed) * session.host.screenHeight * direction
        await ScrollDriver.scroll(
          session.host, band: session.band, to: session.host.offset + step,
          screensPerSecond: speed, ticks: &ticks)
        ticks.removeAll(keepingCapacity: true)
      }
      bursts += 1
      // Quiete.
      let quietEnd = min(start + duration, BenchClock.now() + UInt64(quietSeconds * 1e9))
      while BenchClock.now() < quietEnd {
        try? await Task.sleep(for: .milliseconds(100))
      }
    }
    let end = BenchClock.now()
    let trace = sampler.stop()
    let visibleAtEnd = session.host.isVisibleOnScreen
    await session.close()

    // Analisi. La traccia comincia prima dell'apertura (finestra, 50.000 elementi, riempimento
    // della banda): quella salita non è un andamento della sessione e viene esclusa insieme al
    // primo intervallo dopo l'apertura. La pendenza principale è quella del kernel sulle mediane
    // per intervallo (circa 1/60 della durata, un minuto su 60 minuti): i campioni a 50 ms sono
    // fortemente autocorrelati e il loro intervallo di confidenza sarebbe illusoriamente stretto.
    let bucket = max(UInt64(1_000_000_000), (end - start) / 60)
    let analysisStart = start + bucket
    var buckets: [FootprintSample] = []
    var cursor = analysisStart
    while cursor + bucket <= end {
      let part = trace.samples(from: cursor, to: cursor + bucket)
      if let median = Dispersion(part.map { Double($0.physFootprintBytes) })?.median {
        buckets.append(
          FootprintSample(
            uptimeNanoseconds: cursor + bucket / 2, physFootprintBytes: UInt64(median)))
      }
      cursor += bucket
    }
    let primary =
      buckets.count >= 3
      ? FootprintTrace(intervalMs: Double(bucket) / 1e6, baseline: baseline, samples: buckets)
      : nil
    let analyzed = trace.samples(from: analysisStart, to: end)
    let raw =
      analyzed.count >= 3
      ? FootprintTrace(intervalMs: 50, baseline: baseline, samples: analyzed) : nil

    var windowSlopes: [Double] = []
    let windowLength = (end - analysisStart) / UInt64(windows)
    for window in 0..<windows {
      let from = analysisStart + UInt64(window) * windowLength
      let part = trace.samples(from: from, to: from + windowLength)
      if part.count >= 3 {
        let partial = FootprintTrace(intervalMs: 50, baseline: baseline, samples: part)
        if let slope = partial.slopeBytesPerHour { windowSlopes.append(slope) }
      }
    }
    let bounds = primary?.slopeConfidenceBounds95
    print(
      String(
        format:
          "  sessione lunga %.1f min: pendenza %.0f B/h (IC95 ±%.0f, distinguibile da zero: %@), picco %.1f MB",
        minutes, primary?.slopeBytesPerHour ?? .nan, primary?.slopeConfidenceInterval95 ?? .nan,
        primary?.slopeDistinguishableFromZero.map { $0 ? "sì" : "no" } ?? "?",
        Double(trace.peak) / 1e6))
    func optional(_ value: Double?) -> JSONValue { value.map(JSONValue.number) ?? .null }
    var result: [String: JSONValue] = [:]
    result["minutes"] = .number(Double(end - start) / 6e10)
    result["burstSeconds"] = .number(burstSeconds)
    result["quietSeconds"] = .number(quietSeconds)
    result["bursts"] = .int(bursts)
    result["samples"] = .int(trace.samples.count)
    result["samplingIntervalMs"] = .number(50)
    result["bucketSeconds"] = .number(Double(bucket) / 1e9)
    result["buckets"] = .int(buckets.count)
    result["excludedOpeningSeconds"] = .number(Double(analysisStart - start) / 1e9)
    result["longSessionSlopeBytesPerHour"] = optional(primary?.slopeBytesPerHour)
    result["slopeConfidenceInterval95"] = optional(primary?.slopeConfidenceInterval95)
    result["slopeConfidenceLow"] = optional(bounds?.lowerBound)
    result["slopeConfidenceHigh"] = optional(bounds?.upperBound)
    result["slopeDistinguishableFromZero"] =
      primary?.slopeDistinguishableFromZero.map(JSONValue.bool) ?? .null
    result["slopeMethod"] = .string(
      "kernel FootprintTrace sulle mediane per intervallo, esclusi l'apertura e il primo "
        + "intervallo; IC95 = errore standard della pendenza × 1,96")
    result["raw50msSlopeBytesPerHour"] = optional(raw?.slopeBytesPerHour)
    result["raw50msSlopeConfidenceInterval95"] = optional(raw?.slopeConfidenceInterval95)
    result["raw50msNote"] = .string(
      "secondario: IC95 dei minimi quadrati sui campioni a 50 ms, autocorrelati, quindi "
        + "ottimistico")
    result["windowSlopesBytesPerHour"] = Dispersion(windowSlopes)?.json ?? .null
    result["windows"] = .int(windowSlopes.count)
    result["peakFootprintBytes"] = .number(Double(trace.peak))
    result["initialFootprintBytes"] = optional(buckets.first.map { Double($0.physFootprintBytes) })
    result["finalFootprintBytes"] = optional(buckets.last.map { Double($0.physFootprintBytes) })
    result["openingRampBytes"] = optional(
      buckets.first.map { Double($0.physFootprintBytes) - Double(baseline) })
    result["windowVisibleAtStart"] = .bool(visibleAtStart)
    result["windowVisibleAtEnd"] = .bool(visibleAtEnd)
    result["tracePerSecond"] = trace.downsampledPerSecond()
    return .object(result)
  }

  /// Crescita del footprint per 1.000 elementi percorsi nel tratto indicato della discesa.
  static func marginalBytesPer1000Items(
    trace: FootprintTrace, ticks: [ScrollDriver.Tick], from: UInt64, to: UInt64,
    geometry: GridGeometry
  ) -> Double {
    guard !ticks.isEmpty else { return 0 }
    var x: [Double] = []
    var y: [Double] = []
    var cursor = 0
    for sample in trace.samples(from: from, to: to) {
      while cursor + 1 < ticks.count && ticks[cursor + 1].time <= sample.uptimeNanoseconds {
        cursor += 1
      }
      let items = Double(ticks[cursor].offset / geometry.rowPitch) * Double(geometry.columns)
      x.append(items)
      y.append(Double(sample.physFootprintBytes))
    }
    return (LinearFit.fit(x: x, y: y)?.slope ?? 0) * 1_000
  }

  /// Host, pipeline e banda di una corsa.
  @MainActor
  final class Session {
    let host: BenchHost
    let pipeline: ThumbnailPipeline
    let band: RetentionBand
    private let urls: [URL]

    init(
      urls: [URL], geometry: GridGeometry, options: BenchOptions, queueWidth: Int,
      enterBand: Double, exitBand: Double
    ) {
      self.urls = urls
      host = BenchHost(geometry: geometry)
      pipeline = ThumbnailPipeline(
        path: options.thumbnailPath, width: queueWidth, side: geometry.itemSide,
        scale: options.thumbnailScale)
      band = RetentionBand(
        host: host, pipeline: pipeline, enterBand: enterBand, exitBand: exitBand)
    }

    func open() async throws {
      await host.show()
      host.setURLs(urls)
      host.scroll(to: 0)
      band.update()
      try await ScrollDriver.waitForSteady(band, timeout: .seconds(180))
    }

    var counters: (produced: Int, regenerated: Int, cancelled: Int, failures: Int) {
      (band.producedCount, band.regeneratedCount, band.cancelledCount, pipeline.failureCount)
    }

    func close() async {
      band.clear()
      await pipeline.drain()
      host.close()
    }
  }
}
