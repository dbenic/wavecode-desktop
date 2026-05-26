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
    private let api = WaveCodeAPI()

    /// Citadel's SSHClient is a `final class` that performs its own
    /// internal NIO-based locking — thread-safe in practice.
    private var client: SSHClient?
    private var activePort: Int = 3777
    private var agentRefreshTask: Task<Void, Never>?

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
            let loaded = try SSHKey.loadAuthMethod(
                username: username,
                explicitIdentityFile: profile.identityFile
            )
            log.info("ssh: trying \(loaded.keyType.rawValue, privacy: .public) key at \(loaded.keyPath, privacy: .public)")

            let newClient: SSHClient
            do {
                newClient = try await SSHClient.connect(
                    host: profile.sshHost,
                    port: profile.sshPort,
                    authenticationMethod: loaded.method,
                    // TOFU. TODO(week-5): parse ~/.ssh/known_hosts and prompt on mismatch.
                    hostKeyValidator: .acceptAnything(),
                    reconnect: .never
                )
            } catch {
                // Wrap Citadel's "allAuthenticationOptionsFailed" (or any
                // auth-time error) with our key context + suggested fix.
                throw SSHAuthError.serverRejected(loaded: loaded, underlying: error)
            }
            self.client = newClient
            self.activePort = profile.wavecodePort
            appState.connectionStatus = .connected
            log.info("ssh: connected as \(username, privacy: .public)")

            // Fetch the real agent list from the server.
            await refreshAgents(into: appState)
        } catch {
            self.client = nil
            appState.connectionStatus = .error
            appState.connectionError = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
            log.error("ssh: connect failed: \(String(describing: error), privacy: .public)")
        }
    }

    func disconnect(_ appState: AppState) async {
        agentRefreshTask?.cancel()
        agentRefreshTask = nil
        if let client {
            try? await client.close()
        }
        client = nil
        appState.connectionStatus = .disconnected
        log.info("ssh: disconnected")
    }

    /// One-shot fetch of `/api/agents`. Pushes the result into AppState.
    /// Surfaces a connectionError on failure but leaves the connection
    /// itself intact — fetch problems shouldn't kick the user out.
    func refreshAgents(into appState: AppState) async {
        guard let client else { return }
        do {
            let agents = try await api.fetchAgents(via: client, wavecodePort: activePort)
            appState.agents = agents
            log.info("api: loaded \(agents.count, privacy: .public) agents")
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
            appState.connectionError = msg
            log.error("api: agent fetch failed: \(msg, privacy: .public)")
        }
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

