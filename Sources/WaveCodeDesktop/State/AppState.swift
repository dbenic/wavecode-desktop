//
//  AppState.swift
//
//  Top-level observable state holder. Server state (agents, tasks,
//  artifacts) is NEVER cached here — it lives on the server and arrives
//  via SSE. This holds only UI-local state: which agent is active,
//  whether the palette is open, what the connection profile is.
//

import Foundation
import Observation

@Observable
final class AppState {
    // MARK: - Server connection
    var profile: ServerProfile = .defaultLocal
    var connectionStatus: ConnectionStatus = .disconnected
    var connectionError: String? = nil

    // MARK: - UI state
    var activeAgentId: String? = nil
    var paletteOpen: Bool = false
    var sidebarCollapsed: Bool = false

    // MARK: - Cached server views (driven by SSE; not authoritative)
    var agents: [Agent] = []

    func agent(byId id: String) -> Agent? {
        agents.first { $0.id == id }
    }
}
