//
//  Agent.swift
//
//  Hand-translated from the WaveCode core API. Source of truth is
//  `wavecode/docs/api.md`. When the server adds fields, update here.
//  Future: replace with generated types from an OpenAPI schema.
//

import Foundation

enum AgentStatus: String, Codable, Sendable {
    case idle
    case working
    case error
}

enum AgentMode: String, Codable, Sendable {
    case adopted
    case spawned
}

struct Agent: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let name: String
    let runtime: String
    let tmuxSession: String
    let workspace: String?
    let mode: AgentMode
    let status: AgentStatus
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, runtime
        case tmuxSession = "tmux_session"
        case workspace, mode, status
        case createdAt = "created_at"
    }
}
