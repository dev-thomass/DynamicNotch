//
//  sparkle-key.swift
//  DynamicNotch — outils de release
//
//  Clés EdDSA (Ed25519) au format Sparkle, sans dépendance :
//
//      swift sparkle-key.swift generate                    → clé privée puis clé publique
//      swift sparkle-key.swift public < cle-privee.txt     → clé publique
//      swift sparkle-key.swift verify FICHIER SIGNATURE CLE_PUBLIQUE
//
//  Format Sparkle : la clé privée est la graine de 32 octets en base64 (ce
//  qu'exporte `generate_keys -x`), la clé publique 32 octets en base64
//  (valeur de `SUPublicEDKey`). La signature couvre le fichier entier.
//

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("erreur : \(message)\n".utf8))
    exit(1)
}

func readPrivateKey() -> Curve25519.Signing.PrivateKey {
    let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    guard let seed = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)),
          seed.count == 32,
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else { fail("clé privée invalide (attendu : graine Ed25519 de 32 octets en base64)") }
    return key
}

func verify(file: String, signature: String, publicKey: String) {
    guard let data = FileManager.default.contents(atPath: file) else { fail("fichier illisible : \(file)") }
    guard let signatureData = Data(base64Encoded: signature) else { fail("signature base64 invalide") }
    guard let raw = Data(base64Encoded: publicKey),
          let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { fail("clé publique invalide") }
    guard key.isValidSignature(signatureData, for: data) else { fail("signature INVALIDE pour \(file)") }
    print("signature valide")
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "generate":
    let key = Curve25519.Signing.PrivateKey()
    print(key.rawRepresentation.base64EncodedString())
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    print(readPrivateKey().publicKey.rawRepresentation.base64EncodedString())
case "verify" where arguments.count == 4:
    verify(file: arguments[1], signature: arguments[2], publicKey: arguments[3])
default:
    fail("usage : sparkle-key.swift generate | public | verify FICHIER SIGNATURE CLE_PUBLIQUE")
}
