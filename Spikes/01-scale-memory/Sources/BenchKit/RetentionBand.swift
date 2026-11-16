import AppKit

/// Banda di ritenzione con isteresi, nella forma minima che serve a misurarla (NFR-P6, NFR-P12).
///
/// Un elemento **entra** nell'insieme trattenuto quando la sua distanza dalla porta di vista è
/// inferiore a `enterBand` schermate, e viene **rilasciato** solo quando supera `exitBand`
/// schermate, con `exitBand >= enterBand`. Il rilascio azzera esplicitamente il riferimento
/// all'anteprima. È materiale del banco, non la forma definitiva: non va estratto in un pacchetto.
@MainActor
public final class RetentionBand {
  public let enterBand: Double
  public let exitBand: Double
  private let host: BenchHost
  private let pipeline: ThumbnailPipeline

  /// Elementi con anteprima trattenuta.
  private var retained: Set<Int> = []
  /// Richieste in corso, annullabili.
  private var inFlight: [Int: ThumbnailTicket] = [:]
  /// Elementi la cui anteprima è stata prodotta e poi rilasciata: un bitset di dimensione fissa,
  /// così la memoria della strumentazione non cresce durante lo scorrimento.
  private var released: [UInt64] = []

  /// Anteprime ricalcolate perché rilasciate e poi richieste di nuovo.
  public private(set) var regeneratedCount = 0
  /// Anteprime prodotte in totale.
  public private(set) var producedCount = 0
  /// Richieste annullate perché l'elemento è uscito dalla banda prima di essere prodotto.
  public private(set) var cancelledCount = 0

  /// Anteprime trattenute.
  public var retainedCount: Int { retained.count }
  /// Richieste in corso.
  public var inFlightCount: Int { inFlight.count }

  public init(host: BenchHost, pipeline: ThumbnailPipeline, enterBand: Double, exitBand: Double) {
    precondition(exitBand >= enterBand, "la soglia di uscita non può precedere quella di entrata")
    self.host = host
    self.pipeline = pipeline
    self.enterBand = enterBand
    self.exitBand = exitBand
  }

  /// Azzera i contatori osservabili, senza toccare l'insieme trattenuto.
  public func resetCounters() {
    regeneratedCount = 0
    producedCount = 0
    cancelledCount = 0
  }

  /// Applica la banda alla posizione attuale della vista: chiede gli elementi entrati e
  /// rilascia quelli usciti.
  public func update() {
    let count = host.urls.count
    guard count > 0 else { return }
    if released.count * 64 < count {
      released = [UInt64](repeating: 0, count: (count + 63) / 64)
    }
    let columns = host.geometry.columns
    let pitch = host.geometry.rowPitch
    let screen = host.screenHeight
    let top = host.offset - CGFloat(enterBand) * screen
    let bottom = host.offset + screen + CGFloat(enterBand) * screen
    let lastRow = (count - 1) / columns
    let firstWanted = max(0, Int((top / pitch).rounded(.down)))
    let lastWanted = min(lastRow, Int((bottom / pitch).rounded(.down)))

    // Rilascio: trattenuti e richieste oltre la soglia di uscita.
    for item in retained where distance(of: item) > exitBand {
      retained.remove(item)
      setReleased(item, true)
      host.release(at: item)
    }
    for (item, ticket) in inFlight where distance(of: item) > exitBand {
      ticket.cancel()
      inFlight.removeValue(forKey: item)
      cancelledCount += 1
    }

    // Ingresso: elementi entro la soglia di entrata; gli elementi in vista (distanza 0) sono
    // sempre richiesti, anche con banda nulla.
    guard firstWanted <= lastWanted else { return }
    for row in firstWanted...lastWanted {
      let rowDistance = distance(ofRow: row)
      guard rowDistance == 0 || rowDistance < enterBand else { continue }
      for item in (row * columns)..<min(count, (row + 1) * columns)
      where !retained.contains(item) && inFlight[item] == nil {
        request(item)
      }
    }
  }

  /// Rilascia tutto e annulla le richieste in corso.
  public func clear() {
    for item in retained { host.release(at: item) }
    retained.removeAll()
    for ticket in inFlight.values { ticket.cancel() }
    inFlight.removeAll()
    for index in released.indices { released[index] = 0 }
  }

  private func isReleased(_ item: Int) -> Bool {
    item / 64 < released.count && released[item / 64] & (1 << UInt64(item % 64)) != 0
  }

  private func setReleased(_ item: Int, _ value: Bool) {
    guard item / 64 < released.count else { return }
    if value {
      released[item / 64] |= 1 << UInt64(item % 64)
    } else {
      released[item / 64] &= ~(1 << UInt64(item % 64))
    }
  }

  private func distance(of item: Int) -> Double {
    distance(ofRow: host.row(of: item))
  }

  private func distance(ofRow row: Int) -> Double {
    Double(host.distanceInScreens(ofRow: row))
  }

  private func request(_ item: Int) {
    let priority: Operation.QueuePriority = distance(of: item) == 0 ? .high : .normal
    inFlight[item] = pipeline.requestThumbnail(for: host.urls[item], priority: priority) {
      [weak self] image in
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self?.deliver(image, for: item) }
      }
    }
  }

  private func deliver(_ image: CGImage?, for item: Int) {
    // Una consegna per un elemento non più richiesto (annullato nel frattempo) va scartata.
    guard inFlight.removeValue(forKey: item) != nil else { return }
    producedCount += 1
    if isReleased(item) {
      setReleased(item, false)
      regeneratedCount += 1
    }
    guard let image else { return }
    retained.insert(item)
    host.assign(image, at: item)
  }
}
