import CoreGraphics
import Foundation
import ImageIO

/// Ciò che un'operazione produce: gli oggetti vanno tenuti vivi fino all'ultima lettura del
/// footprint, altrimenti il picco misurato non contiene l'uscita stessa dell'operazione.
public struct WorkOutput {
  /// Oggetti prodotti (anteprime, osservazioni).
  public let objects: [AnyObject]
  /// Byte dell'immagine prodotta (`bytesPerRow × height`), 0 se l'operazione non produce
  /// un'immagine.
  public let outputBytes: Int

  static var none: WorkOutput { WorkOutput(objects: [], outputBytes: 0) }

  static func image(_ image: CGImage) -> WorkOutput {
    WorkOutput(objects: [image], outputBytes: image.bytesPerRow * image.height)
  }
}

/// Tipi di lavoro corrispondenti alle code di ADR-009, con l'operazione misurata dal costo per
/// elemento. È la stessa tassonomia di `PipelineQueueKind`, più `store`, più `noop` come cella
/// di controllo del fondo della strumentazione.
public enum WorkKind: String, CaseIterable, Sendable {
  /// Apertura del file e lettura delle chiavi di risorsa (`.fileSize`,
  /// `.contentModificationDate`, `.fileResourceIdentifierKey`), senza decodifica.
  case io
  /// `CGImageSourceCreateThumbnailAtIndex` al lato dell'elemento per il fattore di scala.
  case decode
  /// `QLThumbnailGenerator.generateBestRepresentation` con `representationTypes: .thumbnail`.
  case quicklook
  /// `VNGenerateImageFeaturePrintRequest` più `VNDetectFaceLandmarksRequest` sulla stessa
  /// immagine.
  case vision
  /// Scrittura dell'anteprima già prodotta su un file di cache (JPEG, qualità 0,8) e rilettura
  /// con decodifica. L'anteprima d'ingresso è prodotta e materializzata **prima** della baseline
  /// e non entra nella misura.
  case store
  /// Nessuna operazione: misura il fondo della strumentazione (campionatore, letture, pool).
  case noop

  /// I tipi di lavoro misurati da `item-cost --all`, esclusa la cella di controllo.
  public static let measured: [WorkKind] = [.io, .decode, .quicklook, .vision, .store]

  /// Prepara l'ingresso dell'operazione, fuori dalla misura. Per `store` l'anteprima viene
  /// ridisegnata in una bitmap propria, così che la sua memoria sia tutta allocata prima della
  /// baseline e non compaia durante l'operazione.
  func prepare(_ url: URL, side: CGFloat, scale: CGFloat) -> CGImage? {
    guard self == .store,
      let thumbnail = ThumbnailWork.imageIOThumbnail(
        url, maxPixelSize: Int((side * scale).rounded())),
      let context = CGContext(
        data: nil, width: thumbnail.width, height: thumbnail.height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    context.draw(
      thumbnail, in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
    return context.makeImage()
  }

  /// Esegue l'operazione misurata su un elemento e restituisce ciò che ha prodotto.
  func perform(
    _ url: URL, prepared: CGImage?, side: CGFloat, scale: CGFloat, cacheDirectory: URL
  ) throws -> WorkOutput {
    switch self {
    case .noop:
      return .none
    case .io:
      try ThumbnailWork.readResourceKeys(url)
      return .none
    case .decode:
      guard
        let image = ThumbnailWork.imageIOThumbnail(url, maxPixelSize: Int((side * scale).rounded()))
      else { throw BenchError.measurementFailed("decodifica fallita: \(url.lastPathComponent)") }
      return .image(image)
    case .quicklook:
      guard let image = ThumbnailWork.quickLookThumbnail(url, side: side, scale: scale) else {
        throw BenchError.measurementFailed("Quick Look senza anteprima: \(url.lastPathComponent)")
      }
      return .image(image)
    case .vision:
      return WorkOutput(objects: try ThumbnailWork.visionAnalysis(url), outputBytes: 0)
    case .store:
      guard let prepared else {
        throw BenchError.measurementFailed("anteprima d'ingresso assente per store")
      }
      let cacheFile = cacheDirectory.appending(path: UUID().uuidString + ".jpg")
      defer { try? FileManager.default.removeItem(at: cacheFile) }
      try ImageSynthesis.write(prepared, format: .jpeg, quality: 0.8, to: cacheFile)
      let options = [kCGImageSourceShouldCache: false] as CFDictionary
      guard let source = CGImageSourceCreateWithURL(cacheFile as CFURL, options),
        let reread = CGImageSourceCreateImageAtIndex(
          source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
      else { throw BenchError.measurementFailed("rilettura della cache fallita") }
      return .image(reread)
    }
  }
}
