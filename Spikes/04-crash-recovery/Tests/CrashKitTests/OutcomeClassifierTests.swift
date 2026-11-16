import Foundation
import Testing

@testable import CrashKit

/// Gli ID dei passi della fixture, `S01`…`S10`.
private let stepIds = (1...10).map { String(format: "S%02d", $0) }

/// Stati dei passi costruiti a mano: ogni passo nello stato `base`, salvo quelli di `overrides`.
private func states(
  _ base: StepState, _ overrides: [String: StepState] = [:]
) -> [String: StepState] {
  var result = Dictionary(uniqueKeysWithValues: stepIds.map { ($0, base) })
  result.merge(overrides) { _, override in override }
  return result
}

/// Un ingresso costruito a mano e l'esito che il piano gli assegna.
struct OutcomeRuleCase: Sendable, CustomTestStringConvertible {
  let name: String
  let input: OutcomeInput
  let kind: OutcomeKind
  let reason: OutcomeReason?
  /// Traccia attesa; `nil` se il caso non la verifica.
  let trace: [String]?

  var testDescription: String { name }
}

private let unrecognizedTrace =
  "S03 forward; anomalia lotto/IMG_0002.jpg=dec2e434c1b1 lotto/selezione/IMG_0002.jpg=dec2e434c1b1"
private let unclassifiedTrace = "S07 forward; copyfile errno 5"

/// Una riga per ciascuna delle otto regole, nell'ordine del piano.
private let ruleCases: [OutcomeRuleCase] = [
  OutcomeRuleCase(
    name: "regola 1: nessun piano completo nel log",
    input: OutcomeInput(hasPlan: false, stepStates: [:], direction: .forward),
    kind: .nonSupportabile, reason: .nessunEsitoApplicabile,
    trace: [OutcomeClassifier.noPlanTrace]),
  OutcomeRuleCase(
    name: "regola 2: un passo non riconoscibile",
    input: OutcomeInput(
      hasPlan: true,
      stepStates: states(.fatto, ["S03": .nonRiconoscibile(trace: unrecognizedTrace)]),
      direction: .forward, unrecognized: [unrecognizedTrace]),
    kind: .nonSupportabile, reason: .statoNonRiconoscibile, trace: [unrecognizedTrace]),
  OutcomeRuleCase(
    name: "regola 2: un errore non classificato",
    input: OutcomeInput(
      hasPlan: true,
      stepStates: states(.nonFatto, ["S07": .nonRiconoscibile(trace: unclassifiedTrace)]),
      direction: .forward, unclassified: [unclassifiedTrace]),
    kind: .nonSupportabile, reason: .statoNonRiconoscibile, trace: [unclassifiedTrace]),
  OutcomeRuleCase(
    name: "regola 3: decisione abandon",
    input: OutcomeInput(
      hasPlan: true, stepStates: states(.nonFatto, ["S01": .fatto]), direction: .forward,
      decision: .abandon),
    kind: .abbandonato, reason: nil, trace: ["decisione dell'utente: abandon"]),
  OutcomeRuleCase(
    name: "regola 4: errore sistemico non risolto",
    input: OutcomeInput(
      hasPlan: true, stepStates: states(.nonFatto, ["S07": .sospeso(.folderReadonly)]),
      direction: .forward, unresolvedSystemic: [.folderReadonly]),
    kind: .bloccato, reason: nil, trace: ["errore sistemico non risolto: G-folder-readonly"]),
  OutcomeRuleCase(
    name: "regola 5: passo saltato per errore locale",
    input: OutcomeInput(
      hasPlan: true, stepStates: states(.fatto, ["S09": .saltato(.locked)]), direction: .forward,
      localSkips: [.locked]),
    kind: .parzialmenteRecuperato, reason: nil,
    trace: ["passo saltato per errore locale: L-locked"]),
  OutcomeRuleCase(
    name: "regola 6: in avanti, ogni passo fatto",
    input: OutcomeInput(hasPlan: true, stepStates: states(.fatto), direction: .forward),
    kind: .completato, reason: nil, trace: []),
  OutcomeRuleCase(
    name: "regola 7: in compensazione, ogni passo all'origine",
    input: OutcomeInput(hasPlan: true, stepStates: states(.nonFatto), direction: .compensate),
    kind: .compensato, reason: nil, trace: []),
  OutcomeRuleCase(
    name: "regola 8: in avanti con un passo non fatto e nessun errore",
    input: OutcomeInput(
      hasPlan: true, stepStates: ["S02": .nonFatto, "S01": .fatto], direction: .forward),
    kind: .nonSupportabile, reason: .nessunEsitoApplicabile,
    trace: ["S01 fatto", "S02 non-fatto"]),
]

/// I quattro casi di precedenza fra regole.
private let precedenceCases: [OutcomeRuleCase] = [
  OutcomeRuleCase(
    name: "non riconoscibile ed errore sistemico: regola 2, non bloccato",
    input: OutcomeInput(
      hasPlan: true,
      stepStates: states(
        .nonFatto,
        ["S03": .nonRiconoscibile(trace: unrecognizedTrace), "S07": .sospeso(.volumeMissing)]),
      direction: .forward, unresolvedSystemic: [.volumeMissing],
      unrecognized: [unrecognizedTrace]),
    kind: .nonSupportabile, reason: .statoNonRiconoscibile, trace: [unrecognizedTrace]),
  OutcomeRuleCase(
    name: "abandon con un passo non riconoscibile: regola 2, non abbandonato",
    input: OutcomeInput(
      hasPlan: true,
      stepStates: states(.fatto, ["S09": .nonRiconoscibile(trace: unrecognizedTrace)]),
      direction: .forward, unrecognized: [unrecognizedTrace], decision: .abandon),
    kind: .nonSupportabile, reason: .statoNonRiconoscibile, trace: [unrecognizedTrace]),
  OutcomeRuleCase(
    name: "piano presente e zero passi: regola 1",
    input: OutcomeInput(
      hasPlan: true, stepStates: [:], direction: .forward, unresolvedSystemic: [.spaceExhausted]),
    kind: .nonSupportabile, reason: .nessunEsitoApplicabile,
    trace: [OutcomeClassifier.noPlanTrace]),
  OutcomeRuleCase(
    name: "in compensazione con un passo ancora fatto e nessun errore: regola 8",
    input: OutcomeInput(
      hasPlan: true, stepStates: states(.nonFatto, ["S04": .fatto]), direction: .compensate),
    kind: .nonSupportabile, reason: .nessunEsitoApplicabile,
    trace: stepIds.map { $0 == "S04" ? "S04 fatto" : "\($0) non-fatto" }),
]

/// Classificatore degli esiti, puro: ingressi costruiti a mano, nessun disco.
@Suite(
  "Classificatore degli esiti: le otto regole, la precedenza e mai bloccato da uno stato ignoto")
struct OutcomeClassifierTests {
  @Test("ogni regola dà l'esito dichiarato", arguments: ruleCases)
  func eachRuleGivesItsOutcome(_ rule: OutcomeRuleCase) {
    let outcome = OutcomeClassifier.classify(rule.input)
    #expect(outcome.kind == rule.kind, "\(rule.name): \(outcome)")
    #expect(outcome.reason == rule.reason, "\(rule.name): \(outcome)")
    if let trace = rule.trace {
      #expect(outcome.trace == trace, "\(rule.name)")
    }
  }

  @Test("la precedenza fra regole segue l'ordine del piano", arguments: precedenceCases)
  func precedenceFollowsRuleOrder(_ rule: OutcomeRuleCase) {
    let outcome = OutcomeClassifier.classify(rule.input)
    #expect(outcome.kind == rule.kind, "\(rule.name): \(outcome)")
    #expect(outcome.reason == rule.reason, "\(rule.name): \(outcome)")
    #expect(outcome.kind != .bloccato || rule.kind == .bloccato, "\(rule.name): \(outcome)")
    if let trace = rule.trace {
      #expect(outcome.trace == trace, "\(rule.name)")
    }
  }

  @Test("ciascuno dei cinque esiti e dei due motivi è raggiungibile dalle regole")
  func everyOutcomeAndReasonIsReachable() {
    let outcomes = (ruleCases + precedenceCases).map { OutcomeClassifier.classify($0.input) }
    #expect(Set(outcomes.map(\.kind)) == Set(OutcomeKind.allCases))
    #expect(Set(outcomes.compactMap(\.reason)) == Set(OutcomeReason.allCases))
    // `motivo=` solo per NON_SUPPORTABILE, e sempre per NON_SUPPORTABILE.
    for outcome in outcomes {
      #expect((outcome.reason != nil) == (outcome.kind == .nonSupportabile), "\(outcome)")
    }
  }

  @Test("la riga ESITO e il record del log portano tipo, motivo e traccia")
  func lineAndRecordCarryKindReasonAndTrace() {
    let notSupportable = Outcome(
      kind: .nonSupportabile, reason: .statoNonRiconoscibile, trace: [unrecognizedTrace])
    #expect(notSupportable.line == "ESITO NON_SUPPORTABILE motivo=stato-non-riconoscibile")
    #expect(
      notSupportable.record
        == .outcome(
          outcome: "NON_SUPPORTABILE", reason: "stato-non-riconoscibile",
          trace: [unrecognizedTrace]))
    #expect(Outcome(kind: .parzialmenteRecuperato).line == "ESITO parzialmente-recuperato")
    #expect(Outcome(kind: .bloccato).record == .outcome(outcome: "bloccato"))
  }

  /// Proprietà di AC-7 su ogni combinazione degli ingressi che decidono le regole da 1 a 5, con
  /// passi tutti fatti o tutti all'origine nelle due direzioni (regole da 6 a 8): otto scelte
  /// binarie per le tre decisioni.
  @Test("bloccato implica sempre nessun passo non riconoscibile e nessun errore non classificato")
  func blockedNeverHidesAnUnrecognizedState() {
    var combinations = 0
    var blocked = 0
    var unknownStates = 0
    for bits in 0..<(1 << 8) {
      func flag(_ index: Int) -> Bool { bits & (1 << index) != 0 }
      let hasPlan = flag(0)
      let hasSteps = flag(1)
      let direction: StepDirection = flag(2) ? .compensate : .forward
      let base: StepState = flag(3) ? .fatto : .nonFatto
      let systemic: [ErrorClass] = flag(4) ? [.volumeMissing] : []
      let local: [ErrorClass] = flag(5) ? [.locked] : []
      let unrecognized = flag(6) ? [unrecognizedTrace] : []
      let unclassified = flag(7) ? [unclassifiedTrace] : []
      var overrides: [String: StepState] = [:]
      if !unrecognized.isEmpty { overrides["S03"] = .nonRiconoscibile(trace: unrecognizedTrace) }
      if !unclassified.isEmpty { overrides["S07"] = .nonRiconoscibile(trace: unclassifiedTrace) }
      if !systemic.isEmpty { overrides["S08"] = .sospeso(.volumeMissing) }
      if !local.isEmpty { overrides["S09"] = .saltato(.locked) }
      let unknown = !unrecognized.isEmpty || !unclassified.isEmpty

      for decision in OutcomeDecision.allCases {
        let input = OutcomeInput(
          hasPlan: hasPlan, stepStates: hasSteps ? states(base, overrides) : [:],
          direction: direction, unresolvedSystemic: systemic, localSkips: local,
          unrecognized: unrecognized, unclassified: unclassified, decision: decision)
        let outcome = OutcomeClassifier.classify(input)
        combinations += 1
        if unknown { unknownStates += 1 }

        if outcome.kind == .bloccato {
          blocked += 1
          #expect(input.unrecognized.isEmpty, "\(input) → \(outcome)")
          #expect(input.unclassified.isEmpty, "\(input) → \(outcome)")
        }
        // `bloccato` nasce solo dalla regola 4: esattamente quando le regole da 1 a 3 non
        // scattano e c'è un errore sistemico non risolto.
        let rule4 = hasPlan && hasSteps && !unknown && decision != .abandon && !systemic.isEmpty
        #expect((outcome.kind == .bloccato) == rule4, "\(input) → \(outcome)")
        // Con un piano e dei passi, uno stato ignoto è sempre la regola 2.
        if hasPlan, hasSteps, unknown {
          #expect(outcome.kind == .nonSupportabile, "\(input) → \(outcome)")
          #expect(outcome.reason == .statoNonRiconoscibile, "\(input) → \(outcome)")
        }
      }
    }
    // La proprietà non è vuota: le combinazioni coprono sia bloccato sia gli stati ignoti.
    #expect(combinations == (1 << 8) * OutcomeDecision.allCases.count)
    #expect(blocked > 0)
    #expect(unknownStates > 0)
  }
}
