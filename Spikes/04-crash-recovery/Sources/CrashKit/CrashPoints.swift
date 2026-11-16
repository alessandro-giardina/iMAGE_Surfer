// Punti di interruzione del lotto e iniettore dell'arresto.
//
// L'elenco non è scritto a mano: `CrashPoints.enumerate(_:)` lo ricava dai passi del piano, così
// che un passo in più, o un tipo diverso, cambi i punti senza che nessuno debba ricordarsene. Sono
// costanti del piano solo i quattro punti di testa (`X00`…`X03`), il passo del record di fatto
// troncato (`S05`) e i due doppi arresti (`D01`, `D02`).
//
// Nel punto scelto il processo stampa `ARRESTO <id>: <descrizione>` e si uccide con
// `kill(getpid(), SIGKILL)`: nessuna pulizia, nessun `atexit`, nessun `defer`. In prova, al posto
// del segnale, l'iniettore lancia `SimulatedCrash`, che attraversa l'esecutore senza scritture.

import Darwin
import Foundation

/// Fase di un punto di interruzione.
public enum CrashPhase: String, Codable, Sendable, CaseIterable {
  /// Esecuzione del lotto in avanti: piano, ricontrollo, preparazione e passi.
  case esecuzione
  /// Annullamento di un lotto completato, chiesto dall'utente (FR-083).
  case compensazione
  /// Doppio arresto: il secondo cade durante il recupero dal primo.
  case doppio
}

/// Un punto di interruzione dell'elenco enumerato.
public struct CrashPoint: Codable, Sendable, Equatable {
  /// `X01-plan`, `S03-b`, `K05-a`, `D01`, …
  public let id: String
  public let phase: CrashPhase
  /// Momento dell'arresto, in una riga senza tabulazioni.
  public let description: String

  public init(id: String, phase: CrashPhase, description: String) {
    self.id = id
    self.phase = phase
    self.description = description
  }
}

/// Doppio arresto: un primo arresto durante l'esecuzione, poi un secondo durante il recupero con
/// la strategia data.
///
/// È anche il contenuto di `<data>/state/pending-second-crash.json`, che `run` scrive per `D01` e
/// `D02` e che il recupero legge per arrestarsi al secondo punto.
public struct CompositeCrash: Codable, Sendable, Equatable {
  /// `D01`, `D02`.
  public let id: String
  /// Punto del primo arresto, durante l'esecuzione del lotto.
  public let firstCrash: String
  /// Punto del secondo arresto, durante il recupero.
  public let secondCrash: String
  /// Strategia del recupero durante il quale cade il secondo arresto.
  public let strategy: RecoveryStrategy

  public init(id: String, firstCrash: String, secondCrash: String, strategy: RecoveryStrategy) {
    self.id = id
    self.firstCrash = firstCrash
    self.secondCrash = secondCrash
    self.strategy = strategy
  }

  /// Nome del file del secondo arresto in attesa, nella directory di stato.
  public static let pendingFileName = "pending-second-crash.json"

  /// `<data>/state/pending-second-crash.json`.
  public static func pendingURL(in volume: WorkVolume) -> URL {
    volume.stateDirectory.appending(path: pendingFileName, directoryHint: .notDirectory)
  }

  /// Scrive il doppio arresto in `pendingURL(in:)`, in JSON con chiavi ordinate. La directory di
  /// stato deve esistere.
  public func writePending(in volume: WorkVolume) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    try encoder.encode(self).write(to: Self.pendingURL(in: volume), options: .atomic)
  }

  /// Il doppio arresto in attesa, `nil` se il file non esiste. Non rimuove il file: lo consuma il
  /// recupero.
  public static func loadPending(in volume: WorkVolume) throws -> CompositeCrash? {
    let url = pendingURL(in: volume)
    guard FileManager.default.fileExists(atPath: url.fileSystemPath) else { return nil }
    return try JSONDecoder().decode(CompositeCrash.self, from: Data(contentsOf: url))
  }

  /// `DOPPIO-ARRESTO <id> primo=<punto> secondo=<punto> strategia=<resume|compensate>`.
  public var line: String {
    "DOPPIO-ARRESTO \(id) primo=\(firstCrash) secondo=\(secondCrash) strategia=\(strategy.rawValue)"
  }
}

/// Momento di un passo in cui cade un punto di interruzione: è il suffisso dell'ID.
public enum StepMoment: String, Sendable, CaseIterable {
  /// Intento registrato, azione non eseguita.
  case intent = "a"
  /// Temporaneo di copia scritto, non pubblicato: solo per i passi `copy`, solo in avanti.
  case tempWritten = "m"
  /// Azione eseguita, fatto non registrato.
  case acted = "b"
  /// Fatto registrato: solo in avanti.
  case recorded = "c"
}

/// Elenco enumerato dei punti di interruzione, ricavato dal piano.
public enum CrashPoints {
  /// Record del piano scritto a metà e sincronizzato.
  public static let planTorn = "X00-plan-torn"
  /// Dopo il record del piano.
  public static let planRecorded = "X01-plan"
  /// Dopo il ricontrollo delle precondizioni.
  public static let recheckDone = "X02-recheck"
  /// Dopo la preparazione delle cartelle.
  public static let prepared = "X03-prepare"
  /// Passo il cui record di fatto si scrive a metà nel punto `<passo>-torn`.
  public static let tornStepId = "S05"

  /// I punti in cui l'arresto cade dentro la scrittura di un record: `X00-plan-torn`, `S05-torn`.
  public static var tornPoints: [String] { [planTorn, tornPoint(tornStepId)] }

  /// I doppi arresti, nell'ordine dell'elenco.
  public static let composite: [CompositeCrash] = [
    CompositeCrash(id: "D01", firstCrash: "S03-b", secondCrash: "S08-b", strategy: .resume),
    CompositeCrash(id: "D02", firstCrash: "S03-b", secondCrash: "K02-a", strategy: .compensate),
  ]

  /// Il doppio arresto con l'ID dato, se esiste.
  public static func composite(_ id: String) -> CompositeCrash? {
    composite.first { $0.id == id }
  }

  /// ID del punto di un passo in avanti: `S03-a`, `S07-m`, `S03-b`, `S03-c`.
  public static func point(_ stepId: String, _ moment: StepMoment) -> String {
    "\(stepId)-\(moment.rawValue)"
  }

  /// ID del punto di un passo in compensazione: `K03-a`, `K03-b`. Per `Steps.prepareStepId`, la
  /// rimozione delle cartelle preparate, `K00-a` e `K00-b`.
  public static func compensationPoint(_ stepId: String, _ moment: StepMoment) -> String {
    let number = stepId == Steps.prepareStepId ? "00" : String(stepId.dropFirst())
    return "K\(number)-\(moment.rawValue)"
  }

  /// ID del punto del record di fatto troncato di un passo: `S05-torn`.
  public static func tornPoint(_ stepId: String) -> String {
    "\(stepId)-torn"
  }

  /// I punti di interruzione del piano, in quest'ordine:
  /// 1. `X00-plan-torn`, `X01-plan`, `X02-recheck`, `X03-prepare`;
  /// 2. per ogni passo, in ordine di piano: `Sxx-a`, `Sxx-m` (solo `copy`), `Sxx-b`, `Sxx-c`;
  /// 3. `S05-torn`, se il piano ha il passo `S05`;
  /// 4. per ogni passo, in ordine inverso: `Kxx-a`, `Kxx-b`; poi `K00-a`, `K00-b`;
  /// 5. i doppi arresti di `composite`.
  ///
  /// Con la fixture: 4 + 32 + 1 + 22 + 2 = 61 punti.
  public static func enumerate(_ plan: BatchPlan) -> [CrashPoint] {
    let folders = plan.directoriesToCreate.joined(separator: ", ")
    var points = [
      CrashPoint(
        id: planTorn, phase: .esecuzione,
        description: "record del piano scritto a metà e sincronizzato, nessuna azione eseguita"),
      CrashPoint(
        id: planRecorded, phase: .esecuzione,
        description: "piano registrato, precondizioni non ancora ricontrollate"),
      CrashPoint(
        id: recheckDone, phase: .esecuzione,
        description: "precondizioni ricontrollate, cartelle non ancora preparate"),
      CrashPoint(
        id: prepared, phase: .esecuzione,
        description: "cartelle preparate (\(folders.isEmpty ? "nessuna" : folders)), "
          + "nessun passo eseguito"),
    ]

    for step in plan.steps {
      let summary = summary(of: step)
      var moments: [(StepMoment, String)] = [(.intent, "intento registrato, azione non eseguita")]
      if step.kind == .copy {
        moments.append((.tempWritten, "temporaneo di copia scritto, non pubblicato"))
      }
      moments.append((.acted, "azione eseguita, fatto non registrato"))
      moments.append((.recorded, "fatto registrato"))
      for (moment, text) in moments {
        points.append(
          CrashPoint(
            id: point(step.id, moment), phase: .esecuzione, description: "\(text) (\(summary))"))
      }
    }

    if let step = plan.step(tornStepId) {
      points.append(
        CrashPoint(
          id: tornPoint(step.id), phase: .esecuzione,
          description: "azione eseguita, record di fatto scritto a metà e sincronizzato "
            + "(\(summary(of: step)))"))
    }

    for step in plan.steps.reversed() {
      let summary = summary(of: step)
      points.append(
        CrashPoint(
          id: compensationPoint(step.id, .intent), phase: .compensazione,
          description: "intento di compensazione registrato, compensazione non eseguita "
            + "(\(summary))"))
      points.append(
        CrashPoint(
          id: compensationPoint(step.id, .acted), phase: .compensazione,
          description: "compensazione eseguita, fatto non registrato (\(summary))"))
    }
    let created = folders.isEmpty ? "nessuna" : folders
    points.append(
      CrashPoint(
        id: compensationPoint(Steps.prepareStepId, .intent), phase: .compensazione,
        description: "passi compensati, cartelle create dal lotto non ancora rimosse "
          + "(\(created))"))
    points.append(
      CrashPoint(
        id: compensationPoint(Steps.prepareStepId, .acted), phase: .compensazione,
        description: "cartelle create dal lotto rimosse se vuote, esito non registrato "
          + "(\(created))"))

    for crash in composite {
      points.append(
        CrashPoint(
          id: crash.id, phase: .doppio,
          description: "doppio arresto: primo a \(crash.firstCrash), secondo a "
            + "\(crash.secondCrash) durante il recupero con strategia \(crash.strategy.rawValue)"))
    }
    return points
  }

  /// `S03, OP2: spostamento di IMG_0002.jpg in selezione/IMG_0002.jpg`.
  static func summary(of step: PlannedStep) -> String {
    let destination = step.destination ?? "?"
    let action =
      switch step.kind {
      case .rename: "rinomina di \(step.source) in \(destination)"
      case .move: "spostamento di \(step.source) in \(destination)"
      case .copy: "copia di \(step.source) in \(destination)"
      case .trash: "\(step.source) nel Cestino del volume"
      }
    return "\(step.id), \(step.opId): \(action)"
  }

  // MARK: - Elenco senza volume

  /// Piano di riferimento della fixture, costruito senza montare il volume: è il piano che
  /// `BatchPlan.make` costruisce dopo il ripristino della cartella di prova, che copia
  /// `fixtures/folder` in `lotto/`.
  ///
  /// Espande le operazioni come `BatchPlan.make` (due passi per operazione, prima l'immagine e poi
  /// il sidecar, numerati da `S01`), leggendo digest e dimensione da `folder` invece che dal
  /// volume. `volumeUUID` è vuoto e `planId` è l'UUID nullo: serve solo a elencare i punti, e non
  /// va mai eseguito. Un test verifica che coincida con il piano costruito sul volume.
  public static func referencePlan(
    definition: BatchDefinition, folder: URL = CrashPaths.fixtureFolder
  ) throws -> BatchPlan {
    var steps: [PlannedStep] = []
    for operation in definition.operations {
      for fileExtension in Fixtures.pairExtensions {
        let source = "\(operation.stem).\(fileExtension)"
        let url = folder.appending(path: source, directoryHint: .notDirectory)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.fileSystemPath)
        steps.append(
          PlannedStep(
            id: String(format: "S%02d", steps.count + 1),
            opId: operation.id,
            kind: operation.kind,
            source: source,
            destination: operation.to.map { "\($0).\(fileExtension)" },
            sha256: try Fixtures.sha256Hex(ofFileAt: url),
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0))
      }
    }

    var directoriesToCreate: [String] = []
    for destination in steps.compactMap(\.destination) {
      var ancestor = ""
      for component in destination.split(separator: "/").dropLast() {
        ancestor = ancestor.isEmpty ? String(component) : "\(ancestor)/\(component)"
        let existing = folder.appending(path: ancestor, directoryHint: .isDirectory)
        guard !directoriesToCreate.contains(ancestor),
          !FileManager.default.fileExists(atPath: existing.fileSystemPath)
        else { continue }
        directoriesToCreate.append(ancestor)
      }
    }

    return BatchPlan(
      planId: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
      batchId: definition.batchId,
      volumeUUID: "",
      steps: steps,
      directoriesToCreate: directoriesToCreate)
  }

  /// I punti di interruzione della fixture versionata, senza volume: quelli di `list-points`.
  public static func fixturePoints() throws -> [CrashPoint] {
    let definition = try BatchDefinition.load(
      from: CrashPaths.fixtures.appending(
        path: Fixtures.batchFileName, directoryHint: .notDirectory))
    return enumerate(try referencePlan(definition: definition))
  }
}

/// Arresto simulato dall'iniettore di prova al posto di `SIGKILL`.
public struct SimulatedCrash: Error, Equatable, Sendable, CustomStringConvertible {
  /// Il punto di interruzione raggiunto.
  public let pointId: String

  public init(_ pointId: String) {
    self.pointId = pointId
  }

  public var description: String { "arresto simulato al punto \(pointId)" }
}

/// Iniettore dell'arresto: la macchina chiama `hit(_:)` in ogni punto dell'elenco, e l'iniettore
/// interrompe il processo solo nel punto bersaglio.
public struct CrashInjector {
  public enum Mode: Sendable {
    /// Stampa `ARRESTO <id>: <descrizione>` e si uccide con `kill(getpid(), SIGKILL)`.
    case kill
    /// Lancia `SimulatedCrash`: per i test in-process, che non devono uccidere il processo di test.
    case throwForTest
  }

  /// Il punto in cui arrestarsi; `nil` per un'esecuzione senza arresto.
  public let target: String?
  public let mode: Mode
  /// Chiamato a ogni punto raggiunto, prima dell'eventuale arresto. Solo per i test.
  public let observer: ((String) -> Void)?
  private let descriptions: [String: String]

  /// - Parameter points: l'elenco da cui prendere la descrizione della riga `ARRESTO`.
  public init(
    target: String?, mode: Mode, observer: ((String) -> Void)? = nil, points: [CrashPoint] = []
  ) {
    self.target = target
    self.mode = mode
    self.observer = observer
    self.descriptions = Dictionary(points.map { ($0.id, $0.description) }) { first, _ in first }
  }

  /// Punto `id` raggiunto: chiama l'osservatore e, se `id` è il bersaglio, arresta il processo.
  ///
  /// In modalità `.kill` non ritorna: dopo `kill(getpid(), SIGKILL)` il segnale è già consegnato.
  /// Se per assurdo non lo fosse, `fatalError` termina con un segnale diverso da 9, che il banco
  /// riconosce come punto non raggiunto.
  public func hit(_ id: String) throws {
    observer?(id)
    guard id == target else { return }
    switch mode {
    case .kill:
      print("ARRESTO \(id): \(descriptions[id] ?? "punto di interruzione")")
      fflush(stdout)
      kill(getpid(), SIGKILL)
      fatalError("SIGKILL non consegnato al punto \(id)")
    case .throwForTest:
      throw SimulatedCrash(id)
    }
  }

  /// Vero se `id` è un punto di record troncato (`X00-plan-torn`, `S05-torn`) ed è il bersaglio:
  /// la macchina allora scrive metà del record e chiama `hit(id)`.
  public func hitTorn(_ id: String) -> Bool {
    id == target && CrashPoints.tornPoints.contains(id)
  }
}
