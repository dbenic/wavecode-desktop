//
//  ProfileStorage.swift
//
//  Persist the list of server profiles + the active selection in
//  UserDefaults. JSON-encoded so adding fields later doesn't break
//  existing installs (any decoding error → fall back to defaults).
//
//  Bearer tokens are NOT stored here — those go in macOS Keychain
//  (future, week 5). This is for non-sensitive connection metadata only.
//

import Foundation
import OSLog

enum ProfileStorage {
    private static let log = Logger(subsystem: "com.wavenetic.wavecode-desktop", category: "profiles")
    private static let profilesKey = "wavecode.profiles.v1"
    private static let activeKey = "wavecode.profiles.active.v1"
    private static let lastAgentKey = "wavecode.lastActiveAgent.v1"

    /// The agent id last shown in the workspace, scoped per server
    /// profile. Stored as `<profileId>::<agentId>` so switching servers
    /// doesn't surface a dead agent. Returns nil if no record exists for
    /// this profile or if the stored format is unrecognised.
    static func loadLastActiveAgent(forProfile profileId: UUID) -> String? {
        guard let raw = UserDefaults.standard.string(forKey: lastAgentKey) else { return nil }
        let parts = raw.split(separator: "::", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0] == profileId.uuidString,
              !parts[1].isEmpty else {
            return nil
        }
        return String(parts[1])
    }

    static func saveLastActiveAgent(_ agentId: String?, forProfile profileId: UUID) {
        let key = lastAgentKey
        if let agentId, !agentId.isEmpty {
            UserDefaults.standard.set("\(profileId.uuidString)::\(agentId)", forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func loadAll() -> (profiles: [ServerProfile], activeId: UUID?) {
        let defaults = UserDefaults.standard

        let profiles: [ServerProfile]
        if let data = defaults.data(forKey: profilesKey) {
            do {
                profiles = try JSONDecoder().decode([ServerProfile].self, from: data)
            } catch {
                log.warning("profiles: decode failed (\(error.localizedDescription, privacy: .public)); falling back to default")
                profiles = [.defaultLocal]
            }
        } else {
            profiles = [.defaultLocal]
        }

        let activeId: UUID?
        if let raw = defaults.string(forKey: activeKey), let uuid = UUID(uuidString: raw) {
            activeId = profiles.contains(where: { $0.id == uuid }) ? uuid : profiles.first?.id
        } else {
            activeId = profiles.first?.id
        }

        return (profiles, activeId)
    }

    static func save(profiles: [ServerProfile], activeId: UUID?) {
        let defaults = UserDefaults.standard
        do {
            let data = try JSONEncoder().encode(profiles)
            defaults.set(data, forKey: profilesKey)
            if let activeId {
                defaults.set(activeId.uuidString, forKey: activeKey)
            } else {
                defaults.removeObject(forKey: activeKey)
            }
        } catch {
            log.error("profiles: save failed (\(error.localizedDescription, privacy: .public))")
        }
    }
}
