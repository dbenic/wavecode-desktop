//
//  WaveCodeAPI.swift
//
//  v0 strategy: shortcut the WaveCode HTTP API by exec'ing `curl` on
//  the server over our existing SSH connection. The server's daemon
//  listens on `localhost:3777` and accepts unauthenticated requests
//  from the same host, so this avoids needing port-forwarding for
//  basic reads.
//
//  Week 2 will swap this for a real SSH port-forward + URLSession
//  fetch — same JSON contract, just a more efficient transport. The
//  Agent decoding code stays identical.
//

import Foundation
import Citadel
import NIOCore
import OSLog

@MainActor
final class WaveCodeAPI {
    private let log = Logger(subsystem: "com.wavenetic.wavecode-desktop", category: "api")

    /// Fetch the full agent list from the WaveCode daemon on the
    /// connected server. Runs `curl -sS --fail http://localhost:<port>/api/agents`
    /// via SSH exec and decodes the result.
    func fetchAgents(via client: SSHClient, wavecodePort: Int) async throws -> [Agent] {
        let cmd = "curl -sS --fail http://localhost:\(wavecodePort)/api/agents"
        log.info("api: \(cmd, privacy: .public)")

        let buffer: ByteBuffer = try await client.executeCommand(
            cmd,
            maxResponseSize: 4 * 1024 * 1024, // 4 MB cap — way more than any agent list
            mergeStreams: false
        )

        let data = Data(buffer.readableBytesView)
        if data.isEmpty {
            throw APIError.emptyResponse
        }

        do {
            return try JSONDecoder().decode([Agent].self, from: data)
        } catch {
            // Most likely cause: server returned an error page (HTML or
            // plain text from auth middleware) rather than JSON. Surface
            // the first 200 chars so the user can diagnose.
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
            throw APIError.decodeFailed(preview: preview, underlying: error)
        }
    }
}

enum APIError: LocalizedError {
    case emptyResponse
    case decodeFailed(preview: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "WaveCode API returned an empty response. Is the daemon running on the server?"
        case .decodeFailed(let preview, let underlying):
            return """
            Could not parse the WaveCode API response.
              \(underlying.localizedDescription)

            Server returned (first 200 chars):
              \(preview)
            """
        }
    }
}
