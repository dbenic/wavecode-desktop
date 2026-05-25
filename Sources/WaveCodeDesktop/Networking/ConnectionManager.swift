//
//  ConnectionManager.swift
//
//  Owns the active SSH connection. Singleton (one SSH session per app
//  process) — multi-server support layers on top later.
//
//  Connects via Citadel using a key from `~/.ssh/`. Failure surfaces
//  through AppState.connectionError so the UI can show it.
//

import Foundation
import Citadel
import OSLog

@MainActor
final class ConnectionManager {
    static let shared = ConnectionManager()

    private let log = Logger(subsystem: "com.wavenetic.wavecode-desktop", category: "ssh")

    /// Citadel's SSHClient is a `final class` that performs its own
    /// internal NIO-based locking — thread-safe in practice.
    private var client: SSHClient?

    private init() {}

    /// True if there's a live SSH session we can open channels on.
    var isConnected: Bool { client != nil }

    /// Establish (or replace) the SSH connection.
    func connect(profile: ServerProfile, into appState: AppState) async {
        guard appState.connectionStatus != .connected,
              appState.connectionStatus != .connecting else { return }

        appState.connectionStatus = .connecting
        appState.connectionError = nil
        log.info("ssh: connecting to \(profile.sshHost, privacy: .public):\(profile.sshPort, privacy: .public)")

        let username = profile.sshUser ?? NSUserName()

        do {
            let auth = try SSHKey.loadAuthMethod(username: username)
            let newClient = try await SSHClient.connect(
                host: profile.sshHost,
                port: profile.sshPort,
                authenticationMethod: auth,
                // TOFU. TODO(week-5): parse ~/.ssh/known_hosts and prompt on mismatch.
                hostKeyValidator: .acceptAnything(),
                reconnect: .never
            )
            self.client = newClient
            appState.connectionStatus = .connected
            log.info("ssh: connected as \(username, privacy: .public)")

            // Load sample agents so the sidebar has content until week 2
            // wires the live `/api/agents` fetch over the port-forward.
            if appState.agents.isEmpty {
                appState.agents = SampleData.agents
            }
        } catch {
            self.client = nil
            appState.connectionStatus = .error
            appState.connectionError = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
            log.error("ssh: connect failed: \(String(describing: error), privacy: .public)")
        }
    }

    func disconnect(_ appState: AppState) async {
        if let client {
            try? await client.close()
        }
        client = nil
        appState.connectionStatus = .disconnected
        log.info("ssh: disconnected")
    }

    /// Open a TTY session running `command` (typically `tmux attach -t …`)
    /// and start streaming bytes to `onBytes`. Returns the session so the
    /// caller can `send(...)` keystrokes and `close()` on view teardown.
    ///
    /// Throws if there is no active SSH connection.
    func openTerminalSession(
        command: String,
        onBytes: @escaping TerminalByteSink,
        onClosed: @escaping @Sendable (Error?) -> Void = { _ in }
    ) throws -> TerminalSession {
        guard let client else {
            throw NSError(
                domain: "WaveCodeDesktop",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No active SSH connection"]
            )
        }
        let session = TerminalSession(
            client: client,
            command: command,
            onBytes: onBytes,
            onClosed: onClosed
        )
        session.start()
        return session
    }
}

/// Hardcoded sample agents until week 2 wires the live feed.
enum SampleData {
    static let agents: [Agent] = [
        Agent(id: "sample-1", name: "cl-backend", runtime: "claude-code", tmuxSession: "cl-backend", workspace: nil, mode: .spawned, status: .working, createdAt: ""),
        Agent(id: "sample-2", name: "cl-api", runtime: "claude-code", tmuxSession: "cl-api", workspace: nil, mode: .spawned, status: .working, createdAt: ""),
        Agent(id: "sample-3", name: "cl-wavebid", runtime: "claude-code", tmuxSession: "cl-wavebid", workspace: nil, mode: .adopted, status: .idle, createdAt: ""),
        Agent(id: "sample-4", name: "cl-wavestorm", runtime: "claude-code", tmuxSession: "cl-wavestorm", workspace: nil, mode: .adopted, status: .idle, createdAt: ""),
        Agent(id: "sample-5", name: "wavepulse", runtime: "claude-code", tmuxSession: "wavepulse", workspace: nil, mode: .adopted, status: .idle, createdAt: ""),
    ]
}
