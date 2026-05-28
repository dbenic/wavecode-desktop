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
import Crypto
import OSLog

@MainActor
final class ConnectionManager {
    static let shared = ConnectionManager()

    private let log = Logger(subsystem: "com.wavenetic.wavecode-desktop", category: "ssh")
    private let api = WaveCodeAPI()

    /// Citadel handles the high-level conveniences (executeCommand for
    /// the WaveCode API fetch). It's a `final class` that performs its
    /// own internal NIO-based locking — thread-safe in practice.
    private var client: SSHClient?
    private var activePort: Int = 3777
    private var agentRefreshTask: Task<Void, Never>?

    /// Direct-NIOSSH client for PTY (terminal) channels. Separate
    /// connection from Citadel so we can request PTYs with proper
    /// controlling-terminal semantics + window_change support — things
    /// Citadel's withTTY API doesn't expose.
    private let ptyClient = NIOSSHPTYClient()
    private var loadedEd25519Key: Curve25519.Signing.PrivateKey?

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

            // Also bring up the NIOSSH-direct connection used for PTYs.
            // For now we require an Ed25519 key (the only auth path
            // NIOSSH-side supports cleanly; same key the user already
            // proved works via Citadel).
            if let ed25519 = SSHKey.loadEd25519IfPresent() {
                do {
                    try await ptyClient.connect(
                        host: profile.sshHost,
                        port: profile.sshPort,
                        username: username,
                        ed25519Key: ed25519
                    )
                    self.loadedEd25519Key = ed25519
                } catch {
                    log.warning("niossh: PTY client connect failed (terminals will be unavailable): \(String(describing: error), privacy: .public)")
                }
            } else {
                log.warning("niossh: no Ed25519 key — terminals will be unavailable. Generate one with: ssh-keygen -t ed25519")
            }

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
        await ptyClient.disconnect()
        loadedEd25519Key = nil
        appState.connectionStatus = .disconnected
        // New connection target = previous agents are unreachable.
        // Drop the visited set so we don't try to re-render dead
        // TerminalViews against a fresh SSH connection.
        appState.clearVisited()
        appState.agents = []
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

    /// Open a PTY-backed shell session that immediately exec's
    /// `command` (typically `tmux attach -t …`). Returns a session
    /// the caller uses to send keystrokes, resize, and close.
    ///
    /// Throws if there is no active NIOSSH PTY connection.
    func openTerminalSession(
        command: String,
        cols: Int,
        rows: Int,
        onBytes: @escaping TerminalByteSink,
        onClosed: @escaping @Sendable (Error?) -> Void = { _ in }
    ) async throws -> TerminalSession {
        guard ptyClient.isConnected else {
            throw NSError(
                domain: "WaveCodeDesktop",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey:
                    "PTY connection unavailable — generate an Ed25519 SSH key (ssh-keygen -t ed25519) and authorize it on the server."]
            )
        }
        let ptySession = try await ptyClient.openShellPTY(
            cols: cols,
            rows: rows,
            command: command
        )
        let session = TerminalSession(
            ptySession: ptySession,
            onBytes: onBytes,
            onClosed: onClosed
        )
        session.start()
        return session
    }
}

