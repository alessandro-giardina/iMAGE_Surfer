// swift-tools-version:6.0
// Banco di misura del cancello n°1 (US-001). Materiale usa-e-getta sotto Spikes/:
// nessuna dipendenza esterna, nessun progetto Xcode, nessun riuso nel prodotto.
import Foundation
import PackageDescription

let strictSwift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

// Con i soli Command Line Tools (nessun Xcode), il sistema di build predefinito di
// SwiftPM 6.4 trova Testing.framework ma non passa al compilatore il percorso del
// plugin delle macro di Swift Testing (`@Test`, `#expect`), e la suite non compila.
// Il percorso viene aggiunto solo se esiste: con Xcode installato il flag è assente.
let commandLineToolsTestingPlugins =
    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testingMacroPluginSettings: [SwiftSetting] =
    FileManager.default.fileExists(atPath: commandLineToolsTestingPlugins)
    ? [.unsafeFlags(["-plugin-path", commandLineToolsTestingPlugins])]
    : []

let package = Package(
    name: "ScaleMemorySpike",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "BenchKit",
            swiftSettings: strictSwift6
        ),
        .executableTarget(
            name: "gen-dataset",
            dependencies: ["BenchKit"],
            swiftSettings: strictSwift6
        ),
        .executableTarget(
            name: "bench",
            dependencies: ["BenchKit"],
            swiftSettings: strictSwift6
        ),
        .testTarget(
            name: "BenchKitTests",
            // `bench` è una dipendenza perché i test di integrazione eseguono il binario reale:
            // così `swift test` lo ricostruisce insieme alla suite e non usa un binario vecchio.
            dependencies: ["BenchKit", "bench"],
            swiftSettings: strictSwift6 + testingMacroPluginSettings
        ),
    ]
)
