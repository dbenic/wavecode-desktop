//
//  InvestigatePTYClose — standalone probe to find which PTY close
//  pattern kills tmux sessions and which preserves them.
//
//  Self-contained (doesn't depend on WaveCodeDesktop's internals)
//  so it can run as an executable target alongside the app.
//
//  USAGE:
//    1) Create the canary session (once):
//         ssh wave 'tmux has-session -t wctest-canary 2>/dev/null \
//                    || tmux new-session -d -s wctest-canary "sleep 3600"'
//    2) Run the probes:
//         swift run InvestigatePTYClose <host> <user> [test]
//       tests:
//         bare_close       — channel.close() with no prelude
//         ctrlbd_close     — Ctrl-b d, 250ms, channel.close()
//         just_ctrlbd      — Ctrl-b d, wait for natural exit
//         all              — run each in sequence
//
//  After each test the probe re-checks `tmux has-session -t
//  wctest-canary` and prints SURVIVED / KILLED.
//

import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import Crypto
@preconcurrency import Citadel

@main
struct InvestigatePTYClose {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            print("usage: InvestigatePTYClose <host> <user> [test]")
            exit(2)
        }
        let host = args[1]
        let user = args[2]
        let testName = args.count >= 4 ? args[3] : "all"

        guard let key = loadEd25519Key() else {
            print("FATAL: no ~/.ssh/id_ed25519 found")
            exit(1)
        }

        let tests: [String] = testName == "all"
            ? ["bare_close", "ctrlbd_close", "just_ctrlbd"]
            : [testName]

        for t in tests {
            print("\n────── \(t) ──────")
            ensureCanaryExists(host: host)
            let before = canaryExists(host: host)
            print("canary present before: \(before)")
            await runTest(t, host: host, user: user, key: key)
            // tmux server takes a beat to update
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let after = canaryExists(host: host)
            print("canary present after:  \(after)")
            print(after ? "✅ SURVIVED \(t)" : "❌ KILLED by \(t)")
        }
        exit(0)
    }

    // MARK: - Key loading

    static func loadEd25519Key() -> Curve25519.Signing.PrivateKey? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".ssh/id_ed25519")
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Use Citadel's well-tested OpenSSH parser instead of rolling our own.
        return try? Curve25519.Signing.PrivateKey(sshEd25519: data)
    }

    // MARK: - Canary checks (via /usr/bin/ssh, out-of-band from our test)

    static func ensureCanaryExists(host: String) {
        runRemote(
            host: host,
            command: "tmux has-session -t wctest-canary 2>/dev/null || tmux new-session -d -s wctest-canary 'sleep 3600'"
        )
    }

    @discardableResult
    static func canaryExists(host: String) -> Bool {
        let out = runRemote(host: host, command: "tmux has-session -t wctest-canary 2>/dev/null && echo PRESENT || echo MISSING")
        return out.contains("PRESENT")
    }

    @discardableResult
    static func runRemote(host: String, command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-o", "BatchMode=yes", host, command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - SSH connect + PTY

    static func runTest(_ name: String, host: String, user: String, key: Curve25519.Signing.PrivateKey) async {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                let handler = NIOSSHHandler(
                    role: .client(.init(
                        userAuthDelegate: PubkeyAuth(username: user, key: key),
                        serverAuthDelegate: AcceptAllHostKeys()
                    )),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: nil
                )
                return channel.pipeline.addHandler(handler)
            }
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)

        let connection: Channel
        do {
            connection = try await bootstrap.connect(host: host, port: 22).get()
        } catch {
            print("  FATAL: connect failed: \(error)")
            return
        }
        defer { try? connection.close().wait() }

        // Open child channel with PTY + exec
        let sshHandler: NIOSSHHandler
        do {
            sshHandler = try await connection.pipeline.handler(type: NIOSSHHandler.self).get()
        } catch {
            print("  FATAL: no SSH handler: \(error)")
            return
        }

        let childPromise = connection.eventLoop.makePromise(of: Channel.self)
        connection.eventLoop.execute {
            sshHandler.createChannel(childPromise, channelType: .session) { childChannel, channelType in
                guard channelType == .session else {
                    return childChannel.eventLoop.makeFailedFuture(ProbeError.wrongChannelType)
                }
                return childChannel.pipeline.addHandler(PTYProbeHandler())
            }
        }

        let childChannel: Channel
        do {
            childChannel = try await childPromise.futureResult.get()
        } catch {
            print("  FATAL: child channel open: \(error)")
            return
        }

        // Let exec settle + tmux render
        try? await Task.sleep(nanoseconds: 700_000_000)

        switch name {
        case "bare_close":
            print("  pattern: channel.close() with no prelude")
            try? await childChannel.close().get()

        case "ctrlbd_close":
            print("  pattern: Ctrl-b d, 250ms, channel.close()")
            await sendBytes(channel: childChannel, bytes: [0x02, 0x64])
            try? await Task.sleep(nanoseconds: 250_000_000)
            try? await childChannel.close().get()

        case "just_ctrlbd":
            print("  pattern: just Ctrl-b d, wait for natural exit")
            await sendBytes(channel: childChannel, bytes: [0x02, 0x64])
            // Wait for the channel to close itself as tmux exits
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            // Channel should already be inactive; explicit close is no-op
            _ = try? await childChannel.closeFuture.get()

        default:
            print("  unknown test: \(name)")
        }
    }

    static func sendBytes(channel: Channel, bytes: [UInt8]) async {
        var buf = channel.allocator.buffer(capacity: bytes.count)
        buf.writeBytes(bytes)
        try? await channel.writeAndFlush(buf).get()
    }
}

enum ProbeError: Error {
    case wrongChannelType
}

// MARK: - NIO handlers

final class PubkeyAuth: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let key: Curve25519.Signing.PrivateKey
    private var offered = false

    init(username: String, key: Curve25519.Signing.PrivateKey) {
        self.username = username
        self.key = key
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard !offered, availableMethods.contains(.publicKey) else {
            nextChallengePromise.succeed(nil)
            return
        }
        offered = true
        let nioKey = NIOSSHPrivateKey(ed25519Key: key)
        let offer = NIOSSHUserAuthenticationOffer(
            username: username,
            serviceName: "",
            offer: .privateKey(.init(privateKey: nioKey))
        )
        nextChallengePromise.succeed(offer)
    }
}

final class AcceptAllHostKeys: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        validationCompletePromise.succeed(())
    }
}

/// Mirror of WaveCodeDesktop's PTYHandler but stripped to the bone for
/// the probe. Same PTY allocation + exec command pattern.
final class PTYProbeHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            .whenFailure { context.fireErrorCaught($0) }
    }

    func channelActive(context: ChannelHandlerContext) {
        let pty = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: 120,
            terminalRowHeight: 40,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([
                .ECHO: 0, .ICANON: 0, .ISIG: 1, .IEXTEN: 1,
                .OPOST: 1, .ONLCR: 1,
            ])
        )
        context.triggerUserOutboundEvent(pty).flatMap { _ -> EventLoopFuture<Void> in
            let exec = SSHChannelRequestEvent.ExecRequest(
                command: "tmux attach -t wctest-canary",
                wantReply: true
            )
            return context.triggerUserOutboundEvent(exec)
        }.whenFailure { _ in
            context.close(promise: nil)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // Drain, don't print — keep probe output clean
        _ = self.unwrapInboundIn(data)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buf = self.unwrapOutboundIn(data)
        context.writeAndFlush(self.wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buf))), promise: promise)
    }
}
