import BenchKit
import Foundation

let usage = """
  uso: gen-dataset [--config <path>] [--out <path>] [--profile full|smoke] [--force]

    --config <path>   configurazione del dataset (predefinita: Spikes/01-scale-memory/dataset.json)
    --out <path>      directory di uscita (predefinita: Spikes/01-scale-memory/.data)
    --profile <p>     full (misura, circa 140 GB) oppure smoke (verifica, meno di 1 GB); predefinito full
    --force           rigenera rimuovendo un dataset già presente nella directory di uscita

  Banco del cancello n°1, versione \(SpikeInfo.version).
  """

func fail(_ message: String, status: Int32) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(status)
}

var configURL = SpikePaths.defaultConfig
var outputURL = SpikePaths.defaultDataDirectory
var profile = DatasetProfile.full
var force = false

var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
  switch argument {
  case "--config", "--out", "--profile":
    guard let value = arguments.popFirst() else {
      fail("opzione \(argument) senza valore\n\n\(usage)", status: 2)
    }
    switch argument {
    case "--config": configURL = URL(fileURLWithPath: value)
    case "--out": outputURL = URL(fileURLWithPath: value, isDirectory: true)
    default:
      guard let parsed = DatasetProfile(rawValue: value) else {
        fail("profilo sconosciuto: \(value)\n\n\(usage)", status: 2)
      }
      profile = parsed
    }
  case "--force":
    force = true
  case "--help", "-h":
    print(usage)
    exit(0)
  default:
    fail("argomento sconosciuto: \(argument)\n\n\(usage)", status: 2)
  }
}

do {
  let generator = try DatasetGenerator(
    configURL: configURL, profile: profile, outputDirectory: outputURL, force: force)
  _ = try await generator.generate()
} catch {
  fail("gen-dataset: \(error)", status: 1)
}
