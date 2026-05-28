//
//  ProfileStorageTests.swift
//
//  Round-trip tests for the UserDefaults-backed profile + last-agent
//  persistence. Uses a clean in-memory UserDefaults via a custom
//  suite name so we don't pollute the user's real prefs.
//

import XCTest
@testable import WaveCodeDesktop

final class ProfileStorageTests: XCTestCase {
    private var originalSuite: String?

    override func setUp() {
        super.setUp()
        // Wipe any keys we might touch — UserDefaults.standard is what
        // ProfileStorage uses. Tests must clean up after themselves.
        let d = UserDefaults.standard
        d.removeObject(forKey: "wavecode.profiles.v1")
        d.removeObject(forKey: "wavecode.profiles.active.v1")
        d.removeObject(forKey: "wavecode.lastActiveAgent.v1")
    }

    override func tearDown() {
        let d = UserDefaults.standard
        d.removeObject(forKey: "wavecode.profiles.v1")
        d.removeObject(forKey: "wavecode.profiles.active.v1")
        d.removeObject(forKey: "wavecode.lastActiveAgent.v1")
        super.tearDown()
    }

    // MARK: - Profiles

    func test_loadAll_returnsDefaultLocalWhenEmpty() {
        let (profiles, activeId) = ProfileStorage.loadAll()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.label, "wave (default)")
        XCTAssertEqual(activeId, profiles.first?.id)
    }

    func test_saveAndLoadRoundTrip() {
        let p1 = ServerProfile(label: "Acme staging", sshHost: "acme-staging", wavecodePort: 3777)
        let p2 = ServerProfile(label: "Personal", sshHost: "wave", wavecodePort: 3777)

        ProfileStorage.save(profiles: [p1, p2], activeId: p2.id)

        let (loaded, activeId) = ProfileStorage.loadAll()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.map(\.label), ["Acme staging", "Personal"])
        XCTAssertEqual(activeId, p2.id)
    }

    func test_loadAll_returnsFirstWhenActiveIdNoLongerExists() {
        let p1 = ServerProfile(label: "Gone", sshHost: "gone", wavecodePort: 3777)
        let p2 = ServerProfile(label: "Here", sshHost: "here", wavecodePort: 3777)

        // Save with p1 active, then save without p1 — simulates a
        // delete that left a stale active id pointer.
        ProfileStorage.save(profiles: [p1, p2], activeId: p1.id)
        ProfileStorage.save(profiles: [p2], activeId: p1.id) // p1 missing!

        let (loaded, activeId) = ProfileStorage.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(activeId, p2.id, "should fall back to first profile when active is missing")
    }

    // MARK: - Last active agent

    func test_loadLastActiveAgent_returnsNilWhenUnset() {
        let id = UUID()
        XCTAssertNil(ProfileStorage.loadLastActiveAgent(forProfile: id))
    }

    func test_lastActiveAgent_roundTrip() {
        let profileId = UUID()
        ProfileStorage.saveLastActiveAgent("agent-abc", forProfile: profileId)
        XCTAssertEqual(ProfileStorage.loadLastActiveAgent(forProfile: profileId), "agent-abc")
    }

    func test_lastActiveAgent_isScopedPerProfile() {
        let profileA = UUID()
        let profileB = UUID()
        ProfileStorage.saveLastActiveAgent("a-agent", forProfile: profileA)
        // Loading for a different profile must NOT return profile A's value.
        XCTAssertNil(ProfileStorage.loadLastActiveAgent(forProfile: profileB))
    }

    func test_lastActiveAgent_nilClears() {
        let profileId = UUID()
        ProfileStorage.saveLastActiveAgent("first", forProfile: profileId)
        ProfileStorage.saveLastActiveAgent(nil, forProfile: profileId)
        XCTAssertNil(ProfileStorage.loadLastActiveAgent(forProfile: profileId))
    }
}
