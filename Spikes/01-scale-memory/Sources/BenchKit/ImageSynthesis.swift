import CoreGraphics
import Foundation
import ImageIO

/// Generatore pseudo-casuale deterministico (SplitMix64): stesso seme, stessa sequenza, su ogni
/// macchina. Il generatore di sistema non è seminabile e renderebbe il dataset non riproducibile.
public struct SplitMix64: RandomNumberGenerator, Sendable {
  private var state: UInt64

  public init(seed: UInt64) {
    state = seed
  }

  public mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// Valore uniforme in `[0, 1)`.
  public mutating func nextUnit() -> Double {
    Double(next() >> 11) / Double(1 << 53)
  }
}

/// Sintesi del contenuto delle immagini del dataset.
///
/// Il rumore puro non va bene: una JPEG da 12 MP di rumore pesa circa 9,3 MB contro i circa 4 MB
/// di una fotografia reale, e gonfierebbe la misura di I/O. L'immagine è quindi un composito a
/// banda limitata di tre strati — un gradiente a bassa frequenza, una texture a media frequenza e
/// una regione di dettaglio ad alta frequenza pari a circa un decimo dell'area — e la qualità di
/// codifica dei formati con perdita viene calibrata per centrare un obiettivo di byte per
/// megapixel.
public enum ImageSynthesis {
  /// Seme del contenuto di un file, derivato dal seme versionato e da una chiave stabile che
  /// identifica il file (FNV-1a a 64 bit: deterministico, a differenza di `Hasher`).
  public static func contentSeed(base: UInt64, key: String) -> UInt64 {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in key.utf8 {
      hash ^= UInt64(byte)
      hash &*= 0x0000_0100_0000_01B3
    }
    var mixer = SplitMix64(seed: base ^ hash)
    return mixer.next()
  }

  /// Sintetizza un'immagine sRGB a 8 bit per componente, senza alfa.
  public static func makeImage(width: Int, height: Int, seed: UInt64) -> CGImage {
    var rng = SplitMix64(seed: seed)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)

    // 1. Gradiente a bassa frequenza fra due colori casuali, con angolo casuale.
    let start = randomColor(&rng, in: colorSpace)
    let end = randomColor(&rng, in: colorSpace)
    let gradient = CGGradient(
      colorsSpace: colorSpace, colors: [start, end] as CFArray, locations: [0, 1])!
    let angle = rng.nextUnit() * 2 * Double.pi
    let radius = hypot(Double(width), Double(height)) / 2
    let center = CGPoint(x: Double(width) / 2, y: Double(height) / 2)
    let delta = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
    context.drawLinearGradient(
      gradient, start: CGPoint(x: center.x - delta.x, y: center.y - delta.y),
      end: CGPoint(x: center.x + delta.x, y: center.y + delta.y),
      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // 2. Texture a media frequenza: rumore a bassa risoluzione ingrandito con interpolazione,
    //    su due ottave, così da avere strutture morbide di scala diversa.
    context.interpolationQuality = .high
    for (divisor, alpha) in [(48, 0.45), (8, 0.30)] {
      let noise = noiseImage(
        width: max(2, width / divisor), height: max(2, height / divisor), rng: &rng)
      context.setAlpha(alpha)
      context.draw(noise, in: bounds)
    }

    // 3. Regione di dettaglio ad alta frequenza, circa un decimo dell'area, disegnata 1:1.
    let side = 0.316
    let detailWidth = max(1, Int(Double(width) * side))
    let detailHeight = max(1, Int(Double(height) * side))
    let detailX = Int(rng.nextUnit() * Double(width - detailWidth))
    let detailY = Int(rng.nextUnit() * Double(height - detailHeight))
    let detail = noiseImage(width: detailWidth, height: detailHeight, rng: &rng)
    context.interpolationQuality = .none
    context.setAlpha(0.35)
    context.draw(
      detail, in: CGRect(x: detailX, y: detailY, width: detailWidth, height: detailHeight))

    return context.makeImage()!
  }

  /// Codifica l'immagine in memoria nel formato richiesto.
  public static func encodedData(_ image: CGImage, format: ImageFormat, quality: Double?) throws
    -> Data
  {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, format.utType.identifier as CFString, 1, nil)
    else { throw SynthesisError.destinationUnavailable(format) }
    CGImageDestinationAddImage(destination, image, properties(format: format, quality: quality))
    guard CGImageDestinationFinalize(destination) else {
      throw SynthesisError.encodingFailed(format)
    }
    return data as Data
  }

  /// Codifica l'immagine direttamente su file.
  public static func write(_ image: CGImage, format: ImageFormat, quality: Double?, to url: URL)
    throws
  {
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, format.utType.identifier as CFString, 1, nil)
    else { throw SynthesisError.destinationUnavailable(format) }
    CGImageDestinationAddImage(destination, image, properties(format: format, quality: quality))
    guard CGImageDestinationFinalize(destination) else {
      throw SynthesisError.encodingFailed(format)
    }
  }

  /// Esito della calibrazione della qualità di codifica per una cella.
  public struct Calibration: Codable, Sendable {
    /// Qualità scelta, `nil` per i formati senza perdita.
    public let quality: Double?
    /// Byte per megapixel ottenuti sul campione con la qualità scelta (MB/MP).
    public let sampleBytesPerMegapixel: Double
    public let iterations: Int
  }

  /// Calibra la qualità di JPEG e HEIC con una ricerca binaria di al più `maxIterations`
  /// iterazioni su un campione, per centrare `target` (MB/MP) entro `tolerance`. Per i formati
  /// senza perdita misura soltanto i byte per megapixel del campione.
  public static func calibrate(
    format: ImageFormat, pixels: PixelSize, target: Double, tolerance: Double, seed: UInt64,
    maxIterations: Int = 6
  ) throws -> Calibration {
    let sample = makeImage(width: pixels.width, height: pixels.height, seed: seed)
    func bytesPerMegapixel(_ quality: Double?) throws -> Double {
      let data = try encodedData(sample, format: format, quality: quality)
      return Double(data.count) / 1_000_000 / pixels.megapixels
    }
    guard format.isLossy else {
      return Calibration(
        quality: nil, sampleBytesPerMegapixel: try bytesPerMegapixel(nil), iterations: 1)
    }
    var low = 0.05
    var high = 1.0
    var best: (quality: Double, achieved: Double)?
    var iterations = 0
    while iterations < maxIterations {
      iterations += 1
      let quality = (low + high) / 2
      let achieved = try bytesPerMegapixel(quality)
      if best == nil || abs(achieved - target) < abs(best!.achieved - target) {
        best = (quality, achieved)
      }
      if abs(achieved - target) <= target * tolerance / 4 { break }
      if achieved > target { high = quality } else { low = quality }
    }
    return Calibration(
      quality: best!.quality, sampleBytesPerMegapixel: best!.achieved, iterations: iterations)
  }

  public enum SynthesisError: Error, CustomStringConvertible {
    case destinationUnavailable(ImageFormat)
    case encodingFailed(ImageFormat)

    public var description: String {
      switch self {
      case .destinationUnavailable(let format): "encoder ImageIO non disponibile per \(format)"
      case .encodingFailed(let format): "codifica \(format) fallita"
      }
    }
  }

  // MARK: - Interni

  private static func properties(format: ImageFormat, quality: Double?) -> CFDictionary {
    var properties: [CFString: Any] = [:]
    if format.isLossy, let quality {
      properties[kCGImageDestinationLossyCompressionQuality] = quality
    }
    if format == .tiff {
      // TIFF senza compressione: è l'obiettivo dichiarato di 3 MB/MP (RGB a 8 bit).
      properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 1]
    }
    return properties as CFDictionary
  }

  private static func randomColor(_ rng: inout SplitMix64, in space: CGColorSpace) -> CGColor {
    let components: [CGFloat] = [
      0.1 + 0.8 * rng.nextUnit(), 0.1 + 0.8 * rng.nextUnit(), 0.1 + 0.8 * rng.nextUnit(), 1,
    ]
    return CGColor(colorSpace: space, components: components)!
  }

  /// Immagine di rumore RGB uniforme, riempita a parole di 64 bit per restare rapida anche nella
  /// costruzione di debug.
  private static func noiseImage(width: Int, height: Int, rng: inout SplitMix64) -> CGImage {
    let bytesPerRow = width * 4
    let wordCount = (bytesPerRow * height + 7) / 8
    var words = [UInt64](repeating: 0, count: wordCount)
    words.withUnsafeMutableBufferPointer { buffer in
      for index in buffer.indices { buffer[index] = rng.next() }
    }
    let data = words.withUnsafeBytes { Data($0.prefix(bytesPerRow * height)) }
    let provider = CGDataProvider(data: data as CFData)!
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
  }
}
