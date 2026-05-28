//
//  SSHKey.swift
//
//  Loads OpenSSH-format private keys from `~/.ssh/` and turns them into
//  a Citadel `SSHAuthenticationMethod`. Walks the standard chain:
//      id_ed25519 → id_rsa
//  (Ed25519 first — modern, fast, and not subject to Citadel's
//  ssh-rsa SHA-1 limitation. RSA fallback for legacy setups.)
//
//  Returns a `LoadedAuth` that includes both the auth method AND the
//  path/type of the key we used, so error reporting upstream can be
//  specific about *which* key the server rejected.
//

import Foundation
// @preconcurrency silences the Sendable warning on Citadel's
// SSHAuthenticationMethod — it's a final class without Sendable
// conformance, but it's effectively safe to pass across actor
// boundaries because Citadel performs internal locking. Revisit when
// upstream adopts Sendable annotations.
@preconcurrency import Citadel
import Crypto

enum SSHKeyType: String, Sendable {
    case ed25519
    case rsa
}

/// What we loaded — the auth method ready to hand to Citadel + the
/// breadcrumbs to surface in error messages if the server rejects us.
struct LoadedAuth: Sendable {
    let method: SSHAuthenticationMethod
    let keyPath: String
    let keyType: SSHKeyType
}

enum SSHAuthError: LocalizedError {
    /// We couldn't find any usable key on disk.
    case noUsableKey(triedPaths: [String])
    /// A key file existed but couldn't be parsed (encrypted? corrupt?).
    case keyParseFailed(path: String, underlying: Error)
    /// We loaded a key but the server rejected it. This is a wrapper
    /// constructed by ConnectionManager around Citadel's authentication
    /// error so we can attach the actionable diagnosis.
    case serverRejected(loaded: LoadedAuth, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noUsableKey(let paths):
            return """
            No SSH key found.

            Looked for one of:
              \(paths.joined(separator: "\n  "))

            Generate an Ed25519 key (recommended):
              ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ''
              ssh-copy-id <your-server-host>
            """
        case .keyParseFailed(let path, let err):
            return """
            Could not parse \(path):
              \(err.localizedDescription)

            v0 doesn't yet support passphrase-protected keys. If your \
            key is encrypted, generate a passphrase-less key for now \
            (passphrase + ssh-agent support is on the roadmap).
            """
        case .serverRejected(let loaded, let underlying):
            let common = """
            Server rejected the key at \(loaded.keyPath).
              (\(underlying.localizedDescription))
            """
            switch loaded.keyType {
            case .rsa:
                return common + """


                Likely cause: modern OpenSSH (8.2+) disables ssh-rsa \
                (SHA-1 signatures) by default, and Citadel's RSA \
                implementation only sends that legacy variant.

                Fix: generate an Ed25519 key (better in every way), then \
                authorize it on the server:

                  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ''
                  ssh-copy-id \(extractHost(loaded.keyPath))

                Then click Connect again.
                """
            case .ed25519:
                return common + """


                Ed25519 was tried — server still rejected it. Make sure \
                the matching public key (id_ed25519.pub) is in the \
                server's ~/.ssh/authorized_keys for your account.
                """
            }
        }
    }
}

enum SSHKey {
    /// Load just an Ed25519 private key from `~/.ssh/id_ed25519` (or
    /// fail). Used by the NIOSSH-direct PTY client which can't use
    /// Citadel's broken-against-modern-OpenSSH RSA path. Returns nil
    /// if no Ed25519 key is found / readable.
    static func loadEd25519IfPresent() -> Curve25519.Signing.PrivateKey? {
        guard let home = FileManager.default.homeDirectoryForCurrentUser as URL? else { return nil }
        let url = home.appendingPathComponent(".ssh/id_ed25519")
        guard FileManager.default.isReadableFile(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let key = try? Curve25519.Signing.PrivateKey(sshEd25519: data) else {
            return nil
        }
        return key
    }

    /// Try the standard `~/.ssh/` key chain. Returns the first one we
    /// can build into an `SSHAuthenticationMethod`, with metadata for
    /// downstream error reporting.
    ///
    /// Honors an explicit `identityFile` if provided in the profile —
    /// only that one is tried (useful for users with multiple keys who
    /// want to pin a specific identity per server).
    static func loadAuthMethod(
        username: String,
        explicitIdentityFile: String? = nil
    ) throws -> LoadedAuth {
        var attempted: [String] = []
        var lastParseError: Error?

        let candidates = makeCandidates(explicit: explicitIdentityFile)

        for (url, kind) in candidates {
            attempted.append(url.path)
            guard FileManager.default.isReadableFile(atPath: url.path) else { continue }

            do {
                let data = try Data(contentsOf: url)
                switch kind {
                case .ed25519:
                    let key = try Curve25519.Signing.PrivateKey(sshEd25519: data)
                    return LoadedAuth(
                        method: .ed25519(username: username, privateKey: key),
                        keyPath: url.path,
                        keyType: .ed25519
                    )
                case .rsa:
                    let key = try Insecure.RSA.PrivateKey(sshRsa: data)
                    return LoadedAuth(
                        method: .rsa(username: username, privateKey: key),
                        keyPath: url.path,
                        keyType: .rsa
                    )
                }
            } catch {
                lastParseError = error
                continue
            }
        }

        if let lastParseError, let last = attempted.last {
            throw SSHAuthError.keyParseFailed(path: last, underlying: lastParseError)
        }
        throw SSHAuthError.noUsableKey(triedPaths: attempted)
    }

    // MARK: - Internals

    private static func makeCandidates(explicit: String?) -> [(url: URL, kind: SSHKeyType)] {
        if let explicit, !explicit.isEmpty {
            let url = URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
            // Infer kind from filename heuristics — fall back to RSA
            // because that's the historical default for "id_rsa"-named keys.
            let kind: SSHKeyType = url.lastPathComponent.contains("ed25519") ? .ed25519 : .rsa
            return [(url, kind)]
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let sshDir = home.appendingPathComponent(".ssh", isDirectory: true)
        return [
            (sshDir.appendingPathComponent("id_ed25519"), .ed25519),
            (sshDir.appendingPathComponent("id_rsa"), .rsa),
        ]
    }
}

/// Placeholder for the host name in `ssh-copy-id <host>` suggestions.
/// LocalizedError is non-isolated and synchronous, so we can't reach
/// into the active profile from here — the suggestion is intentionally
/// generic. Future: thread the host through the SSHAuthError payload.
private func extractHost(_: String) -> String {
    return "your-server-host"
}
