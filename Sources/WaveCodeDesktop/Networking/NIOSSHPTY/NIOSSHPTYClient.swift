//
//  NIOSSHPTYClient.swift
//
//  Direct-NIOSSH SSH client used only for PTY (interactive shell)
//  channels. Citadel still handles the higher-level conveniences
//  (executeCommand for the WaveCode API fetch); this is purely for
//  the terminal channels where we need:
//    - A real PTY with the proper terminal modes
//    - Server-side window_change SSH messages on resize
//    - No `script` wrapper, no `stty` injection
//
//  The class manages a single ClientBootstrap connection per server;
//  each terminal view opens its own child channel through that
//  connection.
//

import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import Crypto
import OSLog

@MainActor
final class NIOSSHPTYClient {
    private let log = Logger(subsystem: "com.wavenetic.wavecode-desktop", category: "niossh")

    nonisolated(unsafe) private var group: MultiThreadedEventLoopGroup?
    nonisolated(unsafe) private var connection: Channel?

    var isConnected: Bool { connection != nil }

    // MARK: - Connect / disconnect

    func connect(
        host: String,
        port: Int,
        username: String,
        ed25519Key: Curve25519.Signing.PrivateKey
    ) async throws {
        log.info("niossh: connecting \(username, privacy: .public)@\(host, privacy: .public):\(port, privacy: .public)")

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let auth = WavePubkeyAuthDelegate(username: username, ed25519Key: ed25519Key)
        let hostKey = TOFUHostKeyDelegate()

        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                let sshHandler = NIOSSHHandler(
                    role: .client(.init(
                        userAuthDelegate: auth,
                        serverAuthDelegate: hostKey
                    )),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: nil
                )
                return channel.pipeline.addHandlers([sshHandler])
            }
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .connectTimeout(.seconds(15))

        do {
            let channel = try await bootstrap.connect(host: host, port: port).get()
            self.group = group
            self.connection = channel
            log.info("niossh: connected")
        } catch {
            try? await group.shutdownGracefully()
            log.error("niossh: connect failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func disconnect() async {
        if let channel = connection {
            try? await channel.close().get()
        }
        connection = nil
        if let group = group {
            try? await group.shutdownGracefully()
        }
        group = nil
        log.info("niossh: disconnected")
    }

    // MARK: - Open PTY

    /// Open a child session channel, request a PTY with the given size,
    /// then request a shell (or exec the given command). Returns a
    /// `PTYSession` for sending input, resizing, and reading output.
    func openShellPTY(
        cols: Int,
        rows: Int,
        term: String = "xterm-256color",
        command: String? = nil
    ) async throws -> PTYSession {
        guard let connection = connection else {
            throw PTYError.notConnected
        }

        let (stream, continuation) = AsyncStream<ByteBuffer>.makeStream()
        let exitPromise = connection.eventLoop.makePromise(of: Int32?.self)

        let handler = PTYHandler(
            initialCols: cols,
            initialRows: rows,
            term: term,
            command: command,
            onBytes: { buf in continuation.yield(buf) },
            onExit: { status in
                continuation.finish()
                exitPromise.succeed(status)
            }
        )

        let sshHandler = try await connection.pipeline.handler(type: NIOSSHHandler.self).get()
        let childPromise = connection.eventLoop.makePromise(of: Channel.self)

        // createChannel mutates NIOSSHHandler state that's only safe to
        // touch from the parent channel's event loop. Dispatch onto it.
        let eventLoop = connection.eventLoop
        eventLoop.execute {
            sshHandler.createChannel(childPromise, channelType: .session) { childChannel, channelType in
                guard channelType == .session else {
                    return childChannel.eventLoop.makeFailedFuture(PTYError.wrongChannelType)
                }
                return childChannel.pipeline.addHandler(handler)
            }
        }
        let childChannel = try await childPromise.futureResult.get()

        return PTYSession(
            channel: childChannel,
            inbound: stream,
            exit: exitPromise.futureResult
        )
    }
}

// MARK: - PTYSession (the per-terminal handle)

/// One live PTY session. Holds the NIO child channel and exposes
/// Swift-concurrency-friendly send / resize / close + an inbound
/// byte stream.
final class PTYSession: @unchecked Sendable {
    let inbound: AsyncStream<ByteBuffer>
    private let channel: Channel
    private let exitFuture: EventLoopFuture<Int32?>

    init(
        channel: Channel,
        inbound: AsyncStream<ByteBuffer>,
        exit: EventLoopFuture<Int32?>
    ) {
        self.channel = channel
        self.inbound = inbound
        self.exitFuture = exit
    }

    /// Send bytes to the remote PTY's stdin.
    /// `Channel.writeAndFlush` is thread-safe — NIO dispatches internally.
    func send(_ bytes: ArraySlice<UInt8>) async {
        var buf = channel.allocator.buffer(capacity: bytes.count)
        buf.writeBytes(bytes)
        try? await channel.writeAndFlush(buf).get()
    }

    /// Send an SSH `window_change` message — the kernel-level resize
    /// signal that `stty cols/rows` was always a hack around.
    /// `triggerUserOutboundEvent` requires the channel's event loop.
    func resize(cols: Int, rows: Int) async {
        let evt = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0
        )
        let promise = channel.eventLoop.makePromise(of: Void.self)
        let chan = channel
        channel.eventLoop.execute {
            chan.triggerUserOutboundEvent(evt).cascade(to: promise)
        }
        try? await promise.futureResult.get()
    }

    /// `Channel.close` is also thread-safe.
    func close() async {
        try? await channel.close().get()
    }

    /// Awaits the remote process's exit status (nil if it ended without
    /// reporting one — most commonly a clean shell exit or a session
    /// torn down by the server).
    func awaitExit() async -> Int32? {
        (try? await exitFuture.get()) ?? nil
    }
}

// MARK: - Errors

enum PTYError: LocalizedError {
    case notConnected
    case wrongChannelType

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected"
        case .wrongChannelType: return "SSH server returned an unexpected channel type"
        }
    }
}
