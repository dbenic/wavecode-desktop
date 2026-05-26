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
    var activeAgentId: String? = nil
    var paletteOpen: Bool = false
    var sidebarCollapsed: Bool = false

    // MARK: - Cached server views (driven by SSE; not authoritative)
    var agents: [Agent] = []

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
