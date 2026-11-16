import Darwin
import Foundation
import Testing

@testable import CrashKit

/// Albero di prova in una directory temporanea del volume ospite, senza Cestino:
///
/// ```
/// radice/  a.txt  b.txt  .DS_Store  sub/c.txt
/// ```
///
/// La radice `@cestino` punta a un percorso assente, che deve produrre zero voci.
private struct SnapshotTree {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appending(path: "spike04-snapshot-\(UUID().uuidString)", directoryHint: .isDirectory)
    let sub = root.appending(path: "sub", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try Data("alfa\n".utf8).write(to: url("a.txt"))
    try Data("bravo\n".utf8).write(to: url("b.txt"))
    try Data("nascosto\n".utf8).write(to: url(".DS_Store"))
    try Data("charlie\n".utf8).write(to: url("sub/c.txt"))
  }

  func url(_ relative: String) -> URL {
    root.appending(path: relative, directoryHint: .notDirectory)
  }

  func path(_ relative: String) -> String {
    url(relative).path(percentEncoded: false)
  }

  func capture() throws -> Snapshot {
    try Snapshot.capture(roots: [
      Snapshot.batchKey: root,
      Snapshot.trashKey: root.appending(path: "assente", directoryHint: .isDirectory),
    ])
  }

  func remove() {
    do {
      try FileManager.default.removeItem(at: root)
    } catch {
      Issue.record("rimozione dell'albero di prova fallita: \(error)")
    }
  }
}

/// Scostamenti diversi da `mtime` di directory: quelli che una mutazione nota deve produrre.
private func fileLevel(_ deviations: [Deviation]) -> [Deviation] {
  deviations.filter { !$0.isDirectoryMtime }
}

/// Sovrascrive sul posto il primo byte del file, senza cambiarne la dimensione né l'inode.
private func flipFirstByte(at url: URL) throws {
  let handle = try FileHandle(forUpdating: url)
  defer { try? handle.close() }
  let first = try #require(try handle.read(upToCount: 1)?.first)
  try handle.seek(toOffset: 0)
  try handle.write(contentsOf: Data([first ^ 0x01]))
}

@Suite("Istantanea e confronto campo per campo")
struct SnapshotTests {
  @Test("due catture senza modifiche danno un diff vuoto; radice assente, zero voci")
  func unchangedTreeHasEmptyDiff() throws {
    let tree = try SnapshotTree()
    defer { tree.remove() }

    let before = try tree.capture()
    let after = try tree.capture()
    #expect(Snapshot.diff(before, after).isEmpty)

    // La radice stessa, i file nascosti compresi, la sottocartella; nulla per `@cestino`.
    #expect(
      before.entries.keys.sorted() == [
        "lotto", "lotto/.DS_Store", "lotto/a.txt", "lotto/b.txt", "lotto/sub", "lotto/sub/c.txt",
      ])
    #expect(!before.entries.keys.contains { $0.hasPrefix(Snapshot.trashKey) })
    let file = try #require(before.entries["lotto/a.txt"])
    #expect(file.kind == .file)
    #expect(file.size == 5)
    #expect(file.sha256 == Fixtures.sha256Hex(of: Data("alfa\n".utf8)))
    #expect(file.mode & S_IFMT == S_IFREG)
    let directory = try #require(before.entries["lotto/sub"])
    #expect(directory.kind == .directory)
    #expect(directory.sha256 == nil)
  }

  @Test("una rinomina dà rimosso più aggiunto, con lo stesso inode e lo stesso sha256")
  func renameIsRemovedPlusAdded() throws {
    let tree = try SnapshotTree()
    defer { tree.remove() }
    let before = try tree.capture()

    #expect(rename(tree.path("a.txt"), tree.path("a-rinominato.txt")) == 0)
    let after = try tree.capture()
    let deviations = Snapshot.diff(before, after)

    #expect(
      fileLevel(deviations).map(\.key) == [
        "lotto/a-rinominato.txt:aggiunto", "lotto/a.txt:rimosso",
      ])
    let old = try #require(before.entries["lotto/a.txt"])
    let new = try #require(after.entries["lotto/a-rinominato.txt"])
    #expect(old.inode == new.inode)
    #expect(old.sha256 == new.sha256)
    // La directory che contiene la voce può cambiare `mtime`, e solo quello.
    #expect(deviations.filter(\.isDirectoryMtime).allSatisfy { $0.path == "lotto" })
  }

  @Test("utimensat sul file dà solo mtime")
  func utimensatChangesOnlyMtime() throws {
    let tree = try SnapshotTree()
    defer { tree.remove() }
    let before = try tree.capture()
    let old = try #require(before.entries["lotto/a.txt"])

    // Un mtime successivo alla nascita: uno precedente sposterebbe anche il birthtime.
    let mtime = old.mtime + 3_600_000_000_123
    var times = [
      timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)),
      timespec(tv_sec: Int(mtime / 1_000_000_000), tv_nsec: Int(mtime % 1_000_000_000)),
    ]
    #expect(utimensat(AT_FDCWD, tree.path("a.txt"), &times, AT_SYMLINK_NOFOLLOW) == 0)
    let deviations = Snapshot.diff(before, try tree.capture())

    #expect(deviations.map(\.key) == ["lotto/a.txt:mtime"])
    #expect(deviations.first?.before == String(old.mtime))
    #expect(deviations.first?.after == String(mtime))
    #expect(deviations.first?.isDirectoryMtime == false)
  }

  @Test("chmod dà solo mode")
  func chmodChangesOnlyMode() throws {
    let tree = try SnapshotTree()
    defer { tree.remove() }
    let before = try tree.capture()

    #expect(chmod(tree.path("a.txt"), 0o604) == 0)
    let deviations = Snapshot.diff(before, try tree.capture())

    #expect(deviations.map(\.key) == ["lotto/a.txt:mode"])
    #expect(deviations.first?.after == "100604")
  }

  @Test("setxattr dà solo xattr, con il nome e il digest del valore")
  func setxattrChangesOnlyXattr() throws {
    let tree = try SnapshotTree()
    defer { tree.remove() }
    let before = try tree.capture()

    let name = "it.imagesurfer.prova"
    let value = Array("valore".utf8)
    #expect(setxattr(tree.path("a.txt"), name, value, value.count, 0, XATTR_NOFOLLOW) == 0)
    let after = try tree.capture()
    let deviations = Snapshot.diff(before, after)

    #expect(deviations.map(\.key) == ["lotto/a.txt:xattr"])
    let digest = Fixtures.sha256Hex(of: Data(value))
    #expect(deviations.first?.before == nil)
    #expect(deviations.first?.after == "\(name)=\(digest)")
    #expect(after.entries["lotto/a.txt"]?.xattrs[name] == digest)
  }

  @Test("un byte modificato dà sha256 e mtime sul file, più mtime della directory se cambia")
  func modifiedByteChangesContentFields() throws {
    let tree = try SnapshotTree()
    defer { tree.remove() }
    let before = try tree.capture()

    try flipFirstByte(at: tree.url("b.txt"))
    let after = try tree.capture()
    let deviations = Snapshot.diff(before, after)

    let fileDeviations = fileLevel(deviations)
    #expect(fileDeviations.allSatisfy { $0.path == "lotto/b.txt" })
    #expect(Set(fileDeviations.map(\.field)).isSubset(of: [.sha256, .size, .mtime]))
    #expect(fileDeviations.map(\.field).contains(.sha256))
    #expect(fileDeviations.map(\.field).contains(.mtime))
    #expect(before.entries["lotto/b.txt"]?.inode == after.entries["lotto/b.txt"]?.inode)
    #expect(deviations.filter(\.isDirectoryMtime).allSatisfy { $0.path == "lotto" })
  }

  @Test("l'elenco è ordinato per percorso e per campo, e isDirectoryMtime vale solo per directory")
  func deviationsAreSortedByPathAndField() throws {
    let tree = try SnapshotTree()
    defer { tree.remove() }
    let before = try tree.capture()

    #expect(chmod(tree.path("sub/c.txt"), 0o604) == 0)
    let handle = try FileHandle(forUpdating: tree.url("b.txt"))
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("!".utf8))
    try handle.close()
    try Data("nuovo\n".utf8).write(to: tree.url("sub/nuovo.txt"))
    let deviations = Snapshot.diff(before, try tree.capture())

    #expect(
      deviations.map(\.key) == [
        "lotto/b.txt:size", "lotto/b.txt:sha256", "lotto/b.txt:mtime",
        "lotto/sub:size", "lotto/sub:mtime",
        "lotto/sub/c.txt:mode",
        "lotto/sub/nuovo.txt:aggiunto",
      ])
    #expect(deviations.filter(\.isDirectoryMtime).map(\.key) == ["lotto/sub:mtime"])
  }

  @Test("il JSON dell'istantanea si rilegge identico")
  func jsonRoundTrip() throws {
    let tree = try SnapshotTree()
    defer { tree.remove() }
    let snapshot = try tree.capture()

    let file = tree.url("istantanea.json")
    try snapshot.jsonData().write(to: file)
    #expect(try Snapshot.load(from: file) == snapshot)
  }
}
