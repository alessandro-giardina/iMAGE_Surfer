import AppKit
import BenchKit
import Foundation

let usage = """
  uso: bench <sottocomando> [opzioni]

  Sottocomandi, nell'ordine di PROCEDURE.md:
    first-screen        tempo alla prima schermata su 3.000 immagini (NFR-P1)
    selection-latency   latenza dello spostamento della selezione sotto carico (NFR-P3)
    retention-band      spazzolamento delle soglie della banda di ritenzione (NFR-P6, AC-5)
    scroll-memory       picco di memoria su 50.000 file e sessione di lunga durata (NFR-P9)
    item-cost           costo in memoria per elemento e limite per singolo elemento (NFR-P10)

  Opzioni comuni:
    --data <path>                     dataset (predefinito: Spikes/01-scale-memory/.data)
    --profile full|smoke              profilo del dataset (predefinito: full)
    --repetitions <n>                 ripetizioni (first-screen e scroll-memory: 5)
    --out <path>                      directory dei risultati (predefinita: Spikes/01-scale-memory/runs)
    --thumbnail-path quicklook|imageio  percorso delle anteprime (predefinito: imageio)
    --window <w>x<h>                  porta di vista (predefinita: 1512x982)
    --scale <s>                       fattore di scala delle anteprime (predefinito: 2)

  Opzioni di first-screen:
    --folders <a,b,…>   cartelle di prima schermata da usare, una per ripetizione, in ordine
                        (predefinite: le prime mai lette)
    --allow-warm        ammette cartelle già lette (cache calda), da dichiarare in RESULT.md

  Opzioni di selection-latency:
    --moves <n>         spostamenti misurati (full: 200, smoke: 40)
    --cadence-ms <ms>   intervallo fra due spostamenti (predefinito: 150)

  Opzioni di retention-band:
    --scroll-speed <s>  velocità di scorrimento in schermate al secondo (predefinita: 3)
    --cycles <n>        cicli di ogni oscillazione (full: 10, smoke: 3)

  Opzioni di scroll-memory:
    --scroll-speed <s>  velocità di scorrimento in schermate al secondo (predefinita: 3)
    --long-session <m>  minuti della sessione di lunga durata (full: 60, smoke: 1)
    --enter-band <s>    soglia di entrata della banda in schermate (predefinita: 1)
    --exit-band <s>     soglia di uscita della banda in schermate (predefinita: 2)

  Opzioni di item-cost (una delle due):
    --cell <lavoro>:<formato>:<classe>  una cella, es. decode:jpeg:M (lavori: io, decode,
                                        quicklook, vision, store, e noop come controllo del
                                        fondo della strumentazione; classe S, M, L o anomalous)
    --all                               tutte le celle, una per sottoprocesso
    --n <n>                             elementi per cella (full: 20, anche minimo; smoke: 3)

  Banco del cancello n°1, versione \(SpikeInfo.version).
  """

func fail(_ message: String, status: Int32) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(status)
}

enum Subcommand: String, CaseIterable {
  case firstScreen = "first-screen"
  case selectionLatency = "selection-latency"
  case retentionBand = "retention-band"
  case scrollMemory = "scroll-memory"
  case itemCost = "item-cost"

  /// Opzioni specifiche ammesse dal sottocomando, con valore.
  var extraOptions: Set<String> {
    switch self {
    case .firstScreen: ["folders"]
    case .selectionLatency: ["moves", "cadence-ms"]
    case .retentionBand: ["scroll-speed", "cycles"]
    case .scrollMemory: ["scroll-speed", "long-session", "enter-band", "exit-band"]
    case .itemCost: ["cell", "n"]
    }
  }
}

// Uscita a righe anche verso una pipe: l'avanzamento delle misure lunghe resta visibile.
setvbuf(stdout, nil, _IOLBF, 0)

var arguments = CommandLine.arguments.dropFirst()
guard let first = arguments.popFirst() else { fail(usage, status: 2) }
if first == "--help" || first == "-h" {
  print(usage)
  exit(0)
}
guard let subcommand = Subcommand(rawValue: first) else {
  fail("sottocomando sconosciuto: \(first)\n\n\(usage)", status: 2)
}

var options = BenchOptions()
while let argument = arguments.popFirst() {
  guard argument.hasPrefix("--") else {
    fail("argomento sconosciuto: \(argument)\n\n\(usage)", status: 2)
  }
  let name = String(argument.dropFirst(2))
  if name == "allow-warm" {
    options.allowWarm = true
    continue
  }
  if name == "all" && subcommand == .itemCost {
    options.extra["all"] = "true"
    continue
  }
  if name == "help" {
    print(usage)
    exit(0)
  }
  guard let value = arguments.popFirst() else {
    fail("opzione \(argument) senza valore\n\n\(usage)", status: 2)
  }
  switch name {
  case "data":
    options.dataDirectory = URL(fileURLWithPath: value, isDirectory: true)
  case "out":
    options.outputDirectory = URL(fileURLWithPath: value, isDirectory: true)
  case "profile":
    guard let profile = DatasetProfile(rawValue: value) else {
      fail("profilo sconosciuto: \(value)\n\n\(usage)", status: 2)
    }
    options.profile = profile
  case "repetitions":
    guard let count = Int(value), count > 0 else {
      fail("valore non valido per --repetitions: \(value)\n\n\(usage)", status: 2)
    }
    options.repetitions = count
  case "thumbnail-path":
    guard let path = ThumbnailPath(rawValue: value) else {
      fail("percorso di anteprima sconosciuto: \(value)\n\n\(usage)", status: 2)
    }
    options.thumbnailPath = path
  case "window":
    let parts = value.split(separator: "x").compactMap { Double($0) }
    guard parts.count == 2, parts.allSatisfy({ $0 > 0 }) else {
      fail("valore non valido per --window: \(value)\n\n\(usage)", status: 2)
    }
    options.window = CGSize(width: parts[0], height: parts[1])
  case "scale":
    guard let scale = Double(value), scale > 0 else {
      fail("valore non valido per --scale: \(value)\n\n\(usage)", status: 2)
    }
    options.thumbnailScale = scale
  default:
    guard subcommand.extraOptions.contains(name) else {
      fail("opzione sconosciuta per \(subcommand.rawValue): \(argument)\n\n\(usage)", status: 2)
    }
    options.extra[name] = value
  }
}

// Verifiche prima di misurare: impronta hardware completa e manifest del dataset presente.
do {
  try HostFingerprint.collect(volumeContaining: options.dataDirectory).assertComplete()
  _ = try LoadedDataset.load(options)
} catch {
  fail("bench: \(error)", status: 1)
}

let writer = ResultWriter(runsDirectory: options.outputDirectory)
let finalOptions = options

// Le corse durano ore a Mac inutilizzato: senza questa asserzione il display si spegnerebbe
// (finestra occlusa, timer rallentati, App Nap) e il sistema potrebbe sospendersi, cambiando le
// condizioni di misura a metà corsa. L'asserzione resta attiva fino all'uscita del processo.
let sleepPrevention =
  "ProcessInfo.beginActivity: userInitiated, idleDisplaySleepDisabled, "
  + "idleSystemSleepDisabled, latencyCritical"
let activity = ProcessInfo.processInfo.beginActivity(
  options: [.userInitiated, .idleDisplaySleepDisabled, .idleSystemSleepDisabled, .latencyCritical],
  reason: "banco del cancello n°1: misura in corso")

/// Scrive il risultato dichiarando la protezione da sospensione attiva durante la misura.
@MainActor
func write(_ result: MeasurementResult) throws {
  var result = result
  result.parameters["sleepPrevention"] = sleepPrevention
  _ = try withExtendedLifetime(activity) { try writer.write(result) }
}

/// Esegue un banco con l'host AppKit: l'applicazione gira sul thread principale e il banco è un
/// compito del `MainActor`; al termine il risultato viene scritto e il processo esce.
@MainActor
func runWithAppKit(_ body: @escaping @MainActor () async throws -> MeasurementResult) -> Never {
  let application = NSApplication.shared
  application.setActivationPolicy(.regular)
  Task { @MainActor in
    do {
      let result = try await body()
      try write(result)
      exit(0)
    } catch {
      fail("bench \(subcommand.rawValue): \(error)", status: 1)
    }
  }
  application.run()
  exit(0)
}

/// Esegue `item-cost` senza host AppKit: una cella, oppure tutte in sottoprocessi.
@MainActor
func runItemCost() -> Never {
  do {
    let bench = try ItemCostBench(options: finalOptions)
    let n = try finalOptions.extra.int("n", default: finalOptions.profile == .full ? 20 : 3)
    if finalOptions.profile == .full && n < 20 {
      fail("item-cost: sul profilo full servono almeno 20 elementi per cella (--n \(n))", status: 2)
    }
    let result: MeasurementResult
    if finalOptions.extra["all"] != nil {
      guard finalOptions.extra["cell"] == nil else {
        fail("item-cost: --all e --cell si escludono\n\n\(usage)", status: 2)
      }
      let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
      result = try bench.runAll(n: n, executable: executable)
    } else {
      guard let label = finalOptions.extra["cell"], let cell = ItemCostCell(parsing: label) else {
        fail(
          "item-cost: serve --cell <lavoro>:<formato>:<classe> oppure --all\n\n\(usage)", status: 2)
      }
      result = try bench.runCell(cell, n: n)
    }
    try write(result)
    exit(0)
  } catch {
    fail("bench item-cost: \(error)", status: 1)
  }
}

if subcommand == .itemCost { runItemCost() }

MainActor.assumeIsolated {
  switch subcommand {
  case .firstScreen:
    runWithAppKit { try await FirstScreenBench(options: finalOptions).run() }
  case .selectionLatency:
    runWithAppKit { try await SelectionLatencyBench(options: finalOptions).run() }
  case .retentionBand:
    runWithAppKit { try await RetentionBandBench(options: finalOptions).run() }
  case .scrollMemory:
    runWithAppKit { try await ScrollMemoryBench(options: finalOptions).run() }
  case .itemCost:
    runItemCost()
  }
}
