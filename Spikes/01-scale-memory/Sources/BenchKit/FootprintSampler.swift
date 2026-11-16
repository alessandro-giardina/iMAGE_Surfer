import Darwin
import Dispatch
import Foundation
import Synchronization

// Unica grandezza di memoria del banco: `phys_footprint` di `task_info(TASK_VM_INFO)`, cioè la
// memoria che il sistema attribuisce al processo ai fini della pressione di memoria (la stessa
// colonna «Memoria» di Monitoraggio Attività). `resident_size` misura un'altra cosa (pagine
// residenti, incluse quelle condivise e pulite) e non va mai mescolata con questa.

/// Un campione di `phys_footprint` con il suo istante monotono.
public struct FootprintSample: Codable, Sendable, Equatable {
  /// Istante del campione, `DispatchTime.now().uptimeNanoseconds`: monotono, non segue l'ora
  /// di sistema.
  public var uptimeNanoseconds: UInt64
  /// `phys_footprint` del processo, in byte.
  public var physFootprintBytes: UInt64

  /// Crea un campione con valori dati (per tracce sintetiche nei test).
  public init(uptimeNanoseconds: UInt64, physFootprintBytes: UInt64) {
    self.uptimeNanoseconds = uptimeNanoseconds
    self.physFootprintBytes = physFootprintBytes
  }

  /// Campiona `phys_footprint` adesso.
  public static func now() -> FootprintSample {
    let bytes = FootprintSampler.physFootprint()
    return FootprintSample(
      uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
      physFootprintBytes: bytes
    )
  }
}

/// Traccia di `phys_footprint` raccolta da un `FootprintSampler`, con picco e pendenza.
///
/// Le grandezze derivate sono calcolate una sola volta dai campioni alla costruzione, anche alla
/// decodifica da JSON: il JSON le riporta per leggibilità, ma la fonte di verità sono i campioni.
public struct FootprintTrace: Codable, Sendable, Equatable {
  /// Intervallo di campionamento richiesto, in millisecondi.
  public let intervalMs: Double
  /// `phys_footprint` di riferimento, fissato dal chiamante prima dell'avvio.
  public let baseline: UInt64
  /// Campioni in ordine di acquisizione, con istante monotono.
  public let samples: [FootprintSample]
  /// Massimo `phys_footprint` osservato fra i campioni.
  public let peak: UInt64
  /// `phys_footprint` del primo campione.
  public let first: UInt64
  /// `phys_footprint` dell'ultimo campione.
  public let last: UInt64
  /// Pendenza della retta ai minimi quadrati di `phys_footprint` sul tempo, in byte all'ora.
  /// `nil` con meno di due campioni o con tutti i campioni nello stesso istante.
  public let slopeBytesPerHour: Double?
  /// Semiampiezza dell'intervallo di confidenza al 95% della pendenza, in byte all'ora:
  /// errore standard della pendenza × 1,96. `nil` con meno di tre campioni.
  ///
  /// L'errore standard è quello dei minimi quadrati ordinari, che assume residui indipendenti.
  /// Campioni ravvicinati (50 ms) sono autocorrelati, quindi l'intervallo è **ottimistico**:
  /// tende a dichiarare distinguibile da zero una deriva piccola. Chi pubblica la cifra lo
  /// dichiara insieme alla durata e all'intervallo di campionamento.
  public let slopeConfidenceInterval95: Double?

  /// Costruisce la traccia da campioni dati e ne calcola picco, estremi e pendenza.
  ///
  /// - Precondition: `samples` non è vuoto.
  public init(intervalMs: Double, baseline: UInt64, samples: [FootprintSample]) {
    precondition(!samples.isEmpty, "una traccia di footprint richiede almeno un campione")
    self.intervalMs = intervalMs
    self.baseline = baseline
    self.samples = samples
    peak = samples.lazy.map(\.physFootprintBytes).max() ?? 0
    first = samples[0].physFootprintBytes
    last = samples[samples.count - 1].physFootprintBytes
    let regression = Self.leastSquaresSlope(samples)
    slopeBytesPerHour = regression?.slope
    slopeConfidenceInterval95 = regression?.halfWidth95
  }

  /// Picco meno baseline, in byte. Negativo se il footprint non ha mai superato la baseline.
  public var peakAboveBaseline: Int64 {
    Int64(clamping: peak) - Int64(clamping: baseline)
  }

  /// Estremi dell'intervallo di confidenza al 95% della pendenza, in byte all'ora.
  public var slopeConfidenceBounds95: ClosedRange<Double>? {
    guard let slope = slopeBytesPerHour, let halfWidth = slopeConfidenceInterval95 else {
      return nil
    }
    return (slope - halfWidth)...(slope + halfWidth)
  }

  /// `true` se l'intervallo di confidenza al 95% della pendenza esclude lo zero.
  ///
  /// Una pendenza il cui intervallo contiene lo zero **non** è crescita né decrescita: va
  /// riportata come «non distinguibile da zero», non arrotondata a «stabile». `nil` quando
  /// l'intervallo non è calcolabile.
  public var slopeDistinguishableFromZero: Bool? {
    guard let bounds = slopeConfidenceBounds95 else { return nil }
    return !bounds.contains(0)
  }

  private enum CodingKeys: String, CodingKey {
    case intervalMs, baseline, samples, peak, first, last
    case slopeBytesPerHour, slopeConfidenceInterval95
  }

  /// Decodifica intervallo, baseline e campioni, e ricalcola le grandezze derivate.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let samples = try container.decode([FootprintSample].self, forKey: .samples)
    guard !samples.isEmpty else {
      throw DecodingError.dataCorruptedError(
        forKey: .samples,
        in: container,
        debugDescription: "una traccia di footprint richiede almeno un campione"
      )
    }
    self.init(
      intervalMs: try container.decode(Double.self, forKey: .intervalMs),
      baseline: try container.decode(UInt64.self, forKey: .baseline),
      samples: samples
    )
  }

  /// Regressione lineare ai minimi quadrati di `phys_footprint` (byte) sul tempo (ore).
  private static func leastSquaresSlope(
    _ samples: [FootprintSample]
  ) -> (slope: Double, halfWidth95: Double?)? {
    let count = samples.count
    guard count >= 2 else { return nil }
    let nanosecondsPerHour = 3_600_000_000_000.0
    let origin = Int64(clamping: samples[0].uptimeNanoseconds)
    let hours = samples.map {
      Double(Int64(clamping: $0.uptimeNanoseconds) - origin) / nanosecondsPerHour
    }
    let bytes = samples.map { Double($0.physFootprintBytes) }
    let meanHours = hours.reduce(0, +) / Double(count)
    let meanBytes = bytes.reduce(0, +) / Double(count)
    var sumSquaresHours = 0.0
    var sumCrossProducts = 0.0
    for index in 0..<count {
      let deltaHours = hours[index] - meanHours
      sumSquaresHours += deltaHours * deltaHours
      sumCrossProducts += deltaHours * (bytes[index] - meanBytes)
    }
    guard sumSquaresHours > 0 else { return nil }
    let slope = sumCrossProducts / sumSquaresHours
    guard count >= 3 else { return (slope, nil) }
    var sumSquaredResiduals = 0.0
    for index in 0..<count {
      let residual = (bytes[index] - meanBytes) - slope * (hours[index] - meanHours)
      sumSquaredResiduals += residual * residual
    }
    let standardError = (sumSquaredResiduals / Double(count - 2) / sumSquaresHours).squareRoot()
    return (slope, 1.96 * standardError)
  }
}

/// Campionatore di `phys_footprint` su un thread dedicato, a intervallo configurabile.
///
/// Uso tipico: `let sampler = FootprintSampler(intervalMs: 50)`, poi
/// `sampler.start(baseline: …)`, il lavoro da misurare, e `let trace = sampler.stop()`.
/// Intervalli adottati dal cancello: 50 ms per scorrimento e sessione lunga, 5 ms per il costo
/// per elemento.
///
/// Il campionatore riserva **e tocca** la memoria dei campioni alla costruzione, così la sua
/// stessa memoria non cresce durante la misura e non altera picco e pendenza (a 50 ms una
/// sessione di un'ora accumula circa 1,1 MB di campioni, che altrimenti comparirebbero come
/// crescita). Oltre `reservedSamples` campioni la memoria torna a crescere, di 16 byte per
/// campione. Il campionatore va quindi creato **prima** di rilevare la baseline.
///
/// Non è rientrante: a ogni `start(baseline:)` corrisponde un solo `stop()`. Dopo `stop()` può
/// essere riavviato e riusa la memoria già riservata.
public final class FootprintSampler: Sendable {
  /// Campioni riservati per difetto: circa 66 minuti a 50 ms, poco più di 1,2 MB.
  public static let defaultReservedSamples = 80_000

  /// Intervallo di campionamento, in millisecondi.
  public let intervalMs: Double

  private let state: Mutex<State>

  /// Crea un campionatore fermo.
  ///
  /// - Parameters:
  ///   - intervalMs: intervallo fra due campioni, in millisecondi; maggiore di zero.
  ///   - reservedSamples: campioni per cui riservare e toccare la memoria in anticipo.
  public init(intervalMs: Double, reservedSamples: Int = FootprintSampler.defaultReservedSamples) {
    precondition(intervalMs > 0, "intervallo di campionamento non positivo: \(intervalMs)")
    self.intervalMs = intervalMs
    // Segnaposto non nullo: ogni pagina riservata viene scritta davvero, e il sistema non può
    // trattarla come pagina di zeri.
    let placeholder = FootprintSample(uptimeNanoseconds: .max, physFootprintBytes: .max)
    state = Mutex(
      State(storage: Array(repeating: placeholder, count: Swift.max(reservedSamples, 2)))
    )
  }

  /// `true` fra `start(baseline:)` e il ritorno di `stop()`.
  public var isRunning: Bool {
    state.withLock { state in
      if case .idle = state.phase { return false }
      return true
    }
  }

  /// `phys_footprint` corrente del processo, in byte.
  public func current() -> UInt64 {
    Self.physFootprint()
  }

  /// Avvia il campionamento. Il primo campione è preso in modo sincrono prima del ritorno.
  ///
  /// - Parameter baseline: `phys_footprint` di riferimento rilevato dal chiamante prima
  ///   dell'avvio; se `nil`, vale il primo campione.
  /// - Precondition: il campionatore è fermo.
  public func start(baseline: UInt64? = nil) {
    let firstSample = FootprintSample.now()
    let wake = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    state.withLock { state in
      guard case .idle = state.phase else {
        preconditionFailure("FootprintSampler già avviato")
      }
      state.phase = .running(wake: wake, finished: finished)
      state.baseline = baseline ?? firstSample.physFootprintBytes
      state.count = 0
      state.append(firstSample)
    }
    let origin = firstSample.uptimeNanoseconds
    let intervalNanoseconds = Swift.max(UInt64((intervalMs * 1_000_000).rounded()), 1)
    let thread = Thread { [self] in
      samplingLoop(
        origin: origin,
        intervalNanoseconds: intervalNanoseconds,
        wake: wake,
        finished: finished
      )
    }
    thread.name = "BenchKit.FootprintSampler"
    thread.qualityOfService = .userInteractive
    thread.start()
  }

  /// Ferma il campionamento, prende un ultimo campione sincrono e restituisce la traccia.
  ///
  /// - Precondition: il campionatore è avviato.
  public func stop() -> FootprintTrace {
    let (wake, finished) = state.withLock { state -> (DispatchSemaphore, DispatchSemaphore) in
      guard case .running(let wake, let finished) = state.phase else {
        preconditionFailure("FootprintSampler non avviato")
      }
      state.phase = .stopping
      return (wake, finished)
    }
    wake.signal()
    finished.wait()
    let lastSample = FootprintSample.now()
    return state.withLock { state in
      state.append(lastSample)
      state.phase = .idle
      return FootprintTrace(
        intervalMs: intervalMs,
        baseline: state.baseline,
        samples: Array(state.storage[0..<state.count])
      )
    }
  }

  /// Copia dei campioni raccolti finora, senza fermare il campionamento (oppure quelli
  /// dell'ultima corsa, se il campionatore è fermo).
  ///
  /// La copia alloca memoria propria: durante una misura di footprint va usata con parsimonia.
  ///
  /// - Precondition: il campionatore è stato avviato almeno una volta.
  public func snapshot() -> FootprintTrace {
    state.withLock { state in
      precondition(state.count > 0, "FootprintSampler mai avviato")
      return FootprintTrace(
        intervalMs: intervalMs,
        baseline: state.baseline,
        samples: Array(state.storage[0..<state.count])
      )
    }
  }

  /// Legge `phys_footprint` del processo corrente con `task_info(TASK_VM_INFO)`.
  ///
  /// Se la chiamata fallisce il processo termina: un campionatore che restituisce zero in
  /// silenzio annullerebbe ogni misura di memoria del cancello, mentre un arresto è visibile.
  public static func physFootprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let capacity = Int(count)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) { words in
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), words, &count)
      }
    }
    guard result == KERN_SUCCESS, Int(count) >= requiredVMInfoCount else {
      fatalError("task_info(TASK_VM_INFO) fallita: kr=\(result), count=\(count)")
    }
    return info.phys_footprint
  }

  /// Numero minimo di parole di `task_vm_info` che deve restituire il kernel perché
  /// `phys_footprint` sia valorizzato.
  private static let requiredVMInfoCount: Int = {
    let offset =
      MemoryLayout<task_vm_info_data_t>.offset(of: \.phys_footprint)
      ?? MemoryLayout<task_vm_info_data_t>.size - MemoryLayout<UInt64>.size
    return (offset + MemoryLayout<UInt64>.size) / MemoryLayout<integer_t>.size
  }()

  /// Ciclo del thread dedicato: un campione per scadenza assoluta `origin + k · intervallo`,
  /// senza deriva cumulativa; le scadenze mancate per ritardo del thread vengono saltate, non
  /// recuperate a raffica.
  private func samplingLoop(
    origin: UInt64,
    intervalNanoseconds: UInt64,
    wake: DispatchSemaphore,
    finished: DispatchSemaphore
  ) {
    var tick: UInt64 = 1
    while wake.wait(timeout: DispatchTime(uptimeNanoseconds: origin + tick * intervalNanoseconds))
      == .timedOut
    {
      let sample = FootprintSample.now()
      state.withLock { $0.append(sample) }
      let elapsedTicks = (sample.uptimeNanoseconds - origin) / intervalNanoseconds
      tick = Swift.max(tick + 1, elapsedTicks + 1)
    }
    finished.signal()
  }

  private enum Phase {
    case idle
    case running(wake: DispatchSemaphore, finished: DispatchSemaphore)
    case stopping
  }

  private struct State {
    var phase = Phase.idle
    var baseline: UInt64 = 0
    var storage: [FootprintSample]
    var count = 0

    init(storage: [FootprintSample]) {
      self.storage = storage
    }

    mutating func append(_ sample: FootprintSample) {
      if count < storage.count {
        storage[count] = sample
      } else {
        storage.append(sample)
      }
      count += 1
    }
  }
}
