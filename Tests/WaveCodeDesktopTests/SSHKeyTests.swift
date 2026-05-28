//
//  SSHKeyTests.swift
//
//  Tests for the SSH key loading paths. We can't easily test the
//  actual `~/.ssh/` chain in CI (no keys there), but we can verify
//  the error shapes and edge-case behaviour.
//

import XCTest
@testable import WaveCodeDesktop

final class SSHKeyTests: XCTestCase {
    func test_serverRejected_RSA_suggestsEd25519() {
        let loaded = LoadedAuth(
            method: .passwordBased(username: "x", password: "y"),  // shape only; not used in description
            keyPath: "/Users/test/.ssh/id_rsa",
            keyType: .rsa
        )
        let err = SSHAuthError.serverRejected(loaded: loaded, underlying: TestError())
        let msg = err.errorDescription ?? ""
        XCTAssertTrue(msg.contains("/Users/test/.ssh/id_rsa"), "should cite the actual key path")
        XCTAssertTrue(msg.contains("ssh-rsa"), "should explain the ssh-rsa limitation")
        XCTAssertTrue(msg.contains("ssh-keygen -t ed25519"), "should suggest creating an Ed25519 key")
    }

    func test_serverRejected_Ed25519_pointsToAuthorizedKeys() {
        let loaded = LoadedAuth(
            method: .passwordBased(username: "x", password: "y"),
            keyPath: "/Users/test/.ssh/id_ed25519",
            keyType: .ed25519
        )
        let err = SSHAuthError.serverRejected(loaded: loaded, underlying: TestError())
        let msg = err.errorDescription ?? ""
        XCTAssertTrue(msg.contains("authorized_keys"),
                      "should suggest authorizing the key when ed25519 is rejected (not the RSA fix)")
    }

    func test_noUsableKey_listsTriedPaths() {
        let paths = ["/Users/test/.ssh/id_ed25519", "/Users/test/.ssh/id_rsa"]
        let err = SSHAuthError.noUsableKey(triedPaths: paths)
        let msg = err.errorDescription ?? ""
        XCTAssertTrue(msg.contains("id_ed25519"))
        XCTAssertTrue(msg.contains("id_rsa"))
        XCTAssertTrue(msg.contains("ssh-keygen"))
    }

    /// loadEd25519IfPresent returns nil when no file exists, doesn't throw.
    /// In CI this should be nil; on a dev machine with id_ed25519 it'll
    /// return non-nil. Either way it must not crash.
    func test_loadEd25519IfPresent_doesNotCrash() {
        _ = SSHKey.loadEd25519IfPresent()
    }
}

private struct TestError: LocalizedError {
    var errorDescription: String? { "test failure" }
}
