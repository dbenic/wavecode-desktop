//
//  PTYHandler.swift
//
//  ChannelDuplexHandler that runs inside an NIOSSH child channel and:
//    1. On activation, requests a PTY with the given size + terminal
//       modes, then requests a shell (or exec if a command is provided).
//    2. Forwards inbound channel data to the `onBytes` callback so the
//       UI (SwiftTerm) can render it.
//    3. Accepts outbound writes from the high-level PTYSession.send and
//       wraps them as SSHChannelData.
//    4. Surfaces exit status via `onExit`.
//

import Foundation
import NIOCore
import NIOSSH

/// Callback fired on each inbound chunk. Always called on the channel's
/// event loop — bridge to main yourself if you're touching UI.
typealias PTYByteSink = @Sendable (ByteBuffer) -> Void

/// Called once when the remote process exits.
typealias PTYExitSink = @Sendable (Int32?) -> Void

final class PTYHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = SSHChannelData // not used externally
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let initialCols: Int
    private let initialRows: Int
    private let term: String
    private let command: String?
    private let onBytes: PTYByteSink
    private let onExit: PTYExitSink

    private var ptyReady = false
    private var exitDelivered = false

    init(
        initialCols: Int,
        initialRows: Int,
        term: String = "xterm-256color",
        command: String? = nil,
        onBytes: @escaping PTYByteSink,
        onExit: @escaping PTYExitSink
    ) {
        self.initialCols = initialCols
        self.initialRows = initialRows
        self.term = term
        self.command = command
        self.onBytes = onBytes
        self.onExit = onExit
    }

    func handlerAdded(context: ChannelHandlerContext) {
        // Allow half-closure so EOF from remote doesn't tear the channel
        // before we've drained inbound.
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            .whenFailure { context.fireErrorCaught($0) }
    }

    func channelActive(context: ChannelHandlerContext) {
        // 1. Request a PTY with the size + terminal modes we want.
        //    OPOST + ONLCR map LF→CRLF on output the way an interactive
        //    terminal expects. ECHO is off because tmux/shell handles
        //    its own echo.
        let ptyReq = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: term,
            terminalCharacterWidth: initialCols,
            terminalRowHeight: initialRows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([
                .ECHO: 0,
                .ICANON: 0,
                .ISIG: 1,
                .IEXTEN: 1,
                .OPOST: 1,
                .ONLCR: 1,
            ])
        )

        context.triggerUserOutboundEvent(ptyReq).flatMap { _ -> EventLoopFuture<Void> in
            // 2. Now request either shell or exec depending on command.
            if let cmd = self.command {
                let req = SSHChannelRequestEvent.ExecRequest(command: cmd, wantReply: true)
                return context.triggerUserOutboundEvent(req)
            } else {
                let req = SSHChannelRequestEvent.ShellRequest(wantReply: true)
                return context.triggerUserOutboundEvent(req)
            }
        }.whenComplete { result in
            switch result {
            case .success:
                self.ptyReady = true
            case .failure(let error):
                context.fireErrorCaught(error)
                context.close(promise: nil)
            }
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let chunk = self.unwrapInboundIn(data)
        guard case .byteBuffer(let buf) = chunk.data else {
            // Other variants exist (fileRegion); we don't expect them
            // from an interactive shell. Drop.
            return
        }
        switch chunk.type {
        case .channel, .stdErr:
            // tmux multiplexes stderr into the same visual stream; tmux
            // running over SSH typically uses only .channel anyway.
            onBytes(buf)
        default:
            break
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buf = self.unwrapOutboundIn(data)
        let wrapped = SSHChannelData(type: .channel, data: .byteBuffer(buf))
        context.writeAndFlush(self.wrapOutboundOut(wrapped), promise: promise)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let exit = event as? SSHChannelRequestEvent.ExitStatus {
            deliverExit(Int32(exit.exitStatus))
        } else if event is SSHChannelRequestEvent.ExitSignal {
            deliverExit(nil)
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        deliverExit(nil)
        context.fireChannelInactive()
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        deliverExit(nil)
    }

    private func deliverExit(_ status: Int32?) {
        guard !exitDelivered else { return }
        exitDelivered = true
        onExit(status)
    }
}
