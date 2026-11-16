import Foundation
import Testing

@testable import BenchKit

@Suite("Campionatore di phys_footprint", .serialized)
struct FootprintSamplerTests {
  /// È il test che protegge dal difetto peggiore dello spike: un campionatore che restituisce
  /// sempre zero renderebbe nulle tutte le misure di memoria del cancello.
  @Test("rileva un'allocazione toccata di 256 MB")
  func detectsTouchedAllocation() async throws {
    let size = 256 << 20
    let sampler = FootprintSampler(intervalMs: 5, reservedSamples: 4_096)
    sampler.start(baseline: FootprintSampler.physFootprint())
    try await Task.sleep(for: .milliseconds(30))

    let block = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16_384)
    // Un byte per pagina: senza scrittura la memoria non entra nel footprint.
    for offset in stride(from: 0, to: size, by: 4_096) {
      block.storeBytes(
        of: UInt8(truncatingIfNeeded: offset >> 12), toByteOffset: offset, as: UInt8.self)
    }
    try await Task.sleep(for: .milliseconds(80))
    block.deallocate()
    try await Task.sleep(for: .milliseconds(30))
    let trace = sampler.stop()

    #expect(trace.samples.count >= 5)
    #expect(trace.peak - trace.baseline >= 200 << 20)
    #expect(trace.peakAboveBaseline >= 200 << 20)
  }

  @Test("current() legge un footprint positivo")
  func currentIsPositive() {
    #expect(FootprintSampler.physFootprint() > 0)
    #expect(FootprintSampler(intervalMs: 50, reservedSamples: 16).current() > 0)
  }

  @Test("la pendenza di una crescita nota è ritrovata entro il 10%")
  func slopeOfKnownGrowth() throws {
    let growthPerHour = 10_000_000.0
    var rng = SplitMix64(seed: 7)
    // Un'ora a un campione al secondo, con rumore di ±2 MB attorno alla retta.
    let samples = (0..<3_600).map { second -> FootprintSample in
      let noise = (rng.nextUnit() - 0.5) * 4_000_000
      let bytes = 500_000_000 + growthPerHour * Double(second) / 3_600 + noise
      return FootprintSample(
        uptimeNanoseconds: UInt64(second) * 1_000_000_000, physFootprintBytes: UInt64(bytes))
    }
    let trace = FootprintTrace(intervalMs: 1_000, baseline: 500_000_000, samples: samples)
    let slope = try #require(trace.slopeBytesPerHour)
    #expect(abs(slope - growthPerHour) / growthPerHour < 0.10)
    #expect(trace.slopeDistinguishableFromZero == true)
  }

  @Test("su una traccia piatta l'intervallo di confidenza al 95% contiene lo zero")
  func flatTraceIsNotGrowth() throws {
    var rng = SplitMix64(seed: 11)
    let samples = (0..<1_200).map { index -> FootprintSample in
      let noise = (rng.nextUnit() - 0.5) * 4_000_000
      return FootprintSample(
        uptimeNanoseconds: UInt64(index) * 50_000_000,
        physFootprintBytes: UInt64(800_000_000 + noise))
    }
    let trace = FootprintTrace(intervalMs: 50, baseline: 800_000_000, samples: samples)
    let bounds = try #require(trace.slopeConfidenceBounds95)
    #expect(bounds.contains(0))
    #expect(trace.slopeDistinguishableFromZero == false)
  }
}
