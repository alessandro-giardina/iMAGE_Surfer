// Classificatore degli esiti: una funzione pura dagli stati dei passi all'esito del lotto.
//
// I cinque esiti dichiarati da ADR-007 (PRD 1.3) sono `completato`, `compensato`,
// `parzialmente-recuperato`, `bloccato` e `abbandonato`. Quando nessuno dei cinque descrive lo
// stato, l'esito è `NON_SUPPORTABILE` con il motivo e la traccia (AC-7): il cancello misura proprio
// quante celle finiscono lì, e un esito di ripiego le nasconderebbe.

import Foundation

/// Stato di un passo, come lo vede il classificatore degli esiti.
public enum StepState: Equatable, Sendable, CustomStringConvertible {
  /// Il passo è nello stato di arrivo della direzione in avanti.
  case fatto
  /// Il passo è nello stato di origine.
  case nonFatto
  /// Il passo è stato saltato per un errore locale della classe data.
  case saltato(ErrorClass)
  /// Il passo è sospeso per un errore sistemico della classe data.
  case sospeso(ErrorClass)
  /// Lo stato del passo non si riconosce dal disco, o il suo errore non si classifica; la traccia
  /// nomina le posizioni ispezionate.
  case nonRiconoscibile(trace: String)

  /// Nome dello stato senza argomento: `fatto`, `non-fatto`, `saltato`, `sospeso`,
  /// `non-riconoscibile`.
  public var name: String {
    switch self {
    case .fatto: "fatto"
    case .nonFatto: "non-fatto"
    case .saltato: "saltato"
    case .sospeso: "sospeso"
    case .nonRiconoscibile: "non-riconoscibile"
    }
  }

  /// `fatto`, `non-fatto`, `saltato(L-locked)`, `sospeso(G-volume-missing)`,
  /// `non-riconoscibile(<traccia>)`.
  public var description: String {
    switch self {
    case .fatto, .nonFatto: name
    case .saltato(let errorClass), .sospeso(let errorClass): "\(name)(\(errorClass.rawValue))"
    case .nonRiconoscibile(let trace): "\(name)(\(trace))"
    }
  }
}

/// Decisione dell'utente nota al momento della classificazione.
public enum OutcomeDecision: String, Codable, Sendable, CaseIterable {
  case none
  case retry
  case abandon
}

/// Ingresso del classificatore degli esiti.
public struct OutcomeInput: Equatable, Sendable {
  /// Vero se il log contiene un record `plan` completo.
  public var hasPlan: Bool
  /// Stato di ogni passo del piano, per `stepId`.
  public var stepStates: [String: StepState]
  /// Direzione del lotto o del recupero.
  public var direction: StepDirection
  /// Classi degli errori sistemici non risolti.
  public var unresolvedSystemic: [ErrorClass]
  /// Classi degli errori locali per cui un passo è stato saltato.
  public var localSkips: [ErrorClass]
  /// Tracce dei passi il cui stato non si riconosce dal disco.
  public var unrecognized: [String]
  /// Tracce degli errori che il classificatore degli errori non ha classificato.
  public var unclassified: [String]
  public var decision: OutcomeDecision

  public init(
    hasPlan: Bool, stepStates: [String: StepState], direction: StepDirection,
    unresolvedSystemic: [ErrorClass] = [], localSkips: [ErrorClass] = [],
    unrecognized: [String] = [], unclassified: [String] = [], decision: OutcomeDecision = .none
  ) {
    self.hasPlan = hasPlan
    self.stepStates = stepStates
    self.direction = direction
    self.unresolvedSystemic = unresolvedSystemic
    self.localSkips = localSkips
    self.unrecognized = unrecognized
    self.unclassified = unclassified
    self.decision = decision
  }
}

/// Tipo di esito: i cinque di ADR-007, più `NON_SUPPORTABILE`.
public enum OutcomeKind: String, Codable, Sendable, CaseIterable {
  case completato
  case compensato
  case parzialmenteRecuperato = "parzialmente-recuperato"
  case bloccato
  case abbandonato
  case nonSupportabile = "NON_SUPPORTABILE"
}

/// Motivo di un esito `NON_SUPPORTABILE`.
public enum OutcomeReason: String, Codable, Sendable, CaseIterable {
  /// Almeno un passo non riconoscibile, o un errore non classificato.
  case statoNonRiconoscibile = "stato-non-riconoscibile"
  /// Lo stato è riconoscibile, ma nessuno dei cinque esiti lo descrive.
  case nessunEsitoApplicabile = "nessun-esito-applicabile"
}

/// Esito del lotto o del recupero.
public struct Outcome: Codable, Sendable, Equatable {
  public let kind: OutcomeKind
  /// Presente solo quando `kind` è `NON_SUPPORTABILE`.
  public let reason: OutcomeReason?
  public let trace: [String]

  public init(kind: OutcomeKind, reason: OutcomeReason? = nil, trace: [String] = []) {
    self.kind = kind
    self.reason = reason
    self.trace = trace
  }

  /// Record `outcome` del log di intenti.
  public var record: IntentLog.Record {
    .outcome(outcome: kind.rawValue, reason: reason?.rawValue, trace: trace)
  }

  /// `ESITO <kind>`, seguito da ` motivo=<reason>` per `NON_SUPPORTABILE`.
  public var line: String {
    "ESITO \(kind.rawValue)" + (reason.map { " motivo=\($0.rawValue)" } ?? "")
  }
}

/// Classificatore degli esiti, puro: nessun accesso al disco o al log.
public enum OutcomeClassifier {
  /// Traccia della regola 1.
  public static let noPlanTrace =
    "log senza piano completo: per costruzione del log di intenti nessuna azione è stata eseguita"

  /// Esito dagli stati dei passi. Le regole si applicano in ordine, e la prima che corrisponde
  /// vince:
  ///
  /// 1. nessun piano completo, o zero passi → `NON_SUPPORTABILE`, `nessun-esito-applicabile`;
  /// 2. `unrecognized` o `unclassified` non vuoti → `NON_SUPPORTABILE`, `stato-non-riconoscibile`,
  ///    con quelle tracce;
  /// 3. decisione `abandon` → `abbandonato`;
  /// 4. `unresolvedSystemic` non vuoto → `bloccato`;
  /// 5. `localSkips` non vuoto → `parzialmente-recuperato`;
  /// 6. direzione `forward` e ogni passo `fatto` → `completato`;
  /// 7. direzione `compensate` e ogni passo `non-fatto` → `compensato`;
  /// 8. ogni altro caso → `NON_SUPPORTABILE`, `nessun-esito-applicabile`, con lo stato dei passi
  ///    come traccia.
  ///
  /// **`bloccato` nasce solo dalla regola 4.** Nessuna regola riconduce uno stato non riconoscibile
  /// a `bloccato` (AC-7): la regola 2 precede la 4, così un passo non riconoscibile o un errore non
  /// classificato danno `NON_SUPPORTABILE` anche in presenza di un errore sistemico, e la regola 8
  /// non produce mai `bloccato`.
  public static func classify(_ input: OutcomeInput) -> Outcome {
    // 1
    if !input.hasPlan || input.stepStates.isEmpty {
      return Outcome(kind: .nonSupportabile, reason: .nessunEsitoApplicabile, trace: [noPlanTrace])
    }
    // 2
    if !input.unrecognized.isEmpty || !input.unclassified.isEmpty {
      return Outcome(
        kind: .nonSupportabile, reason: .statoNonRiconoscibile,
        trace: input.unrecognized + input.unclassified)
    }
    // 3
    if input.decision == .abandon {
      return Outcome(kind: .abbandonato, trace: ["decisione dell'utente: abandon"])
    }
    // 4
    if !input.unresolvedSystemic.isEmpty {
      return Outcome(
        kind: .bloccato,
        trace: input.unresolvedSystemic.map { "errore sistemico non risolto: \($0.rawValue)" })
    }
    // 5
    if !input.localSkips.isEmpty {
      return Outcome(
        kind: .parzialmenteRecuperato,
        trace: input.localSkips.map { "passo saltato per errore locale: \($0.rawValue)" })
    }
    let states = input.stepStates.values
    // 6
    if input.direction == .forward, states.allSatisfy({ $0 == .fatto }) {
      return Outcome(kind: .completato)
    }
    // 7
    if input.direction == .compensate, states.allSatisfy({ $0 == .nonFatto }) {
      return Outcome(kind: .compensato)
    }
    // 8
    return Outcome(
      kind: .nonSupportabile, reason: .nessunEsitoApplicabile,
      trace: input.stepStates.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" })
  }
}
