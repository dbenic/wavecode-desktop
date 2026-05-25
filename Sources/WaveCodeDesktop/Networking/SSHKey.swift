//
//  SSHKey.swift
//
//  Loads OpenSSH-format private keys from `~/.ssh/` and turns them into
//  a Citadel `SSHAuthenticationMethod`. Walks the standard chain:
//      id_ed25519 → id_rsa → id_ecdsa
//
//  Returns the first one that parses cleanly. v0 doesn't support
//  encrypted keys (no passphrase prompt yet) or ssh-agent — those land
//  in week 5 alongside profile management.
//

import Foundation
import Citadel
import Crypto

enum SSHAuthError: LocalizedError {
    case noUsableKey(triedPaths: [String])
    case keyParseFailed(path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noUsableKey(let paths):
            return """
            No usable SSH key found. Tried:
              \(paths.joined(separator: "\n  "))
            Make sure one of these files exists, is readable, and is NOT \
            passphrase-encrypted (passphrase support lands in a later \
            milestone — until then use a key without a passphrase or \
            unlock it with ssh-add ahead of launching this app).
            """
        case .keyParseFailed(let path, let err):
            return "Could not parse \(path): \(err.localizedDescription)"
        }
    }
}

enum SSHKey {
    /// Try the standard `~/.ssh/` key chain. Returns the first auth method
    /// we can build, or throws `noUsableKey` with the paths we tried.
    static func loadAuthMethod(username: String) throws -> SSHAuthenticationMethod {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sshDir = home.appendingPathComponent(".ssh", isDirectory: true)

        let candidates: [(name: String, kind: KeyKind)] = [
            ("id_ed25519", .ed25519),
            ("id_rsa", .rsa),
            // ECDSA support could land later — Citadel exposes it via SSHCert
            // but the API requires more glue than ed25519/rsa.
        ]

        var attempted: [String] = []
        var lastParseError: Error?

        for (name, kind) in candidates {
            let url = sshDir.appendingPathComponent(name)
            attempted.append(url.path)
            guard FileManager.default.isReadableFile(atPath: url.path) else { continue }

            do {
                let data = try Data(contentsOf: url)
                switch kind {
                case .ed25519:
                    let key = try Curve25519.Signing.PrivateKey(sshEd25519: data)
                    return .ed25519(username: username, privateKey: key)
                case .rsa:
                    let key = try Insecure.RSA.PrivateKey(sshRsa: data)
                    return .rsa(username: username, privateKey: key)
                }
            } catch {
                lastParseError = error
                continue
            }
        }

        if let lastParseError, !attempted.isEmpty {
            throw SSHAuthError.keyParseFailed(path: attempted.last!, underlying: lastParseError)
        }
        throw SSHAuthError.noUsableKey(triedPaths: attempted)
    }

    private enum KeyKind {
        case ed25519, rsa
    }
}
