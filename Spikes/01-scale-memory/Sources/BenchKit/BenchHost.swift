import AppKit
import QuartzCore

/// Geometria dichiarata della griglia: porta di vista, lato dell'elemento e spaziatura.
public struct GridGeometry: Sendable {
  public var viewport: CGSize
  public var itemSide: CGFloat = 240
  public var spacing: CGFloat = 8

  public init(viewport: CGSize, itemSide: CGFloat = 240, spacing: CGFloat = 8) {
    self.viewport = viewport
    self.itemSide = itemSide
    self.spacing = spacing
  }

  /// Colonne della griglia alla larghezza della porta di vista.
  public var columns: Int {
    max(1, Int((viewport.width + spacing) / (itemSide + spacing)))
  }

  /// Passo verticale fra due righe.
  public var rowPitch: CGFloat { itemSide + spacing }

  /// Righe che intersecano una porta di vista posta a `y = 0`.
  public var rowsPerScreen: Int {
    max(1, Int((viewport.height / rowPitch).rounded(.up)))
  }

  /// Elementi che intersecano la porta di vista iniziale, dedotti dalla geometria.
  public var initialVisibleCount: Int { columns * rowsPerScreen }

  /// Parametri da registrare nel risultato.
  public var parameters: [String: String] {
    [
      "window": "\(Int(viewport.width))x\(Int(viewport.height))",
      "itemSide": "\(Int(itemSide))",
      "spacing": "\(Int(spacing))",
      "columns": "\(columns)",
    ]
  }
}

/// Elemento della griglia: un `NSImageView` con segnaposto grigio finché l'anteprima non arriva.
final class ThumbnailCell: NSCollectionViewItem {
  static let identifier = NSUserInterfaceItemIdentifier("ThumbnailCell")

  override func loadView() {
    let imageView = NSImageView()
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.wantsLayer = true
    imageView.layer?.backgroundColor = NSColor.systemGray.cgColor
    imageView.layer?.borderColor = NSColor.controlAccentColor.cgColor
    view = imageView
    self.imageView = imageView
  }

  override var isSelected: Bool {
    didSet { view.layer?.borderWidth = isSelected ? 4 : 0 }
  }

  func show(_ image: CGImage?) {
    imageView?.image = image.map { NSImage(cgImage: $0, size: .zero) }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    imageView?.image = nil
  }
}

/// Host AppKit del banco: una finestra con `NSCollectionView` dentro un `NSScrollView`,
/// dimensionata sulla porta di vista dichiarata.
///
/// È **strumentazione di misura**, non interfaccia di prodotto: serve perché la prima schermata e
/// la latenza della selezione includano il costo di composizione e presentazione del fotogramma.
@MainActor
public final class BenchHost: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
  public let geometry: GridGeometry
  public let window: NSWindow
  public let scrollView: NSScrollView
  public let collectionView: NSCollectionView

  /// File mostrati, nell'ordine della griglia.
  public private(set) var urls: [URL] = []
  /// Anteprime assegnate e trattenute dall'host, per indice.
  public private(set) var images: [Int: CGImage] = [:]

  /// Chiamato quando una cella viene configurata per un indice (l'elemento entra in vista).
  public var onCellShown: ((Int) -> Void)?
  /// Chiamato quando la selezione cambia per un'azione utente (tastiera compresa).
  public var onSelectionChanged: ((Set<IndexPath>) -> Void)?

  public init(geometry: GridGeometry) {
    self.geometry = geometry
    let layout = NSCollectionViewFlowLayout()
    layout.itemSize = CGSize(width: geometry.itemSide, height: geometry.itemSide)
    layout.minimumInteritemSpacing = geometry.spacing
    layout.minimumLineSpacing = geometry.spacing
    layout.sectionInset = NSEdgeInsetsZero

    collectionView = NSCollectionView(frame: CGRect(origin: .zero, size: geometry.viewport))
    collectionView.collectionViewLayout = layout
    collectionView.isSelectable = true
    collectionView.allowsMultipleSelection = false
    collectionView.backgroundColors = [.windowBackgroundColor]
    collectionView.register(ThumbnailCell.self, forItemWithIdentifier: ThumbnailCell.identifier)

    scrollView = NSScrollView(frame: CGRect(origin: .zero, size: geometry.viewport))
    scrollView.documentView = collectionView
    scrollView.hasVerticalScroller = true
    scrollView.scrollerStyle = .overlay
    scrollView.autoresizingMask = [.width, .height]

    window = NSWindow(
      contentRect: CGRect(origin: .zero, size: geometry.viewport),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = "iMAGE Surfer — banco del cancello n°1 (strumentazione di misura)"
    window.contentView = scrollView
    super.init()
    collectionView.dataSource = self
    collectionView.delegate = self
  }

  /// Fattore di scala dello schermo su cui si trova la finestra.
  public var screenScale: CGFloat { window.backingScaleFactor }

  /// Descrizione dello schermo della finestra, da registrare nel risultato.
  public var screenParameters: [String: String] {
    let screen = window.screen
    return [
      "screenScaleFactor": "\(screenScale)",
      "screenSize": screen.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "?",
      "screenName": screen?.localizedName ?? "?",
    ]
  }

  /// Mostra la finestra in primo piano e attende che sia stata presentata almeno una volta.
  /// Preferisce uno schermo Retina (fattore di scala 2), come il display di riferimento.
  public func show() async {
    if let retina = NSScreen.screens.first(where: { $0.backingScaleFactor >= 2 }) {
      let frame = retina.visibleFrame
      window.setFrameOrigin(
        CGPoint(
          x: frame.midX - window.frame.width / 2,
          y: max(frame.minY, frame.midY - window.frame.height / 2)))
    } else {
      window.center()
    }
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(collectionView)
    await nextFrame()
    try? await Task.sleep(for: .milliseconds(200))
    await nextFrame()
  }

  /// Chiude la finestra e rilascia tutte le anteprime.
  public func close() {
    images.removeAll()
    urls.removeAll()
    collectionView.reloadData()
    window.orderOut(nil)
    window.close()
  }

  /// Prova a secco prima della baseline: carica AppKit, ImageIO, Quick Look e la composizione
  /// della finestra, e porta allo stato di regime le code della pipeline (un thread per
  /// operazione, con lo stato di decodifica di ogni codec), così che la baseline di memoria sia
  /// quella dell'host vuoto a regime e non del processo appena avviato. Usa file sintetici
  /// temporanei, mai file del dataset.
  public static func warmUp(geometry: GridGeometry, scale: CGFloat, queueWidth: Int) async {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "spike01-warmup-\(ProcessInfo.processInfo.processIdentifier)")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let count = geometry.initialVisibleCount
    let files = (0..<count).map { index in
      let format = ImageFormat.allCases[index % ImageFormat.allCases.count]
      return directory.appending(path: String(format: "warmup-%03d.", index) + format.fileExtension)
    }
    await Task.detached {
      DispatchQueue.concurrentPerform(iterations: files.count) { index in
        let format = ImageFormat.allCases[index % ImageFormat.allCases.count]
        let image = ImageSynthesis.makeImage(width: 2_016, height: 1_512, seed: UInt64(index + 1))
        try? ImageSynthesis.write(image, format: format, quality: 0.8, to: files[index])
      }
    }.value

    for path in ThumbnailPath.allCases {
      let host = BenchHost(geometry: geometry)
      await host.show()
      host.setURLs(files)
      let pipeline = ThumbnailPipeline(
        path: path, width: queueWidth, side: geometry.itemSide, scale: scale)
      let remaining = MainActorCounter(files.count)
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        for (index, file) in files.enumerated() {
          pipeline.requestThumbnail(for: file) { image in
            DispatchQueue.main.async {
              MainActor.assumeIsolated {
                host.assign(image, at: index)
                if remaining.decrement() == 0 { continuation.resume() }
              }
            }
          }
        }
      }
      await host.nextFrame()
      await pipeline.drain()
      host.close()
    }
    try? await Task.sleep(for: .seconds(1))
  }

  // MARK: - Contenuto

  /// Sostituisce l'intero contenuto della griglia.
  public func setURLs(_ newURLs: [URL]) {
    urls = newURLs
    images.removeAll()
    collectionView.reloadData()
    collectionView.layoutSubtreeIfNeeded()
  }

  /// Aggiunge file in coda alla griglia.
  public func appendURLs(_ more: [URL]) {
    guard !more.isEmpty else { return }
    let start = urls.count
    urls.append(contentsOf: more)
    let paths = Set((start..<urls.count).map { IndexPath(item: $0, section: 0) })
    collectionView.insertItems(at: paths)
  }

  /// Assegna l'anteprima di un elemento: la trattiene e aggiorna la cella se è in vista.
  public func assign(_ image: CGImage?, at index: Int) {
    if let image { images[index] = image } else { images.removeValue(forKey: index) }
    if let cell = collectionView.item(at: IndexPath(item: index, section: 0)) as? ThumbnailCell {
      cell.show(image)
    }
  }

  /// Rilascia l'anteprima trattenuta di un elemento.
  public func release(at index: Int) {
    guard images.removeValue(forKey: index) != nil else { return }
    if let cell = collectionView.item(at: IndexPath(item: index, section: 0)) as? ThumbnailCell {
      cell.show(nil)
    }
  }

  // MARK: - Geometria e scorrimento

  /// Indici degli elementi che intersecano la porta di vista attuale, secondo il layout.
  public func visibleIndices() -> [Int] {
    collectionView.layoutSubtreeIfNeeded()
    let rect = scrollView.contentView.documentVisibleRect
    let attributes =
      collectionView.collectionViewLayout?.layoutAttributesForElements(in: rect) ?? []
    return attributes.compactMap {
      $0.representedElementCategory == .item ? $0.indexPath?.item : nil
    }
    .filter { $0 < urls.count }
    .sorted()
  }

  /// Altezza totale del contenuto.
  public var documentHeight: CGFloat {
    collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
  }

  /// Altezza di una schermata (la porta di vista).
  public var screenHeight: CGFloat { scrollView.contentView.bounds.height }

  /// Massimo scostamento verticale raggiungibile: lo limita la cornice della vista documento,
  /// non soltanto l'altezza dichiarata dal layout.
  public var maxOffset: CGFloat {
    max(0, min(documentHeight, collectionView.frame.height) - screenHeight)
  }

  /// Scostamento verticale attuale.
  public var offset: CGFloat { scrollView.contentView.bounds.origin.y }

  /// Porta la vista allo scostamento verticale indicato.
  public func scroll(to y: CGFloat) {
    let clamped = min(max(0, y), maxOffset)
    scrollView.contentView.scroll(to: CGPoint(x: 0, y: clamped))
    scrollView.reflectScrolledClipView(scrollView.contentView)
  }

  /// Vero se la finestra è almeno in parte visibile (non occlusa, schermo acceso).
  public var isVisibleOnScreen: Bool { window.occlusionState.contains(.visible) }

  /// Frazione degli elementi in vista che hanno già l'anteprima, dalla geometria.
  public func visibleFilledFraction() -> Double {
    guard !urls.isEmpty else { return 0 }
    let firstRow = max(0, Int((offset / geometry.rowPitch).rounded(.down)))
    let lastRow = Int(((offset + screenHeight) / geometry.rowPitch).rounded(.down))
    let first = firstRow * geometry.columns
    let last = min(urls.count, (lastRow + 1) * geometry.columns)
    guard first < last else { return 0 }
    let filled = (first..<last).filter { images[$0] != nil }.count
    return Double(filled) / Double(last - first)
  }

  /// Riga della griglia che contiene l'elemento.
  public func row(of index: Int) -> Int { index / geometry.columns }

  /// Distanza dell'elemento dalla porta di vista attuale, in schermate (0 se è in vista).
  public func distanceInScreens(ofRow row: Int) -> CGFloat {
    let top = CGFloat(row) * geometry.rowPitch
    let bottom = top + geometry.itemSide
    let viewTop = offset
    let viewBottom = offset + screenHeight
    if bottom < viewTop { return (viewTop - bottom) / screenHeight }
    if top > viewBottom { return (top - viewBottom) / screenHeight }
    return 0
  }

  // MARK: - Oracolo del fotogramma

  /// Attende il completamento della prossima transazione Core Animation.
  public func nextFrame() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      CATransaction.setCompletionBlock { continuation.resume() }
      window.contentView?.needsDisplay = true
    }
  }

  // MARK: - NSCollectionViewDataSource

  public func collectionView(
    _ collectionView: NSCollectionView, numberOfItemsInSection section: Int
  ) -> Int {
    urls.count
  }

  public func collectionView(
    _ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath
  ) -> NSCollectionViewItem {
    let item = collectionView.makeItem(withIdentifier: ThumbnailCell.identifier, for: indexPath)
    if let cell = item as? ThumbnailCell {
      cell.show(images[indexPath.item])
    }
    onCellShown?(indexPath.item)
    return item
  }

  // MARK: - NSCollectionViewDelegate

  public func collectionView(
    _ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>
  ) {
    onSelectionChanged?(collectionView.selectionIndexPaths)
  }
}

/// Contatore posseduto dal thread principale.
@MainActor
final class MainActorCounter {
  private var value: Int

  init(_ value: Int) {
    self.value = value
  }

  /// Decrementa e restituisce il nuovo valore.
  func decrement() -> Int {
    value -= 1
    return value
  }
}
