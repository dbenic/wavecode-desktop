//
//  ConnectionManager.swift
//
//  Owns the active SSH connection. Singleton (one SSH session per app
//  process) — multi-server support layers on top later.
//
//  v0 stub: simulates a successful connection so the rest of the app
//  flow can be exercised. Real Citadel SSH client wiring lands week 1
//  alongside the PTY plumbing.
//

import Foundation

@MainActor
final class ConnectionManager {
    static let shared = ConnectionManager()

    private var sshClient: AnyObject? // Will be Citadel's SSHClient
    private var hasPopulatedSamples = false

    private init() {}

    func connect(profile: ServerProfile, into appState: AppState) async {
        guard appState.connectionStatus != .connected,
              appState.connectionStatus != .connecting else { return }

        appState.connectionStatus = .connecting
        appState.connectionError = nil

        // TODO(week-1): real Citadel client
        // let client = try await SSHClient.connect(
        //     host: profile.sshHost,
        //     authenticationMethod: .ed25519(...),
        //     hostKeyValidator: .acceptAnything(),
        //     reconnect: .always
        // )

        // v0 stub: pretend, populate sample agents so the sidebar isn't empty
        try? await Task.sleep(nanoseconds: 400_000_000)
        appState.connectionStatus = .connected

        if !hasPopulatedSamples {
            hasPopulatedSamples = true
            appState.agents = SampleData.agents
        }
    }

    func disconnect(_ appState: AppState) async {
        appState.connectionStatus = .disconnected
        sshClient = nil
    }
}

/// Hardcoded sample data so the UI has something to render before the
/// live agent feed (week 2 — fetched from /api/agents via the SSH
/// port-forward, then live-updated via SSE).
enum SampleData {
    static let agents: [Agent] = [
        Agent(id: "sample-1", name: "cl-backend", runtime: "claude-code", tmuxSession: "cl-backend", workspace: nil, mode: .spawned, status: .working, createdAt: ""),
        Agent(id: "sample-2", name: "cl-api", runtime: "claude-code", tmuxSession: "cl-api", workspace: nil, mode: .spawned, status: .working, createdAt: ""),
        Agent(id: "sample-3", name: "codex-tests", runtime: "codex", tmuxSession: "codex-tests", workspace: nil, mode: .spawned, status: .idle, createdAt: ""),
        Agent(id: "sample-4", name: "aider-docs", runtime: "aider", tmuxSession: "aider-docs", workspace: nil, mode: .spawned, status: .idle, createdAt: ""),
        Agent(id: "sample-5", name: "reviewer", runtime: "claude-code", tmuxSession: "reviewer", workspace: nil, mode: .spawned, status: .working, createdAt: ""),
    ]
}
