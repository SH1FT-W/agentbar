// Ed25519 key for update signatures.
//   release-key <App> generate     create the private key (once) and print the public key
//   release-key <App> public       print the public key (goes into the app's Updater as publicKey)
//   release-key <App> sign <file>  print the signature (Base64) of a file
// The private key lives ONLY locally: ~/Library/Application Support/<App> Release/ed25519.key (0600).
// Whoever publishes releases needs this file. Keep it safe, never put it into a repository.
import CryptoKit
import Foundation

let args = Array(CommandLine.arguments.dropFirst())

func fail(_ text: String) -> Never {
    FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
    exit(1)
}

guard args.count >= 2 else { fail("Usage: release-key <App> generate | public | sign <file>") }
let app = args[0]
let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/\(app) Release")
let keyFile = dir.appendingPathComponent("ed25519.key")

func loadKey() -> Curve25519.Signing.PrivateKey {
    guard let b64 = try? String(contentsOf: keyFile, encoding: .utf8),
          let raw = Data(base64Encoded: b64.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("No key at \(keyFile.path). Run `generate` first.")
    }
    return key
}

switch args[1] {
case "generate":
    guard !FileManager.default.fileExists(atPath: keyFile.path) else { fail("Key exists already, not overwritten.") }
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let key = Curve25519.Signing.PrivateKey()
    FileManager.default.createFile(atPath: keyFile.path, contents: key.rawRepresentation.base64EncodedString().data(using: .utf8),
                                   attributes: [.posixPermissions: 0o600])
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    print(loadKey().publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard args.count >= 3, let data = FileManager.default.contents(atPath: args[2]) else { fail("Usage: release-key <App> sign <file>") }
    print(try! loadKey().signature(for: data).base64EncodedString())
default:
    fail("Usage: release-key <App> generate | public | sign <file>")
}
