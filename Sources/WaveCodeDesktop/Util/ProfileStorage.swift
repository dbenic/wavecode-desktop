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
