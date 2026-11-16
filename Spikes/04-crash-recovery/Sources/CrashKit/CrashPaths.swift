import Foundation

/// Percorsi del pacchetto del banco, risolti dalla posizione dei sorgenti e quindi
/// indipendenti dalla directory corrente da cui viene lanciato `swift run` o il binario.
public enum CrashPaths {
  /// `Spikes/04-crash-recovery`.
  public static var packageRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Sources/CrashKit
      .deletingLastPathComponent()  // Sources
      .deletingLastPathComponent()  // radice del pacchetto
  }

  /// `Spikes/04-crash-recovery/fixtures`, le fixture versionate del lotto di prova.
  public static var fixtures: URL {
    packageRoot.appending(path: "fixtures", directoryHint: .isDirectory)
  }

  /// `Spikes/04-crash-recovery/fixtures/folder`, la cartella con le cinque coppie
  /// immagine+sidecar.
  public static var fixtureFolder: URL {
    fixtures.appending(path: "folder", directoryHint: .isDirectory)
  }

  /// `Spikes/04-crash-recovery/.data`, la directory dei dati generati: immagine disco, punto di
  /// montaggio e stato durevole del banco (non versionata, `.gitignore`: `Spikes/*/.data/`).
  public static var defaultDataDirectory: URL {
    packageRoot.appending(path: ".data", directoryHint: .isDirectory)
  }

  /// `Spikes/04-crash-recovery/runs`, le esecuzioni di scarto della matrice (non versionate,
  /// `.gitignore`: `Spikes/*/runs/`).
  public static var runs: URL {
    packageRoot.appending(path: "runs", directoryHint: .isDirectory)
  }

  /// `Spikes/04-crash-recovery/measurements`, la misura scelta e versionata.
  public static var measurements: URL {
    packageRoot.appending(path: "measurements", directoryHint: .isDirectory)
  }
}
