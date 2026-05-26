//
//  ServerProfile.swift
//
//  User-configured SSH connection profile. Persisted in UserDefaults
//  (non-sensitive fields) + macOS Keychain (any bearer token). Never
//  sent to the server.
//

import Foundation

struct ServerProfile: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var label: String
    var sshHost: String
    var sshUser: String?
    var sshPort: Int = 22
    /// Server-side WaveCode HTTP port. Default 3777.
    var wavecodePort: Int = 3777
    /// Optional explicit private key path. If nil, defaults from ~/.ssh/
    /// or ssh-agent are tried in order.
    var identityFile: String?

    static let defaultLocal = ServerProfile(
        label: "wave (default)",
        sshHost: "wave",
        sshUser: nil,
        sshPort: 22,
        wavecodePort: 3777
    )

    /// Build a blank profile for the "+ Add" action — distinct UUID,
    /// generic label/host so the user fills it in.
    static func newDraft() -> ServerProfile {
        ServerProfile(
            label: "New server",
            sshHost: "",
            sshUser: nil,
            sshPort: 22,
            wavecodePort: 3777
        )
    }
}

enum ConnectionStatus: String, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case error
}
