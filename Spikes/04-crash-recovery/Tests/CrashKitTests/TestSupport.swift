import Foundation
import Testing

@testable import CrashKit

/// Copia di `fixtures/` in una directory temporanea nuova del volume ospite, da modificare senza
/// toccare le fixture versionate. Chi la usa la rimuove al termine.
func fixtureCopy() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: "spike04-fixtures-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.copyItem(at: CrashPaths.fixtures, to: directory)
  return directory
}

/// Esito di un'esecuzione del binario `crashbench` reale, come lo osserva il processo padre.
typealias CrashbenchResult = (
  reason: Process.TerminationReason, status: Int32, stdout: String, stderr: String
)

/// Esegue il binario `crashbench` reale, costruito insieme alla suite in `.build/debug`, come
/// processo figlio con la directory dati `dataDir` (`--data-dir` è aggiunto in coda).
///
/// Legge stdout e stderr fino alla chiusura dei pipe, e solo dopo chiama `waitUntilExit`. stderr è
/// letto su un thread dedicato, così che un pipe pieno non blocchi il figlio mentre il padre legge
/// l'altro. Il motivo e lo stato sono quelli del figlio stesso: un arresto per `SIGKILL` dà
/// `.uncaughtSignal` con stato 9, non lo stato 137 che riporterebbe una shell.
func runCrashbench(_ args: [String], dataDir: URL) throws -> CrashbenchResult {
  let binary = CrashPaths.packageRoot.appending(
    path: ".build/debug/crashbench", directoryHint: .notDirectory)
  try #require(
    FileManager.default.isExecutableFile(atPath: binary.fileSystemPath),
    "binario assente: \(binary.fileSystemPath)")
  let process = Process()
  process.executableURL = binary
  process.arguments = args + ["--data-dir", dataDir.fileSystemPath]
  process.standardInput = FileHandle.nullDevice
  let stdout = Pipe()
  let stderr = Pipe()
  process.standardOutput = stdout
  process.standardError = stderr
  try process.run()
  let errorReader = PipeReader(stderr.fileHandleForReading)
  let output = stdout.fileHandleForReading.readDataToEndOfFile()
  let errorOutput = errorReader.wait()
  process.waitUntilExit()
  return (
    process.terminationReason, process.terminationStatus,
    String(decoding: output, as: UTF8.self), String(decoding: errorOutput, as: UTF8.self)
  )
}

/// Legge un `FileHandle` fino alla fine su un thread dedicato; `wait()` restituisce i byte letti.
/// Il semaforo ordina la scrittura di `data` sul thread prima della lettura in `wait()`.
private final class PipeReader: @unchecked Sendable {
  private let done = DispatchSemaphore(value: 0)
  private var data = Data()

  init(_ handle: FileHandle) {
    Thread.detachNewThread { [self] in
      data = handle.readDataToEndOfFile()
      done.signal()
    }
  }

  func wait() -> Data {
    done.wait()
    return data
  }
}

/// Volume di lavoro dedicato a un test, con una propria directory dati
/// `.data/tests/<name>-<UUID>`: immagine creata, volume montato e cartella di prova ripristinata.
///
/// Chi lo apre chiama `defer { volume.close() }`, che espelle il volume e rimuove la directory: nessun
/// test lascia volumi montati.
struct TestVolume {
  let dataDirectory: URL
  let volume: WorkVolume

  init(name: String) throws {
    dataDirectory = CrashPaths.defaultDataDirectory
      .appending(path: "tests/\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    volume = WorkVolume(dataDirectory: dataDirectory)
    do {
      try volume.ensureImage()
      try volume.attach()
      try volume.resetBatchFolder()
    } catch {
      close()
      throw error
    }
  }

  /// Espelle il volume e rimuove la directory dati. Se il volume resta montato la directory non viene
  /// rimossa, perché la rimozione scenderebbe nel volume, e il test fallisce.
  func close() {
    do {
      try volume.eject()
    } catch {
      Issue.record("espulsione del volume di prova fallita: \(error)")
    }
    guard !volume.isMounted else {
      Issue.record(
        "volume di prova ancora montato: \(volume.mountPoint.fileSystemPath)")
      return
    }
    do {
      try FileManager.default.removeItem(at: dataDirectory)
    } catch {
      Issue.record("rimozione della directory dati di prova fallita: \(error)")
    }
  }
}
