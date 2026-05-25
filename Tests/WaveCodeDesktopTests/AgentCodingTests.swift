//
//  AgentCodingTests.swift
//
//  Round-trip test for the Agent JSON shape. Catches drift between the
//  WaveCode API and our hand-translated types — when the server adds or
//  renames a field, this fails and we know to update.
//

import XCTest
@testable import WaveCodeDesktop

final class AgentCodingTests: XCTestCase {
    func test_decodesAgentFromServerJson() throws {
        let json = #"""
        {
          "id": "01KREZA3Q3TYBEM8GCKQN45RHG",
          "name": "cl-wavebid",
          "runtime": "claude-code",
          "tmux_session": "cl-wavebid",
          "workspace": null,
          "mode": "adopted",
          "status": "idle",
          "created_at": "2026-05-12 20:50:59"
        }
        """#

        let decoder = JSONDecoder()
        let agent = try decoder.decode(Agent.self, from: Data(json.utf8))

        XCTAssertEqual(agent.id, "01KREZA3Q3TYBEM8GCKQN45RHG")
        XCTAssertEqual(agent.name, "cl-wavebid")
        XCTAssertEqual(agent.tmuxSession, "cl-wavebid")
        XCTAssertEqual(agent.mode, .adopted)
        XCTAssertEqual(agent.status, .idle)
        XCTAssertNil(agent.workspace)
    }

    func test_decodesWorkingSpawnedAgent() throws {
        let json = #"""
        { "id": "x", "name": "y", "runtime": "claude-code",
          "tmux_session": "wc-y", "workspace": "/path/to/repo",
          "mode": "spawned", "status": "working", "created_at": "" }
        """#

        let agent = try JSONDecoder().decode(Agent.self, from: Data(json.utf8))

        XCTAssertEqual(agent.mode, .spawned)
        XCTAssertEqual(agent.status, .working)
        XCTAssertEqual(agent.workspace, "/path/to/repo")
    }
}
