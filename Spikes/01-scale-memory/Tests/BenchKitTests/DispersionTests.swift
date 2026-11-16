import Foundation
import Testing

@testable import BenchKit

@Suite("Dispersione delle ripetizioni")
struct DispersionTests {
  @Test("serie 1…5: mediana, media, deviazione standard campionaria, IQR e p95 noti")
  func knownSeries() throws {
    let dispersion = try #require(Dispersion([1, 2, 3, 4, 5]))
    #expect(dispersion.n == 5)
    #expect(dispersion.min == 1)
    #expect(dispersion.max == 5)
    #expect(dispersion.median == 3)
    #expect(dispersion.mean == 3)
    #expect(abs(dispersion.stddev - 2.5.squareRoot()) < 1e-9)
    // Interpolazione lineare fra ranghi: q25 = x[1] = 2, q75 = x[3] = 4, p95 a h = 3,8.
    #expect(abs(dispersion.iqr - 2) < 1e-12)
    #expect(abs(dispersion.p95 - 4.8) < 1e-12)
  }

  @Test("l'ordine di ingresso non conta")
  func orderIndependent() throws {
    let sorted = try #require(Dispersion([1, 2, 3, 4, 5]))
    let shuffled = try #require(Dispersion([4, 1, 5, 3, 2]))
    #expect(sorted == shuffled)
  }

  @Test("n = 1: deviazione standard e IQR nulli senza divisione per zero")
  func singleValue() throws {
    let dispersion = try #require(Dispersion([7]))
    #expect(dispersion.n == 1)
    #expect(dispersion.stddev == 0)
    #expect(dispersion.iqr == 0)
    #expect(dispersion.median == 7)
    #expect(dispersion.p95 == 7)
  }

  @Test("serie vuota: nessuna dispersione")
  func emptySeries() {
    #expect(Dispersion([]) == nil)
  }

  @Test("valori identici: deviazione standard nulla e p95 pari al valore")
  func identicalValues() throws {
    let dispersion = try #require(Dispersion([4.25, 4.25, 4.25, 4.25, 4.25, 4.25]))
    #expect(dispersion.stddev == 0)
    #expect(dispersion.iqr == 0)
    #expect(dispersion.p95 == 4.25)
  }

  @Test("convenzione fissata per iscritto: sulla serie 1…100 il p95 vale 95,05")
  func p95ConventionIsPinned() throws {
    let dispersion = try #require(Dispersion((1...100).map(Double.init)))
    // h = (n - 1) · 0,95 = 94,05 → x[94] + 0,05 · (x[95] - x[94]) = 95 + 0,05.
    #expect(abs(dispersion.p95 - 95.05) < 1e-9)
    #expect(abs(dispersion.median - 50.5) < 1e-9)
    #expect(abs(dispersion.iqr - 49.5) < 1e-9)
  }

  @Test("un valore non finito non produce una dispersione")
  func nonFiniteValuesAreRejected() {
    #expect(Dispersion([1, .nan, 3]) == nil)
    #expect(Dispersion([1, .infinity]) == nil)
  }
}
