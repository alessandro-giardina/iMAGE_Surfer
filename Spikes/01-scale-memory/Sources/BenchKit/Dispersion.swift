/// Statistica di dispersione di una serie di misure ripetute.
///
/// **Convenzione dei percentili (vincolante per ogni cifra del cancello).** Il percentile `p`
/// (con `p` in `0...1`) di un campione ordinato `x[0] <= … <= x[n-1]` si ottiene per
/// interpolazione lineare fra ranghi:
///
///     h = (n - 1) * p
///     percentile(p) = x[⌊h⌋] + (h - ⌊h⌋) * (x[⌊h⌋ + 1] - x[⌊h⌋])
///
/// È la definizione 7 di Hyndman & Fan (1996), la stessa di `numpy.percentile` con
/// `method="linear"`, di `quantile(type = 7)` in R e di `PERCENTILE.INC` nei fogli di calcolo.
/// La mediana è il percentile 0,5 e l'IQR è `percentile(0,75) - percentile(0,25)`, entrambi con
/// la stessa convenzione. Esempio fissato per iscritto: sulla serie `1…100` il p95 vale
/// `95,05` (h = 94,05).
///
/// Due implementazioni di p95 diverse producono cifre diverse nello stesso documento: questo
/// cancello pubblica p95 come stima adottata, quindi la convenzione non va cambiata in silenzio.
public struct Dispersion: Codable, Sendable, Equatable {
  /// Numero di valori della serie.
  public let n: Int
  /// Valore minimo.
  public let min: Double
  /// Mediana (percentile 0,5).
  public let median: Double
  /// Percentile 0,95: la stima adottata dal cancello.
  public let p95: Double
  /// Valore massimo.
  public let max: Double
  /// Media aritmetica.
  public let mean: Double
  /// Deviazione standard campionaria, con denominatore `n - 1`. Vale `0` quando `n == 1`.
  public let stddev: Double
  /// Scarto interquartile, `percentile(0,75) - percentile(0,25)`. Vale `0` quando `n == 1`.
  public let iqr: Double

  /// Calcola la dispersione di `values`.
  ///
  /// Restituisce `nil` se la serie è vuota o contiene un valore non finito (`NaN` o infinito):
  /// una cifra non finita in un documento di esito sarebbe una cifra falsa, e l'assenza della
  /// dispersione è un difetto visibile invece di un numero plausibile.
  public init?(_ values: [Double]) {
    guard !values.isEmpty, values.allSatisfy(\.isFinite) else { return nil }
    let sorted = values.sorted()
    let count = sorted.count
    n = count
    min = sorted[0]
    max = sorted[count - 1]
    median = Self.percentile(sorted: sorted, 0.5)
    p95 = Self.percentile(sorted: sorted, 0.95)
    iqr = Self.percentile(sorted: sorted, 0.75) - Self.percentile(sorted: sorted, 0.25)
    if sorted[0] == sorted[count - 1] {
      // Serie costante: media e deviazione esatte, senza residui di arrotondamento.
      mean = sorted[0]
      stddev = 0
    } else {
      let average = sorted.reduce(0, +) / Double(count)
      let squaredDeviations = sorted.reduce(0) { $0 + ($1 - average) * ($1 - average) }
      mean = average
      stddev = count > 1 ? (squaredDeviations / Double(count - 1)).squareRoot() : 0
    }
  }

  /// Percentile `p` (in `0...1`) di una serie **già ordinata** in senso crescente, secondo la
  /// convenzione documentata sul tipo (interpolazione lineare fra ranghi, Hyndman & Fan tipo 7).
  ///
  /// - Precondition: `sorted` non è vuota e `p` è compreso fra 0 e 1.
  public static func percentile(sorted: [Double], _ p: Double) -> Double {
    precondition(!sorted.isEmpty, "percentile di una serie vuota")
    precondition((0.0...1.0).contains(p), "percentile fuori da 0...1: \(p)")
    let rank = Double(sorted.count - 1) * p
    let lower = Int(rank.rounded(.down))
    let upper = Swift.min(lower + 1, sorted.count - 1)
    let fraction = rank - Double(lower)
    return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
  }
}
