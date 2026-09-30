// Ed25519-Schlüssel für Update-Signaturen.
//   release-key generate      → privaten Schlüssel anlegen (nur einmal), öffentlichen ausgeben
//   release-key public        → öffentlichen Schlüssel ausgeben (für Updater.publicKey)
//   release-key sign <datei>  → Signatur (Base64) ausgeben
// Der private Schlüssel liegt NUR lokal: ~/Library/Application Support/AgentBar Release/ed25519.key (0600).
// Wer Releases veröffentlichen will, braucht diese Datei – sicher aufbewahren, nie ins Repo.
import CryptoKit
import Foundation

let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/AgentBar Release")
let keyFile = dir.appendingPathComponent("ed25519.key")
let args = CommandLine.arguments.dropFirst()

func loadKey() -> Curve25519.Signing.PrivateKey {
    guard let b64 = try? String(contentsOf: keyFile, encoding: .utf8),
          let raw = Data(base64Encoded: b64.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        FileHandle.standardError.write("Kein Schlüssel unter \(keyFile.path) – erst `generate`\n".data(using: .utf8)!)
        exit(1)
    }
    return key
}

switch args.first {
case "generate":
    guard !FileManager.default.fileExists(atPath: keyFile.path) else {
        FileHandle.standardError.write("Schlüssel existiert schon – nicht überschrieben.\n".data(using: .utf8)!)
        exit(1)
    }
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let key = Curve25519.Signing.PrivateKey()
    FileManager.default.createFile(atPath: keyFile.path, contents: key.rawRepresentation.base64EncodedString().data(using: .utf8),
                                   attributes: [.posixPermissions: 0o600])
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    print(loadKey().publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard let path = args.dropFirst().first, let data = FileManager.default.contents(atPath: path) else {
        FileHandle.standardError.write("Aufruf: release-key sign <datei>\n".data(using: .utf8)!); exit(1)
    }
    print(try! loadKey().signature(for: data).base64EncodedString())
default:
    FileHandle.standardError.write("Aufruf: release-key generate | public | sign <datei>\n".data(using: .utf8)!)
    exit(1)
}
