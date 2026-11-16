// Schema del JSON di misura della matrice degli arresti (`crashbench run-matrix`), e unione di più
// esecuzioni parziali della stessa misura in un unico JSON (`crashbench combine-matrix`).
//
// Ogni cifra di `RESULT.md` viene da questo JSON. Il JSON è scritto con chiavi ordinate e
// indentato; i campi opzionali assenti sono omessi.
//
// **Esecuzioni parziali (adattamento locale).** Ogni comando del banco ha un tetto di durata, e la
// matrice `full` non sta in una sola esecuzione. `run-matrix` accetta quindi una selezione di celle
// (`--only`, `--shard k/n`) e un `--measurement-id` condiviso; `combine-matrix` unisce le parti in
// un'unica misura con un solo `measurementId`, rifiutando parti che dichiarano un host, un digest
// del manifest, un profilo o un numero di ripetizioni diversi, o che si sovrappongono su una cella,
// e dichiara in `coverage` se l'unione copre esattamente le celle del profilo. L'invocazione senza
// selezione resta quella del piano: tutta la matrice, un solo JSON.

import Foundation

/// Profilo della matrice.
public enum MatrixProfile: String, Codable, Sendable, CaseIterable {
  /// Tutte le celle: 98 di base più 48 di perturbazione, con la fixture.
  case full
  /// Il sottoinsieme rapido dei test di integrazione: 6 punti con le loro strategie, più 2 celle di
  /// perturbazione.
  case smoke

  /// Ripetizioni per cella quando `--repetitions` non è dato.
  public var defaultRepetitions: Int {
    switch self {
    case .full: 5
    case .smoke: 1
    }
  }
}

/// Esito dell'oracolo della separazione: le separazioni osservate dal banco nell'istantanea da cui
/// parte il recupero, confrontate con `SEPARAZIONI-ALL-AVVIO`.
public enum SeparationDetection: String, Codable, Sendable, CaseIterable {
  /// Le due liste coincidono e non sono vuote.
  case rilevata
  /// Almeno una separazione osservata non è riferita (prevale su una falsa segnalazione).
  case nonRilevata = "non-rilevata"
  /// Ogni separazione osservata è riferita, ma ne è riferita almeno una che l'istantanea non mostra.
  case falsaSegnalazione = "falsa-segnalazione"
  /// Nessuna separazione, né osservata né riferita.
  case nessuna
}

/// Il volume di lavoro su cui è stata eseguita la misura.
public struct MeasurementVolume: Codable, Sendable, Equatable {
  public var name: String
  /// Formato dell'immagine disco: `ASIF`.
  public var format: String
  /// Dimensione nella sintassi di `diskutil image create --size`: `64m`.
  public var size: String
  public var fs: String

  /// Il volume di `WorkVolume`.
  public static let workVolume = MeasurementVolume(
    name: WorkVolume.volumeName, format: "ASIF", size: WorkVolume.imageSize, fs: "APFS")
}

/// Parametri della cattura assestata delle istantanee.
///
/// Il Cestino di sistema aggiorna `.Trashes/<uid>` in modo asincrono (`UF_HIDDEN` e
/// `com.apple.FinderInfo` dopo la prima voce, `.DS_Store` riscritto dopo le successive, circa
/// 0,2-0,3 s dopo a riposo): un'istantanea presa subito può precedere l'aggiornamento. Un'istantanea
/// è **assestata** quando `stableCaptures` catture consecutive, a `intervalSeconds` l'una
/// dall'altra, coincidono con la precedente; se non lo diventa entro `maxWaitSeconds`, si usa
/// l'ultima cattura e il fatto si registra nella cella.
public struct SettleParameters: Codable, Sendable, Equatable {
  public var intervalSeconds: Double
  public var stableCaptures: Int
  public var maxWaitSeconds: Double

  /// 3 catture uguali a 0,25 s (0,75 s di quiete, circa tre volte il ritardo misurato), al più
  /// 10 s.
  public static let standard = SettleParameters(
    intervalSeconds: 0.25, stableCaptures: 3, maxWaitSeconds: 10)
}

/// Selezione di celle di un'esecuzione parziale.
public struct MatrixSelection: Codable, Sendable, Equatable {
  /// Modelli `fnmatch` sull'ID di cella, in OR; `nil` se non dati.
  public var only: [String]?
  /// `k/n`: la parte `k` di `n`, a rotazione sull'elenco ordinato delle celle selezionate.
  public var shard: String?

  public init(only: [String]?, shard: String?) {
    self.only = only
    self.shard = shard
  }
}

/// Copertura delle celle di una misura rispetto al profilo dichiarato.
public struct MeasurementCoverage: Codable, Sendable, Equatable {
  /// Celle del profilo.
  public var expectedCells: Int
  /// Celle presenti nella misura.
  public var presentCells: Int
  /// Vero se le celle presenti sono esattamente quelle del profilo.
  public var complete: Bool
  /// Celle del profilo assenti dalla misura, nell'ordine del profilo.
  public var missingCells: [String]
  /// Celle della misura che il profilo non prevede.
  public var unexpectedCells: [String]

  /// Copertura di `present` rispetto a `expected`.
  public static func of(present: [String], expected: [String]) -> MeasurementCoverage {
    let presentSet = Set(present)
    let expectedSet = Set(expected)
    let missing = expected.filter { !presentSet.contains($0) }
    let unexpected = present.filter { !expectedSet.contains($0) }
    return MeasurementCoverage(
      expectedCells: expected.count, presentCells: present.count,
      complete: missing.isEmpty && unexpected.isEmpty, missingCells: missing,
      unexpectedCells: unexpected)
  }
}

/// Una parte di una misura unita da `combine-matrix`.
public struct MeasurementPart: Codable, Sendable, Equatable {
  /// Nome del file della parte.
  public var file: String
  public var startedAt: String
  public var durationSeconds: Double
  public var selection: MatrixSelection?
  public var cells: Int
  /// Le operazioni preliminari della parte.
  public var preparation: [String]
}

/// Riepilogo della misura, ricalcolato dalle celle.
public struct MeasurementSummary: Codable, Sendable, Equatable {
  public var cells: Int
  public var applicableCells: Int
  /// Ripetizioni per tipo di esito, su tutte le celle.
  public var outcomes: [String: Int]
  /// Celle con almeno una ripetizione `NON_SUPPORTABILE`.
  public var nonSupportableCells: Int
  /// Celle `RICONOSCIMENTO_ERRATO`.
  public var recognitionErrorCells: Int
  /// Celle con almeno una ripetizione `PUNTO_NON_RAGGIUNTO`.
  public var pointNotReachedCells: Int
  public var nonDeterministicCells: Int
  /// Celle con almeno un'istantanea non assestata entro il limite.
  public var unsettledSnapshotCells: Int
  /// Celle con almeno un errore del banco (un figlio uscito in modo inatteso).
  public var benchErrorCells: Int

  /// Riepilogo delle celle date.
  public static func of(_ cells: [MeasurementCell]) -> MeasurementSummary {
    var outcomes: [String: Int] = [:]
    for cell in cells {
      for (kind, count) in cell.outcomes { outcomes[kind, default: 0] += count }
    }
    return MeasurementSummary(
      cells: cells.count,
      applicableCells: cells.filter(\.applicable).count,
      outcomes: outcomes,
      nonSupportableCells: cells.filter {
        ($0.outcomes[OutcomeKind.nonSupportabile.rawValue] ?? 0) > 0
      }.count,
      recognitionErrorCells: cells.filter(\.recognitionError).count,
      pointNotReachedCells: cells.filter { !$0.pointReached }.count,
      nonDeterministicCells: cells.filter(\.nonDeterministic).count,
      unsettledSnapshotCells: cells.filter { !$0.snapshotsNotSettled.isEmpty }.count,
      benchErrorCells: cells.filter { !$0.benchErrors.isEmpty }.count)
  }
}

/// Stato di un passo riferito dal recupero nella riga `PASSO`.
public struct CellStep: Codable, Sendable, Equatable {
  /// Stato all'avvio del recupero: `fatto`, `non-fatto`, `saltato`, `sospeso`, `non-riconoscibile`.
  public var start: String
  /// Stato finale, con lo stesso vocabolario.
  public var final: String
  public var errorClass: String?
  public var errorScope: String?
}

/// Posizioni di immagine e sidecar di un'operazione, calcolate dal banco su un'istantanea.
public struct CellPair: Codable, Sendable, Equatable {
  public var image: FilePosition
  public var sidecar: FilePosition
  public var separated: Bool
}

/// Oracolo della compensazione: `Snapshot.diff(pre, post)`.
public struct CompensationOracle: Codable, Sendable, Equatable {
  /// Vero se la direzione effettiva del recupero è `compensate` (riga `RECUPERO … direzione=…`).
  public var attempted: Bool
  /// Vero se e solo se entrambi gli elenchi sono vuoti; `nil` se la compensazione non è tentata.
  public var matchesPre: Bool?
  /// Scostamenti diversi dall'`mtime` di una directory.
  public var fileDeviations: [Deviation]
  /// Scostamenti `mtime` di una directory.
  public var directoryMtimeDeviations: [Deviation]

  /// Compensazione non tentata.
  public static let notAttempted = CompensationOracle(
    attempted: false, matchesPre: nil, fileDeviations: [], directoryMtimeDeviations: [])
}

/// Fallimento registrato dal recupero nel log di intenti (`step-failed`).
public struct ObservedFailure: Codable, Sendable, Equatable {
  /// Passo, oppure `prepare` per la preparazione e la sua compensazione.
  public var stepId: String
  public var direction: String
  public var syscall: String
  public var errno: Int32?
  public var cocoa: String?
  public var errorClass: String?
  public var scope: String?
}

/// Esiti di un ramo dopo un `bloccato`: `decide retry` oppure `decide abandon`.
public struct FollowUpResult: Codable, Sendable, Equatable {
  /// Rami eseguiti fino alla decisione.
  public var repetitions: Int
  public var outcomes: [String: Int]
  /// Motivi di `NON_SUPPORTABILE`, con i conteggi.
  public var reasons: [String: Int]
  /// Traccia del primo ramo.
  public var trace: [String]
  /// Posizioni riferite dalle righe `COPPIA` del primo ramo: `immagine=<pos> sidecar=<pos>`.
  public var reportedPairs: [String: String]
}

/// I due rami dopo un `bloccato`.
public struct FollowUp: Codable, Sendable, Equatable {
  /// Ramo `retry`, su una ripetizione nuova: `unperturb`, poi `decide retry`.
  public var retry: FollowUpResult?
  /// Ramo `abandon`, sulla stessa ripetizione: `decide abandon`.
  public var abandon: FollowUpResult?
}

/// Statistiche della cattura assestata delle istantanee di una cella.
public struct SettleStatistics: Codable, Sendable, Equatable {
  /// Istantanee assestate catturate.
  public var captures: Int
  /// Quelle in cui il disco è cambiato durante l'attesa.
  public var changed: Int
  /// Il ritardo più lungo fra l'inizio di una cattura e l'ultimo cambiamento osservato.
  public var maxLastChangeSeconds: Double
}

/// Una cella della matrice, con gli esiti di tutte le ripetizioni e gli oracoli della prima.
public struct MeasurementCell: Codable, Sendable, Equatable {
  /// `<punto>/<strategia>[/<classe>]`.
  public var cellId: String
  public var point: String
  public var phase: CrashPhase
  public var strategy: RecoveryStrategy
  /// Classe di errore applicata fra l'arresto e il recupero, per le celle di perturbazione.
  public var perturbation: ErrorClass?
  /// Passo bersaglio della perturbazione, se ne ha uno.
  public var target: String?
  public var applicable: Bool
  public var notApplicableReason: String?
  /// Ripetizioni eseguite.
  public var repetitions: Int
  /// Ripetizioni per tipo di esito: `{"completato": 5}`.
  public var outcomes: [String: Int]
  /// Motivi di `NON_SUPPORTABILE`, con i conteggi.
  public var reasons: [String: Int]
  /// Direzione effettiva del recupero (`forward`, `compensate`, `nessuna`), dalla prima ripetizione.
  public var direction: String?
  public var recordTroncato: Bool?
  /// Righe `DIVERGENZA` del recupero, senza il prefisso.
  public var divergences: [String]
  /// Righe `TRACCIA` del recupero, senza il prefisso.
  public var trace: [String]
  /// Stato di ogni passo per `stepId`, dalle righe `PASSO`.
  public var steps: [String: CellStep]
  /// Posizioni di immagine e sidecar per `opId`, dall'istantanea `post`.
  public var pairs: [String: CellPair]
  /// Separazioni osservate dal banco nell'istantanea da cui parte il recupero che riferisce l'esito:
  /// dopo l'arresto; per le celle di perturbazione dopo la perturbazione; per `D01` e `D02` dopo il
  /// secondo arresto.
  public var separationsAtCrash: [String]
  /// Separazioni all'arresto prima della perturbazione, solo per le celle di perturbazione.
  public var separationsBeforePerturbation: [String]?
  /// Separazioni al primo arresto, solo per `D01` e `D02`.
  public var separationsAtFirstCrash: [String]?
  /// `SEPARAZIONI-ALL-AVVIO` del recupero.
  public var separationsReported: [String]
  /// `SEPARAZIONI-RESIDUE` del recupero.
  public var separationsResidual: [String]
  public var separationDetected: SeparationDetection?
  public var compensation: CompensationOracle
  /// Per gli esiti `completato`: percorsi e digest di `post` uguali al lotto completato atteso.
  public var resumeMatchesExpected: Bool?
  /// Le differenze dal lotto completato atteso.
  public var resumeMismatches: [String]
  /// Vero se in almeno una ripetizione una riga `COPPIA` dichiara una posizione diversa
  /// dall'istantanea: la cella è `RICONOSCIMENTO_ERRATO`.
  public var recognitionError: Bool
  /// Le affermazioni smentite, una per riga: `r<n> OP2 immagine: dichiarata dest, istantanea orig`.
  public var recognitionErrors: [String]
  public var followUp: FollowUp?
  /// Classe adottata dal recupero per il primo fallimento classificato (o dalle righe `PASSO`).
  public var errorClass: ErrorClass?
  public var errorScope: ErrorScope?
  public var errnoObserved: Int32?
  public var cocoaObserved: String?
  public var syscallObserved: String?
  /// I fallimenti `step-failed` registrati dal recupero, dalla prima ripetizione.
  public var failures: [ObservedFailure]
  public var nonDeterministic: Bool
  public var repetitionNotes: [String]
  /// Falso se in almeno una ripetizione il figlio non è morto per segnale 9 nel punto chiesto.
  public var pointReached: Bool
  /// Istantanee non assestate entro il limite: `r<n>:<istantanea>`.
  public var snapshotsNotSettled: [String]
  public var settle: SettleStatistics
  /// Figli usciti in modo inatteso, con stato e stderr.
  public var benchErrors: [String]
  public var durationSeconds: Double

  /// Marcatori della cella: `NON_SUPPORTABILE`, `RICONOSCIMENTO_ERRATO`, `PUNTO_NON_RAGGIUNTO`,
  /// `nonDeterministica`.
  public var marks: [String] {
    var marks: [String] = []
    if (outcomes[OutcomeKind.nonSupportabile.rawValue] ?? 0) > 0 {
      marks.append(OutcomeKind.nonSupportabile.rawValue)
    }
    if recognitionError { marks.append("RICONOSCIMENTO_ERRATO") }
    if !pointReached { marks.append("PUNTO_NON_RAGGIUNTO") }
    if nonDeterministic { marks.append("nonDeterministica") }
    return marks
  }
}

/// Il JSON di misura della matrice.
public struct MeasurementResult: Codable, Sendable, Equatable {
  /// `crash-matrix-<UTC yyyyMMdd'T'HHmmss'Z'>-<8 esadecimali>`.
  public var measurementId: String
  /// `04-crash-recovery`.
  public var spike: String
  public var host: HostFingerprint
  public var volume: MeasurementVolume
  /// SHA-256 di `fixtures/MANIFEST.json`.
  public var fixtureManifestSha256: String
  public var profile: MatrixProfile
  /// Ripetizioni per cella.
  public var repetitions: Int
  /// ISO 8601 UTC.
  public var startedAt: String
  public var durationSeconds: Double
  /// L'elenco completo di `list-points`.
  public var points: [CrashPoint]
  public var settleParameters: SettleParameters
  /// Selezione di un'esecuzione parziale; assente per la matrice intera e per una misura unita.
  public var selection: MatrixSelection?
  /// Operazioni preliminari: `setup`, riscaldamento del Cestino, rimozione di una perturbazione.
  public var preparation: [String]
  /// Le parti di una misura unita da `combine-matrix`.
  public var parts: [MeasurementPart]?
  public var coverage: MeasurementCoverage
  public var summary: MeasurementSummary
  /// Celle nell'ordine del profilo.
  public var cells: [MeasurementCell]

  /// Nome dello spike nel JSON.
  public static let spikeName = "04-crash-recovery"

  /// JSON con chiavi ordinate e indentato, terminato da un a capo.
  public func jsonData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    var data = try encoder.encode(self)
    data.append(Data("\n".utf8))
    return data
  }

  /// Rilegge una misura scritta da `jsonData()`.
  public static func load(from url: URL) throws -> MeasurementResult {
    try JSONDecoder().decode(MeasurementResult.self, from: Data(contentsOf: url))
  }

  /// Il digest di `fixtures/MANIFEST.json`.
  public static func fixtureManifestDigest() throws -> String {
    try Fixtures.sha256Hex(
      ofFileAt: CrashPaths.fixtures.appending(
        path: Fixtures.manifestFileName, directoryHint: .notDirectory))
  }

  // MARK: - Identificativo

  /// Un nuovo `measurementId` per l'istante dato.
  public static func newMeasurementId(at date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    let suffix = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(8)
    return "crash-matrix-\(formatter.string(from: date))-\(suffix)"
  }

  /// Vero se `id` ha la forma di un `measurementId`.
  public static func isValidMeasurementId(_ id: String) -> Bool {
    id.wholeMatch(of: /crash-matrix-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}/) != nil
  }

  /// Istante in ISO 8601 UTC, al secondo.
  public static func timestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: date)
  }

  // MARK: - Unione di esecuzioni parziali

  /// Unisce le parti di una stessa misura in un'unica misura, in modo deterministico.
  ///
  /// Le parti devono dichiarare lo stesso `measurementId`, lo stesso host, lo stesso volume, lo
  /// stesso digest del manifest, lo stesso profilo, le stesse ripetizioni, gli stessi punti e gli
  /// stessi parametri di assestamento, e nessuna cella può comparire in due parti. La misura unita
  /// ha le celle nell'ordine di `canonicalCells` (le celle sconosciute in coda, per ID),
  /// `startedAt` della parte iniziata per prima, `durationSeconds` uguale alla somma delle parti,
  /// `parts` con la provenienza di ogni parte, e `coverage` rispetto a `canonicalCells`.
  ///
  /// - Parameter canonicalCells: gli ID di cella del profilo, nel loro ordine.
  /// - Throws: `MeasurementCombineError` se le parti non sono della stessa misura o si
  ///   sovrappongono.
  public static func combine(
    _ parts: [(file: String, result: MeasurementResult)], canonicalCells: [String]
  ) throws -> MeasurementResult {
    guard let (firstFile, first) = parts.first else { throw MeasurementCombineError.noParts }

    func require<T: Equatable>(_ field: String, _ value: (MeasurementResult) -> T) throws {
      for (file, part) in parts.dropFirst() where value(part) != value(first) {
        throw MeasurementCombineError.mismatch(
          field: field, file: file, expected: "\(value(first))", found: "\(value(part))",
          reference: firstFile)
      }
    }
    try require("measurementId", \.measurementId)
    try require("spike", \.spike)
    try require("host", \.host)
    try require("volume", \.volume)
    try require("fixtureManifestSha256", \.fixtureManifestSha256)
    try require("profile", \.profile)
    try require("repetitions", \.repetitions)
    try require("points", { $0.points.map(\.id) })
    try require("settleParameters", \.settleParameters)

    var owner: [String: String] = [:]
    var cells: [MeasurementCell] = []
    var provenance: [MeasurementPart] = []
    for (file, part) in parts {
      for cell in part.cells {
        if let other = owner[cell.cellId] {
          throw MeasurementCombineError.overlap(cellId: cell.cellId, files: [other, file])
        }
        owner[cell.cellId] = file
        cells.append(cell)
      }
      provenance +=
        part.parts
        ?? [
          MeasurementPart(
            file: file, startedAt: part.startedAt, durationSeconds: part.durationSeconds,
            selection: part.selection, cells: part.cells.count, preparation: part.preparation)
        ]
    }

    let order = Dictionary(
      canonicalCells.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    cells.sort { lhs, rhs in
      switch (order[lhs.cellId], order[rhs.cellId]) {
      case (let left?, let right?): left < right
      case (.some, nil): true
      case (nil, .some): false
      case (nil, nil): lhs.cellId < rhs.cellId
      }
    }
    provenance.sort { ($0.startedAt, $0.file) < ($1.startedAt, $1.file) }

    var combined = first
    combined.startedAt = parts.map(\.result.startedAt).min() ?? first.startedAt
    combined.durationSeconds = parts.map(\.result.durationSeconds).reduce(0, +)
    combined.selection = nil
    combined.preparation = []
    combined.parts = provenance
    combined.cells = cells
    combined.coverage = .of(present: cells.map(\.cellId), expected: canonicalCells)
    combined.summary = .of(cells)
    return combined
  }
}

/// Parti che non si possono unire in un'unica misura.
public enum MeasurementCombineError: Error, Equatable, CustomStringConvertible, LocalizedError {
  case noParts
  /// Un campo di testata di `file` è diverso da quello della parte di riferimento.
  case mismatch(field: String, file: String, expected: String, found: String, reference: String)
  /// Una cella compare in due parti.
  case overlap(cellId: String, files: [String])

  public var description: String {
    switch self {
    case .noParts:
      "nessuna parte da unire"
    case .mismatch(let field, let file, let expected, let found, let reference):
      "\(file): \(field) diverso da \(reference) (\(found) invece di \(expected)): le parti non "
        + "sono della stessa misura"
    case .overlap(let cellId, let files):
      "la cella \(cellId) compare in più parti: \(files.joined(separator: ", "))"
    }
  }

  public var errorDescription: String? { description }
}
