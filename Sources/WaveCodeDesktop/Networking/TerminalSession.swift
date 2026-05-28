//
//  TerminalSession.swift
//
//  Higher-level wrapper around a PTYSession. Provides the same
//  Swift-friendly callback API the rest of the app already uses
//  (onBytes, onClosed), built on the NIOSSH-direct PTY layer.
//
//  The previous version of this file wrapped Citadel.withTTY and had
//  to ride on top of the `script` workaround for tmux. This rewrite
//  drops both: tmux can attach directly because the PTY now has
//  proper controlling-terminal semantics + a real configurable size.
//

import Foundation
import NIOCore

/// Sink for bytes arriving from the remote PTY. Called from a Tokio-
/// equivalent task; the caller hops to main before touching SwiftTerm.
typealias TerminalByteSink = @Sendable (ArraySlice<UInt8>) -> Void

final class TerminalSession: @unchecked Sendable {
    private let ptySession: PTYSession
    private let onBytes: TerminalByteSink
    private let onClosed: @Sendable (Error?) -> Void
    private var pumpTask: Task<Void, Never>?

    init(
        ptySession: PTYSession,
        onBytes: @escaping TerminalByteSink,
        onClosed: @escaping @Sendable (Error?) -> Void = { _ in }
    ) {
        self.ptySession = ptySession
        self.onBytes = onBytes
        self.onClosed = onClosed
    }

    /// Begin pumping inbound bytes → onBytes callback. Spawns one
    /// long-lived Task that lives until the SSH channel closes or
    /// `close()` is invoked.
    func start() {
        let stream = ptySession.inbound
        let bytesCallback = onBytes
        let closedCallback = onClosed
        let pty = ptySession

        pumpTask = Task.detached(priority: .userInitiated) {
            for await chunk in stream {
                let slice = ArraySlice(chunk.readableBytesView)
                bytesCallback(slice)
            }
            // Stream finished — either the remote closed cleanly or
            // we cancelled. Report exit status if any.
            let exit = await pty.awaitExit()
            if let exit, exit != 0 {
                closedCallback(NSError(domain: "PTY", code: Int(exit),
                                       userInfo: [NSLocalizedDescriptionKey: "exit \(exit)"]))
            } else {
                closedCallback(nil)
            }
        }
    }

    func send(_ bytes: ArraySlice<UInt8>) {
        let pty = ptySession
        Task { await pty.send(bytes) }
    }

    func resize(cols: Int, rows: Int) {
        let pty = ptySession
        Task { await pty.resize(cols: cols, rows: rows) }
    }

    func close() {
        pumpTask?.cancel()
        pumpTask = nil
        let pty = ptySession
        Task { await pty.close() }
    }

    deinit {
        pumpTask?.cancel()
    }
}
