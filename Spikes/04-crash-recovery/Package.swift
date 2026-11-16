// swift-tools-version:6.0
// Banco del cancello n°4 (US-004): iniezione di arresti in un lotto di operazioni su file e
// misura dell'esito raggiunto dopo il recupero, per confermare o emendare ADR-007.
// Materiale usa-e-getta sotto Spikes/: nessuna dipendenza esterna, nessun progetto Xcode,
// nessuna dipendenza da Spikes/01-scale-memory, nessun riuso nel prodotto.
import Foundation
import PackageDescription

let strictSwift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

// Con i soli Command Line Tools (nessun Xcode), il sistema di build predefinito di
// SwiftPM 6.4 trova Testing.framework ma non passa al compilatore il percorso del
// plugin delle macro di Swift Testing (`@Test`, `#expect`), e la suite non compila.
// Il percorso viene aggiunto solo se esiste: con Xcode installato il flag è assente.
// Blocco copiato da Spikes/01-scale-memory/Package.swift, non importato.
let commandLineToolsTestingPlugins =
  "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testingMacroPluginSettings: [SwiftSetting] =
  FileManager.default.fileExists(atPath: commandLineToolsTestingPlugins)
  ? [.unsafeFlags(["-plugin-path", commandLineToolsTestingPlugins])]
  : []

let package = Package(
  name: "CrashRecoverySpike",
  platforms: [.macOS(.v15)],
  targets: [
    .target(
      name: "CrashKit",
      swiftSettings: strictSwift6
    ),
    .executableTarget(
      name: "crashbench",
      dependencies: ["CrashKit"],
      swiftSettings: strictSwift6
    ),
    .testTarget(
      name: "CrashKitTests",
      // `crashbench` è una dipendenza perché i test di integrazione eseguono il binario reale:
      // così `swift test` lo ricostruisce insieme alla suite e non usa un binario vecchio.
      dependencies: ["CrashKit", "crashbench"],
      swiftSettings: strictSwift6 + testingMacroPluginSettings
    ),
  ]
)
