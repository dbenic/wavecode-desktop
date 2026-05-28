//
//  AppState.swift
//
//  Top-level observable state holder. Server state (agents, tasks,
//  artifacts) is NEVER cached here — it lives on the server and arrives
//  via SSE. This holds only UI-local state.
//
//  Profile management:
//    - `profiles` holds the full list (persisted to UserDefaults)
//    - `activeProfileId` points at the currently-selected one
//    - `activeProfile` is the computed accessor used everywhere else
//

import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    // MARK: - Server profiles
    private(set) var profiles: [ServerProfile]
    private(set) var activeProfileId: UUID?

    var activeProfile: ServerProfile {
        if let id = activeProfileId, let p = profiles.first(where: { $0.id == id }) {
            return p
        }
        return profiles.first ?? .defaultLocal
    }

    // MARK: - Connection
    var connectionStatus: ConnectionStatus = .disconnected
    var connectionError: String? = nil

    // MARK: - UI state
    var activeAgentId: String? = nil {
        didSet {
            // Visiting an agent marks it as "alive in the UI" so the
            // workspace keeps its TerminalView (and SSH channel + tmux
            // session) around for instant re-switch. Set never shrinks
            // automatically — only on full disconnect / app quit — so
            // we don't churn SSH channels.
            if let id = activeAgentId {
                visitedAgentIds.insert(id)
            }
        }
    }
    var paletteOpen: Bool = false
    var sidebarCollapsed: Bool = false

    /// Agents the user has attached to at least once this session.
    /// The workspace pane keeps a TerminalView alive for each so
    /// switching back is instant (no SSH re-attach, no tmux re-connect).
    private(set) var visitedAgentIds: Set<String> = []

    /// Visited agents in current `agents` order. Lazily computed.
    var visitedAgents: [Agent] {
        agents.filter { visitedAgentIds.contains($0.id) }
    }

    /// Clear visited set when we change SSH connection target — old
    /// agents are unreachable on the new server. Called from the
    /// connection lifecycle, not the UI.
    func clearVisited() {
        visitedAgentIds.removeAll()
        activeAgentId = nil
    }

    /// Set by the open TerminalCoordinator so the App's ⌘V command can
    /// reach the active session. Weak so swapping agents doesn't leak.
    weak var activeTerminalCoordinator: TerminalCoordinator? = nil

    // MARK: - Cached server views (driven by SSE; not authoritative)
    var agents: [Agent] = []

    // MARK: - Terminal display prefs
    let terminalPrefs = TerminalPrefs()

    init() {
        let (loaded, active) = ProfileStorage.loadAll()
        self.profiles = loaded
        self.activeProfileId = active ?? loaded.first?.id
    }

    func agent(byId id: String) -> Agent? {
        agents.first { $0.id == id }
    }

    // MARK: - Profile mutations (persist on every change)

    func addProfile(_ profile: ServerProfile) {
        profiles.append(profile)
        if activeProfileId == nil { activeProfileId = profile.id }
        persist()
    }

    func updateProfile(_ profile: ServerProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        persist()
    }

    func removeProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
            activeProfileId = profiles.first?.id
        }
        persist()
    }

    func setActive(id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
        persist()
    }

    private func persist() {
        ProfileStorage.save(profiles: profiles, activeId: activeProfileId)
    }
}
