import Darwin
import Foundation
import Testing

@testable import CrashKit

/// Voce del `.DS_Store` che il Cestino di sistema crea in `.Trashes/<uid>` alla prima voce: è un
/// effetto dichiarato del Cestino, non del lotto, e viene stampato quando compare.
private let trashDSStore = "\(Snapshot.trashKey)/.DS_Store"

/// File dell'istantanea, nel lotto e nel Cestino: percorso → digest.
private func files(of snapshot: Snapshot) -> [String: String] {
  snapshot.entries.reduce(into: [:]) { files, item in
    if item.value.kind == .file, let digest = item.value.sha256 { files[item.key] = digest }
  }
}

/// Directory dell'istantanea.
private func directories(of snapshot: Snapshot) -> Set<String> {
  Set(snapshot.entries.filter { $0.value.kind == .directory }.keys)
}

/// L'elenco completo degli scostamenti, una riga ciascuno, per i messaggi di errore.
private func render(_ deviations: [Deviation]) -> String {
  deviations.isEmpty ? "nessuno" : deviations.map(\.description).joined(separator: "\n")
}

/// Le righe `COPPIA` stampate.
private func pairLines(_ printed: [String]) -> [String] {
  printed.filter { $0.hasPrefix("COPPIA ") }
}

/// Scostamenti di `post` dallo stato atteso del lotto completato, calcolato applicando il piano a
/// `pre`; vuoto se coincidono.
///
/// - rinomina e spostamento: il file lascia l'origine e arriva nella destinazione con lo stesso
///   digest e lo stesso inode (è stato spostato, non copiato);
/// - copia: la destinazione si aggiunge, l'origine resta;
/// - `trash`: il file lascia l'origine e arriva in `@cestino/<nome>` con lo stesso inode (il
///   Cestino di `pre` non ha voci con quel nome, quindi nessun suffisso orario);
/// - le cartelle del piano si aggiungono; l'unico file in più ammesso è `@cestino/.DS_Store`.
private func completedMismatches(pre: Snapshot, post: Snapshot, plan: BatchPlan) -> [String] {
  var expected = files(of: pre)
  var expectedInodes: [String: UInt64] = [:]
  var expectedDirectories = directories(of: pre)
  expectedDirectories.formUnion(plan.directoriesToCreate.map(SnapshotOracle.batchKey))
  var mismatches: [String] = []

  for step in plan.steps {
    let source = SnapshotOracle.batchKey(step.source)
    let arrival: String
    if step.kind == .trash {
      arrival = "\(Snapshot.trashKey)/\(URL(filePath: step.source).lastPathComponent)"
      expectedDirectories.insert(Snapshot.trashKey)
      if pre.entries[arrival] != nil {
        mismatches.append("\(arrival): già presente in pre, il nome della voce non è prevedibile")
      }
    } else if let destination = step.destination {
      arrival = SnapshotOracle.batchKey(destination)
    } else {
      mismatches.append("\(step.id): passo senza destinazione")
      continue
    }
    if step.kind != .copy {
      expected[source] = nil
      expectedInodes[arrival] = pre.entries[source]?.inode
    }
    expected[arrival] = step.sha256
  }

  let actual = files(of: post)
  for path in Set(expected.keys).union(actual.keys).sorted() {
    let wanted = expected[path]
    let found = actual[path]
    guard wanted != found, !(wanted == nil && path == trashDSStore) else { continue }
    mismatches.append("\(path): atteso \(wanted ?? "assente"), trovato \(found ?? "assente")")
  }
  for (path, inode) in expectedInodes.sorted(by: { $0.key < $1.key })
  where post.entries[path]?.inode != inode {
    let found = post.entries[path].map { String($0.inode) } ?? "assente"
    mismatches.append("\(path): inode \(found), atteso \(inode) dell'origine")
  }
  let actualDirectories = directories(of: post)
  for path in expectedDirectories.symmetricDifference(actualDirectories).sorted() {
    mismatches.append(
      "\(path): directory \(expectedDirectories.contains(path) ? "attesa e assente" : "inattesa")")
  }
  if actual[trashDSStore] != nil, expected[trashDSStore] == nil {
    print("scostamento dichiarato: \(trashDSStore) creato dal Cestino di sistema")
  }
  return mismatches
}

/// Recupero in-process con l'iniettore di prova senza bersaglio. Restituisce il resoconto e le
/// righe stampate, che devono coincidere con le righe del resoconto.
private func recover(
  _ batch: CrashedBatch, _ strategy: RecoveryStrategy
) throws -> (report: RecoveryReport, printed: [String]) {
  var printed: [String] = []
  let report = try Recovery.run(
    strategy: strategy, log: batch.log, volume: batch.volume,
    injector: CrashInjector(target: nil, mode: .throwForTest), output: { printed.append($0) })
  #expect(printed == report.lines, "righe stampate diverse dal resoconto")
  return (report, printed)
}

/// Decisione dell'utente in-process su un lotto bloccato.
private func decide(
  _ batch: CrashedBatch, _ decision: UserDecision
) throws -> (report: RecoveryReport, printed: [String]) {
  var printed: [String] = []
  let report = try Recovery.decide(
    decision, log: batch.log, volume: batch.volume,
    injector: CrashInjector(target: nil, mode: .throwForTest), output: { printed.append($0) })
  #expect(printed == report.lines, "righe stampate diverse dal resoconto")
  return (report, printed)
}

/// I cinque esiti e i due motivi di `NON_SUPPORTABILE`, ciascuno raggiunto da uno scenario
/// in-process: arresto con l'iniettore di prova, eventuale perturbazione, recupero.
///
/// L'istantanea del banco è l'oracolo; la riga `ESITO` e le righe `COPPIA` stampate dal recupero
/// sono le affermazioni da verificare. Ogni asserzione sull'istantanea stampa, se fallisce,
/// l'elenco completo degli scostamenti.
@Suite("Esiti del recupero asseriti sull'istantanea del disco", .serialized)
struct RecoveryScenarioTests {
  @Test("completato: arresto a S04-b e ripresa; il disco è il lotto completato atteso da pre")
  func resumeAfterS04bIsCompleted() throws {
    let test = try TestVolume(name: "scenario-completato")
    defer { test.close() }
    let batch = try CrashedBatch(volume: test.volume, crashAt: "S04-b")

    let (report, printed) = try recover(batch, .resume)
    let post = try Snapshot.capture(volume: batch.volume)

    // Oracolo: il piano applicato a `pre`.
    let mismatches = completedMismatches(pre: batch.pre, post: post, plan: batch.plan)
    #expect(
      mismatches.isEmpty,
      "scostamenti dal lotto completato atteso:\n\(mismatches.joined(separator: "\n"))")
    // OP4 è una copia: l'originale resta in origine, la copia è in consegna/.
    for id in ["S07", "S08"] {
      let step = try batch.step(id)
      let destination = try #require(step.destination)
      #expect(post.entries[SnapshotOracle.batchKey(step.source)]?.sha256 == step.sha256, "\(id)")
      #expect(post.entries[SnapshotOracle.batchKey(destination)]?.sha256 == step.sha256, "\(id)")
      #expect(destination.hasPrefix("consegna/"), "\(id)")
    }

    // Affermazioni del recupero.
    #expect(report.outcome == Outcome(kind: .completato))
    #expect(printed.contains("ESITO completato"))
    #expect(printed.contains("RECUPERO strategia=resume direzione=forward"))
    #expect(printed.contains("DIVERGENZA S04 log=non-fatto disco=fatto"))
    #expect(report.steps.allSatisfy { $0.final == .fatto }, "\(report.steps.map(\.line))")
    #expect(pairLines(printed) == SnapshotOracle.pairLines(post, plan: batch.plan))
    #expect(printed.contains("SEPARAZIONI-RESIDUE nessuna"))
  }

  @Test("compensato: arresto a S04-b e compensazione; il disco coincide con pre campo per campo")
  func compensationAfterS04bMatchesPre() throws {
    let test = try TestVolume(name: "scenario-compensato")
    defer { test.close() }
    let batch = try CrashedBatch(volume: test.volume, crashAt: "S04-b")
    // La compensazione ha qualcosa da annullare: all'arresto il disco non è quello di `pre`.
    let atCrash = try Snapshot.capture(volume: batch.volume)
    try #require(atCrash.entries[SnapshotOracle.batchKey("selezione/IMG_0002.xmp")] != nil)
    try #require(batch.pre.entries[SnapshotOracle.batchKey("selezione")] == nil)

    let (report, printed) = try recover(batch, .compensate)
    let post = try Snapshot.capture(volume: batch.volume)

    // Oracolo: confronto campo per campo con `pre`; ammessi solo gli `mtime` di directory.
    let deviations = Snapshot.diff(batch.pre, post)
    let allowed = deviations.filter(\.isDirectoryMtime)
    print(
      "scostamenti ammessi dopo la compensazione (mtime di directory): "
        + (allowed.isEmpty ? "nessuno" : allowed.map(\.description).joined(separator: "; ")))
    let forbidden = deviations.filter { !$0.isDirectoryMtime }
    #expect(
      forbidden.isEmpty, "scostamenti oltre gli mtime di directory:\n\(render(deviations))")
    // `selezione/` era stata creata dal lotto ed è vuota: la compensazione la rimuove.
    #expect(
      try batch.log.read().records.contains(.prepare(created: batch.plan.directoriesToCreate)))
    #expect(post.entries[SnapshotOracle.batchKey("selezione")] == nil)
    #expect(post.entries[SnapshotOracle.batchKey("consegna")] == nil)

    // Affermazioni del recupero.
    #expect(report.outcome == Outcome(kind: .compensato))
    #expect(printed.contains("ESITO compensato"))
    #expect(printed.contains("RECUPERO strategia=compensate direzione=compensate"))
    #expect(report.steps.allSatisfy { $0.final == .nonFatto }, "\(report.steps.map(\.line))")
    #expect(pairLines(printed) == SnapshotOracle.pairLines(post, plan: batch.plan))
    #expect(pairLines(printed).allSatisfy { $0.hasSuffix("immagine=orig sidecar=orig") })
  }

  @Test("parzialmente-recuperato: S06-b, L-locked su S09, ripresa; OP5 resta separata")
  func lockedImageIsSkippedAndOP5StaysSeparated() throws {
    let test = try TestVolume(name: "scenario-parziale")
    defer { test.close() }
    let batch = try CrashedBatch(volume: test.volume, crashAt: "S06-b")
    let perturbation = try Perturbations.apply(
      .locked, strategy: .resume, plan: batch.plan, log: batch.log, volume: batch.volume)
    try #require(perturbation.target == "S09", "\(perturbation.line)")

    let (report, printed) = try recover(batch, .resume)
    let post = try Snapshot.capture(volume: batch.volume)

    // Oracolo: S07, S08 e S10 fatti, S09 ancora in origine e bloccato da UF_IMMUTABLE.
    for id in ["S07", "S08"] {
      let step = try batch.step(id)
      let destination = try #require(step.destination)
      #expect(post.entries[SnapshotOracle.batchKey(destination)]?.sha256 == step.sha256, "\(id)")
    }
    let s09 = try batch.step("S09")
    let s10 = try batch.step("S10")
    let image = post.entries[SnapshotOracle.batchKey(s09.source)]
    #expect(image?.sha256 == s09.sha256)
    #expect((image?.flags ?? 0) & UInt32(UF_IMMUTABLE) != 0)
    #expect(SnapshotOracle.trashKeys(withDigest: s09.sha256, in: post).isEmpty)
    #expect(post.entries[SnapshotOracle.batchKey(s10.source)] == nil)
    #expect(SnapshotOracle.trashKeys(withDigest: s10.sha256, in: post).count == 1)
    let oracle = SnapshotOracle.pairLines(post, plan: batch.plan)
    #expect(oracle.contains("COPPIA OP5 immagine=orig sidecar=cest SEPARATA"), "\(oracle)")

    // Affermazioni del recupero.
    #expect(report.outcome.kind == .parzialmenteRecuperato)
    #expect(printed.contains("ESITO parzialmente-recuperato"))
    #expect(printed.contains("TRACCIA passo saltato per errore locale: L-locked"))
    let finals = Dictionary(uniqueKeysWithValues: report.steps.map { ($0.stepId, $0.final) })
    #expect(finals["S07"] == .fatto)
    #expect(finals["S08"] == .fatto)
    #expect(finals["S09"] == .saltato(.locked))
    #expect(finals["S10"] == .fatto)
    #expect(printed.contains("PASSO S09 non-fatto -> saltato classe=L-locked ambito=locale"))
    #expect(pairLines(printed) == oracle)
    #expect(printed.contains("SEPARAZIONI-RESIDUE OP5"))

    #expect(try Perturbations.remove(volume: batch.volume) == perturbation)
  }

  @Test("bloccato: S06-b, G-folder-readonly, ripresa; nessun file si muove, poi retry completa")
  func readOnlyFolderBlocksThenRetryCompletes() throws {
    let test = try TestVolume(name: "scenario-bloccato")
    defer { test.close() }
    let batch = try CrashedBatch(volume: test.volume, crashAt: "S06-b")
    let perturbation = try Perturbations.apply(
      .folderReadonly, strategy: .resume, plan: batch.plan, log: batch.log, volume: batch.volume)
    try #require(perturbation.isApplied, "\(perturbation.line)")
    let afterPerturbation = try Snapshot.capture(volume: batch.volume)

    let (blocked, printed) = try recover(batch, .resume)
    let post = try Snapshot.capture(volume: batch.volume)

    // Oracolo: dopo la sospensione il disco è quello lasciato dalla perturbazione.
    let deviations = Snapshot.diff(afterPerturbation, post)
    #expect(deviations.isEmpty, "scostamenti dopo la sospensione:\n\(render(deviations))")

    // Affermazioni del recupero.
    #expect(blocked.outcome.kind == .bloccato)
    #expect(printed.contains("ESITO bloccato"))
    #expect(printed.contains("TRACCIA errore sistemico non risolto: G-folder-readonly"))
    #expect(blocked.steps.first { $0.stepId == "S07" }?.final == .sospeso(.folderReadonly))
    #expect(pairLines(printed) == SnapshotOracle.pairLines(post, plan: batch.plan))

    // Rimossa la causa, `decide retry` completa il lotto.
    #expect(try Perturbations.remove(volume: batch.volume) == perturbation)
    let (retried, retryPrinted) = try decide(batch, .retry)
    let final = try Snapshot.capture(volume: batch.volume)
    let mismatches = completedMismatches(pre: batch.pre, post: final, plan: batch.plan)
    #expect(
      mismatches.isEmpty,
      "scostamenti dal lotto completato atteso:\n\(mismatches.joined(separator: "\n"))")
    #expect(retried.outcome == Outcome(kind: .completato))
    #expect(retryPrinted.first == "DECISIONE retry")
    #expect(retryPrinted.contains("ESITO completato"))
    #expect(pairLines(retryPrinted) == SnapshotOracle.pairLines(final, plan: batch.plan))
  }

  @Test("abbandonato: S06-b, G-volume-missing, ripresa bloccata, poi decide abandon")
  func ejectedVolumeBlocksThenAbandon() throws {
    let test = try TestVolume(name: "scenario-abbandonato")
    defer { test.close() }
    let batch = try CrashedBatch(volume: test.volume, crashAt: "S06-b")
    let atCrash = try Snapshot.capture(volume: batch.volume)
    let perturbation = try Perturbations.apply(
      .volumeMissing, strategy: .resume, plan: batch.plan, log: batch.log, volume: batch.volume)
    try #require(!batch.volume.isMounted)

    let (blocked, printed) = try recover(batch, .resume)
    #expect(blocked.outcome.kind == .bloccato)
    #expect(printed.contains("ESITO bloccato"))
    #expect(
      blocked.steps.allSatisfy { $0.final == .sospeso(.volumeMissing) },
      "\(blocked.steps.map(\.line))")
    // Con il volume espulso le posizioni non sono osservabili: `amb` non afferma una posizione.
    #expect(pairLines(printed).allSatisfy { $0.contains("immagine=amb sidecar=amb") })

    #expect(try Perturbations.remove(volume: batch.volume) == perturbation)
    try #require(batch.volume.isMounted)
    let (abandoned, abandonPrinted) = try decide(batch, .abandon)
    let post = try Snapshot.capture(volume: batch.volume)

    // Oracolo: dall'arresto in poi nessun file si è mosso.
    let deviations = Snapshot.diff(atCrash, post)
    #expect(deviations.isEmpty, "scostamenti dall'arresto:\n\(render(deviations))")

    // Affermazioni della decisione: le righe COPPIA coincidono con le posizioni dell'istantanea.
    #expect(
      abandoned.outcome == Outcome(kind: .abbandonato, trace: ["decisione dell'utente: abandon"]))
    #expect(abandonPrinted.first == "DECISIONE abandon")
    #expect(!abandonPrinted.contains { $0.hasPrefix("RECUPERO ") })
    #expect(abandonPrinted.contains("ESITO abbandonato"))
    let oracle = SnapshotOracle.pairLines(post, plan: batch.plan)
    #expect(oracle.contains("COPPIA OP3 immagine=dest sidecar=dest"), "\(oracle)")
    #expect(oracle.contains("COPPIA OP4 immagine=orig sidecar=orig"), "\(oracle)")
    #expect(pairLines(abandonPrinted) == oracle)
  }

  @Test("NON_SUPPORTABILE stato-non-riconoscibile: S03-c, immagine copiata in origine, ripresa")
  func fileInTwoPositionsIsNotSupportable() throws {
    let test = try TestVolume(name: "scenario-non-riconoscibile")
    defer { test.close() }
    let batch = try CrashedBatch(volume: test.volume, crashAt: "S03-c")
    let s03 = try batch.step("S03")
    try batch.copy("lotto/selezione/IMG_0002.jpg", to: "lotto/IMG_0002.jpg")

    let (report, printed) = try recover(batch, .resume)
    let post = try Snapshot.capture(volume: batch.volume)

    // Oracolo: il file del passo è ancora in due posizioni con il digest del piano.
    #expect(post.entries[SnapshotOracle.batchKey("IMG_0002.jpg")]?.sha256 == s03.sha256)
    #expect(post.entries[SnapshotOracle.batchKey("selezione/IMG_0002.jpg")]?.sha256 == s03.sha256)
    #expect(SnapshotOracle.position(of: s03, in: post) == "amb")

    // Affermazioni del recupero: mai bloccato, e la traccia nomina le due posizioni.
    #expect(report.outcome.kind == .nonSupportabile)
    #expect(report.outcome.kind != .bloccato)
    #expect(report.outcome.reason == .statoNonRiconoscibile)
    #expect(printed.contains("ESITO NON_SUPPORTABILE motivo=stato-non-riconoscibile"))
    let digest = String(s03.sha256.prefix(12))
    let traces = printed.filter { $0.hasPrefix("TRACCIA ") }
    #expect(
      traces.contains {
        $0.contains("lotto/IMG_0002.jpg=\(digest)")
          && $0.contains("lotto/selezione/IMG_0002.jpg=\(digest)")
      }, "\(traces)")
    #expect(pairLines(printed) == SnapshotOracle.pairLines(post, plan: batch.plan))
  }

  /// Lo stato è riconoscibile e coincide con quello di partenza, ma nessuno dei cinque esiti lo
  /// descrive. Il test fissa il comportamento dichiarato; l'interpretazione per ADR-007 spetta a
  /// TASK-10.
  @Test("NON_SUPPORTABILE nessun-esito-applicabile: X00-plan-torn e ripresa; il disco è pre")
  func tornPlanHasNoApplicableOutcome() throws {
    let test = try TestVolume(name: "scenario-piano-troncato")
    defer { test.close() }
    let batch = try CrashedBatch(volume: test.volume, crashAt: "X00-plan-torn")

    let (report, printed) = try recover(batch, .resume)
    let post = try Snapshot.capture(volume: batch.volume)

    // Oracolo: nessuna azione, il disco è quello di partenza.
    let deviations = Snapshot.diff(batch.pre, post)
    #expect(deviations.isEmpty, "scostamenti da pre:\n\(render(deviations))")

    // Affermazioni del recupero.
    #expect(
      report.outcome
        == Outcome(
          kind: .nonSupportabile, reason: .nessunEsitoApplicabile,
          trace: [OutcomeClassifier.noPlanTrace]))
    #expect(
      printed == [
        "RECUPERO strategia=resume direzione=nessuna",
        "RECORD-TRONCATO si",
        "SEPARAZIONI-ALL-AVVIO nessuna",
        "SEPARAZIONI-RESIDUE nessuna",
        "ESITO NON_SUPPORTABILE motivo=nessun-esito-applicabile",
        "TRACCIA \(OutcomeClassifier.noPlanTrace)",
      ])
  }
}
