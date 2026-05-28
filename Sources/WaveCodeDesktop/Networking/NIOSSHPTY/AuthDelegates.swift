//
//  AuthDelegates.swift
//
//  Client-side auth delegates required by NIOSSHHandler. We support:
//    - Server-side public key auth (no password, no keyboard-interactive)
//    - Trust-on-first-use server key validation (TODO: known_hosts)
//

import Foundation
import NIOCore
import NIOSSH
import Crypto

/// Client user authentication delegate. NIOSSH calls us with the list
/// of methods the server accepts; we offer publickey with our private
/// key (Ed25519 only — RSA via NIOSSH's RSA support is broken with
/// modern OpenSSH same as Citadel, so we don't try).
final class WavePubkeyAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let ed25519Key: Curve25519.Signing.PrivateKey
    private var didOffer = false

    init(username: String, ed25519Key: Curve25519.Signing.PrivateKey) {
        self.username = username
        self.ed25519Key = ed25519Key
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        // We only try once. If publickey fails the second time, give up.
        guard !didOffer, availableMethods.contains(.publicKey) else {
            nextChallengePromise.succeed(nil)
            return
        }
        didOffer = true

        let nioKey = NIOSSHPrivateKey(ed25519Key: ed25519Key)
        let offer = NIOSSHUserAuthenticationOffer(
            username: username,
            serviceName: "",
            offer: .privateKey(.init(privateKey: nioKey))
        )
        nextChallengePromise.succeed(offer)
    }
}

/// Trust-on-first-use server key validator. Production should diff
/// against `~/.ssh/known_hosts` and prompt on mismatch; for v0 we
/// accept whatever the server presents.
final class TOFUHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        // TODO(week-5): known_hosts parsing + user prompt on mismatch.
        validationCompletePromise.succeed(())
    }
}
