import CoreGraphics
import Darwin
import Foundation
import ImageIO
import QuickLookThumbnailing
import Synchronization
import Vision

/// Percorso di produzione dell'anteprima, selezionabile da riga di comando.
public enum ThumbnailPath: String, CaseIterable, Sendable {
  /// `QLThumbnailGenerator.generateBestRepresentation` con `representationTypes: .thumbnail`.
  case quicklook
  /// `CGImageSourceCreateThumbnailAtIndex` alla dimensione dell'elemento per il fattore di scala.
  case imageio

  /// Coda che esegue questo percorso.
  public var queue: PipelineQueueKind {
    switch self {
    case .quicklook: .quicklook
    case .imageio: .decode
    }
  }
}

/// Code per tipo di lavoro, nella forma minima che serve a misurare la politica di ADR-009.
public enum PipelineQueueKind: String, CaseIterable, Sendable {
  case io
  case quicklook
  case decode
  case vision
}

/// Operazioni elementari di ogni tipo di lavoro. Sono funzioni pure e bloccanti, riusate sia dalle
/// code della pipeline sia dalla misura del costo per elemento.
public enum ThumbnailWork {
  /// `io`: apertura del file e lettura delle chiavi di risorsa, senza decodifica.
  @discardableResult
  public static func readResourceKeys(_ url: URL) throws -> Int {
    var url = url
    url.removeAllCachedResourceValues()
    let values = try url.resourceValues(forKeys: [
      .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey,
    ])
    let descriptor = open(url.path, O_RDONLY)
    guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    close(descriptor)
    return values.fileSize ?? 0
  }

  /// `decode`: anteprima ridimensionata con ImageIO, decodificata dall'immagine piena.
  public static func imageIOThumbnail(_ url: URL, maxPixelSize: Int) -> CGImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  /// `quicklook`: anteprima prodotta da Quick Look, attesa in modo sincrono.
  public static func quickLookThumbnail(_ url: URL, side: CGFloat, scale: CGFloat) -> CGImage? {
    let request = QLThumbnailGenerator.Request(
      fileAt: url, size: CGSize(width: side, height: side), scale: scale,
      representationTypes: .thumbnail)
    let box = ResultBox<CGImage>()
    let done = DispatchSemaphore(value: 0)
    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
      box.set(representation?.cgImage)
      done.signal()
    }
    // Scadenza: un file che Quick Look non riesce a trattare non deve bloccare il banco.
    guard done.wait(timeout: .now() + 60) == .success else { return nil }
    return box.get()
  }

  /// `vision`: impronta di caratteristiche dell'immagine, il carico di visione della coda.
  public static func visionFeaturePrint(_ url: URL) throws {
    let handler = VNImageRequestHandler(url: url, options: [:])
    try handler.perform([VNGenerateImageFeaturePrintRequest()])
  }

  /// `vision` completo, come misurato dal costo per elemento: impronta più punti del volto.
  /// Restituisce le richieste eseguite, che trattengono le proprie osservazioni.
  @discardableResult
  public static func visionAnalysis(_ url: URL) throws -> [AnyObject] {
    let handler = VNImageRequestHandler(url: url, options: [:])
    let requests: [VNRequest] = [
      VNGenerateImageFeaturePrintRequest(), VNDetectFaceLandmarksRequest(),
    ]
    try handler.perform(requests)
    return requests
  }

  /// Anteprima con il percorso richiesto.
  public static func thumbnail(
    _ url: URL, path: ThumbnailPath, side: CGFloat, scale: CGFloat
  ) -> CGImage? {
    switch path {
    case .quicklook: quickLookThumbnail(url, side: side, scale: scale)
    case .imageio: imageIOThumbnail(url, maxPixelSize: Int((side * scale).rounded()))
    }
  }
}

/// Richiesta di anteprima annullabile.
public final class ThumbnailTicket: Sendable {
  private let state = Mutex<(cancelled: Bool, operations: [Operation])>((false, []))

  public var isCancelled: Bool { state.withLock { $0.cancelled } }

  /// Annulla la richiesta: le operazioni non ancora iniziate non partono e il completamento non
  /// viene chiamato.
  public func cancel() {
    let operations = state.withLock { state -> [Operation] in
      state.cancelled = true
      return state.operations
    }
    for operation in operations { operation.cancel() }
  }

  fileprivate func attach(_ operation: Operation) {
    state.withLock { $0.operations.append(operation) }
  }

  /// Rilascia le operazioni concluse.
  fileprivate func detachAll() {
    state.withLock { $0.operations.removeAll() }
  }
}

/// Pipeline delle anteprime: code separate per tipo di lavoro, con larghezza configurabile e
/// priorità inferiore all'interazione. Una richiesta di anteprima passa prima dalla coda `io`
/// (apertura e chiavi di risorsa) e poi dalla coda del percorso scelto.
///
/// È materiale del banco: la forma minima che serve a misurare, non quella del prodotto.
public final class ThumbnailPipeline: @unchecked Sendable {
  // `@unchecked`: `OperationQueue` è thread-safe ma non è annotata `Sendable`.
  public let path: ThumbnailPath
  public let width: Int
  public let side: CGFloat
  public let scale: CGFloat
  private let queues: [PipelineQueueKind: OperationQueue]
  private let failures = Mutex(0)

  public init(path: ThumbnailPath, width: Int, side: CGFloat, scale: CGFloat) {
    self.path = path
    self.width = max(1, width)
    self.side = side
    self.scale = scale
    var queues: [PipelineQueueKind: OperationQueue] = [:]
    for kind in PipelineQueueKind.allCases {
      let queue = OperationQueue()
      queue.name = "spike01.\(kind.rawValue)"
      queue.maxConcurrentOperationCount = self.width
      queue.qualityOfService = .utility
      queues[kind] = queue
    }
    self.queues = queues
  }

  /// Lato in pixel dell'anteprima prodotta.
  public var maxPixelSize: Int { Int((side * scale).rounded()) }

  /// Anteprime non prodotte per errore del percorso (non per annullamento).
  public var failureCount: Int { failures.withLock { $0 } }

  /// Chiede l'anteprima di `url`. `completion` è chiamato su un thread della pipeline con
  /// l'immagine, oppure `nil` se il percorso fallisce; non è chiamato se la richiesta è annullata.
  @discardableResult
  public func requestThumbnail(
    for url: URL, priority: Operation.QueuePriority = .normal,
    completion: @escaping @Sendable (CGImage?) -> Void
  ) -> ThumbnailTicket {
    let ticket = ThumbnailTicket()
    let path = path
    let side = side
    let scale = scale
    let thumbnailQueue = queues[path.queue]!
    // Le operazioni catturano il biglietto in modo debole: il biglietto trattiene le operazioni
    // per poterle annullare, e un riferimento forte nei due versi tratterrebbe per sempre
    // operazioni, completamento e tutto ciò che il completamento cattura.
    let io = BlockOperation { [self, weak ticket] in
      guard ticket?.isCancelled != true else { return }
      _ = try? ThumbnailWork.readResourceKeys(url)
      guard ticket?.isCancelled != true else { return }
      let produce = BlockOperation { [weak ticket] in
        defer { ticket?.detachAll() }
        guard ticket?.isCancelled != true else { return }
        let image = autoreleasepool {
          ThumbnailWork.thumbnail(url, path: path, side: side, scale: scale)
        }
        guard ticket?.isCancelled != true else { return }
        if image == nil { self.failures.withLock { $0 += 1 } }
        completion(image)
      }
      produce.queuePriority = priority
      ticket?.attach(produce)
      thumbnailQueue.addOperation(produce)
    }
    io.queuePriority = priority
    ticket.attach(io)
    queues[.io]!.addOperation(io)
    return ticket
  }

  /// Accoda il carico di visione artificiale su `url`.
  public func requestVision(for url: URL, priority: Operation.QueuePriority = .low) {
    let operation = BlockOperation {
      autoreleasepool { _ = try? ThumbnailWork.visionFeaturePrint(url) }
    }
    operation.queuePriority = priority
    queues[.vision]!.addOperation(operation)
  }

  /// Lavoro in attesa o in esecuzione per coda.
  public func depths() -> [PipelineQueueKind: Int] {
    queues.mapValues(\.operationCount)
  }

  /// Annulla tutto il lavoro accodato.
  public func cancelAll() {
    for queue in queues.values { queue.cancelAllOperations() }
  }

  /// Ferma le code e attende che le operazioni in corso terminino, senza bloccare il thread
  /// principale.
  public func drain() async {
    cancelAll()
    while queues.values.contains(where: { $0.operationCount > 0 }) {
      try? await Task.sleep(for: .milliseconds(20))
    }
  }
}

/// Contenitore thread-safe per il risultato di una chiamata asincrona attesa con un semaforo.
final class ResultBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value?

  func set(_ newValue: Value?) {
    lock.withLock { value = newValue }
  }

  func get() -> Value? {
    lock.withLock { value }
  }
}
