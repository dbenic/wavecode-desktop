//
//  TerminalSession.swift
//
//  Manages one open SSH PTY for an agent terminal view. The session:
//    1. Opens a TTY channel on the active SSH connection
//    2. Runs `tmux attach -t <session>` inside it
//    3. Streams remote stdout/stderr bytes to a callback (which feeds
//       SwiftTerm's TerminalView)
//    4. Accepts keystrokes from the terminal view and writes them back
//       to the remote PTY
//
//  Bidirectional I/O is achieved by running `withTTY` in a child Task
//  and using an AsyncStream as the queue for outgoing keystrokes —
//  the closure body drains the stream into the SSH writer.
//

import Foundation
import Citadel
import NIOCore

/// Sink for bytes arriving from the remote PTY. Called on a background
/// task; the caller (TerminalCoordinator) hops to main before touching
/// SwiftTerm.
typealias TerminalByteSink = @Sendable (ArraySlice<UInt8>) -> Void

final class TerminalSession: @unchecked Sendable {
    private let client: SSHClient
    private let command: String
    private let onBytes: TerminalByteSink
    private let onClosed: @Sendable (Error?) -> Void

    private var runTask: Task<Void, Never>?
    private let outboundContinuation: AsyncStream<[UInt8]>.Continuation
    private let outboundStream: AsyncStream<[UInt8]>

    init(
        client: SSHClient,
        command: String,
        onBytes: @escaping TerminalByteSink,
        onClosed: @escaping @Sendable (Error?) -> Void = { _ in }
    ) {
        self.client = client
        self.command = command
        self.onBytes = onBytes
        self.onClosed = onClosed

        var continuation: AsyncStream<[UInt8]>.Continuation!
        self.outboundStream = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.outboundContinuation = continuation
    }

    /// Start streaming. Spawns the long-lived Task that owns the TTY.
    func start() {
        let command = self.command
        let onBytes = self.onBytes
        let onClosed = self.onClosed
        let outbound = self.outboundStream
        let client = self.client

        runTask = Task.detached(priority: .userInitiated) {
            var captured: Error?
            do {
                try await client.withTTY { inbound, writer in
                    // Concurrent writer: drains keystroke queue → SSH PTY.
                    let writerTask = Task {
                        for await bytes in outbound {
                            var buffer = ByteBuffer()
                            buffer.writeBytes(bytes)
                            try? await writer.write(buffer)
                        }
                    }

                    // Send the command first; it will own the PTY's foreground.
                    var startBuf = ByteBuffer()
                    startBuf.writeString(command + "\n")
                    try await writer.write(startBuf)

                    // Main read loop: remote → SwiftTerm.
                    for try await output in inbound {
                        switch output {
                        case .stdout(let buf), .stderr(let buf):
                            let slice = ArraySlice(buf.readableBytesView)
                            onBytes(slice)
                        }
                    }

                    writerTask.cancel()
                }
            } catch {
                captured = error
            }
            onClosed(captured)
        }
    }

    /// Forward keystrokes from the terminal view to the remote PTY.
    /// Safe to call from any thread.
    func send(_ bytes: ArraySlice<UInt8>) {
        outboundContinuation.yield(Array(bytes))
    }

    /// Tear down the session. After this, `send` is a no-op and the
    /// `runTask` exits (when withTTY's closure returns or is cancelled).
    func close() {
        outboundContinuation.finish()
        runTask?.cancel()
        runTask = nil
    }

    deinit {
        outboundContinuation.finish()
        runTask?.cancel()
    }
}
