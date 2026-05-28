//
//  ReconnectSupervisor.swift
//
//  Glues macOS sleep/wake notifications and connection-death detection
//  to the ConnectionManager so we transparently reconnect after the
//  user's laptop wakes / network resumes. The server side is untouched
//  — tmux sessions stay alive throughout per the no-kill invariant
//  (see CLAUDE.md §2a) — so reconnect just re-establishes the SSH
//  transport.
//
//  Lifecycle:
//    - On `start(appState:)` we register for NSWorkspace willSleep /
//      didWake notifications and start observing connectionStatus.
//    - On didWake (or any explicit "kick"), if status is not
//      `.connected`, we begin a reconnect cycle with exponential
//      backoff.
//    - On willSleep we mark status as `.reconnecting` so the UI shows
//      the pending state before sleep actually fires.
//
//  We deliberately do NOT race the system's own connection death
//  detection — TCP keepalive on the SSH socket (set in
//  NIOSSHPTYClient) will trip eventually anyway. didWake just lets us
//  reconnect *now* instead of waiting for the kernel timer.
//

import Foundation
import AppKit
import OSLog

@MainActor
final class ReconnectSupervisor {
    static let shared = ReconnectSupervisor()

    private let log = Logger(subsystem: "com.wavenetic.wavecode-desktop", category: "reconnect")
    private weak var appState: AppState?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var reconnectTask: Task<Void, Never>?

    // Backoff schedule in seconds. Caps at 30s; we never give up — the
    // user might still come back hours later (e.g. closed laptop, plane).
    private let backoffSeconds: [UInt64] = [1, 2, 5, 10, 15, 30]

    private init() {}

    func start(appState: AppState) {
        self.appState = appState
        log.info("reconnect supervisor: starting")

        let nc = NSWorkspace.shared.notificationCenter
        sleepObserver = nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWillSleep()
        }
        wakeObserver = nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidWake()
        }
    }

    func stop() {
        if let s = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(s) }
        if let w = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(w) }
        sleepObserver = nil
        wakeObserver = nil
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    /// Public hook so the UI's "Reconnect" button can request an
    /// immediate retry without waiting for sleep/wake or backoff.
    func kickReconnect() {
        log.info("reconnect: manual kick")
        startReconnectCycleIfNeeded()
    }

    // MARK: - Notification handlers

    private func handleWillSleep() {
        log.info("reconnect: system willSleep — marking connection as reconnecting")
        guard let appState else { return }
        // Pre-set the status; the actual TCP drop will follow as the
        // kernel suspends networking.
        if appState.connectionStatus == .connected {
            appState.connectionStatus = .reconnecting
        }
    }

    private func handleDidWake() {
        log.info("reconnect: system didWake — triggering reconnect attempt")
        startReconnectCycleIfNeeded()
    }

    private func startReconnectCycleIfNeeded() {
        guard let appState else { return }
        guard appState.connectionStatus != .connected,
              appState.connectionStatus != .connecting else {
            log.info("reconnect: already connected/connecting, skipping cycle")
            return
        }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            await self?.runReconnectCycle()
        }
    }

    private func runReconnectCycle() async {
        guard let appState else { return }
        var attempt = 0
        while !Task.isCancelled {
            // Tear down any half-dead state then reconnect via the
            // existing ConnectionManager path. We don't try to be
            // clever about which side of the connection died — just
            // reset and reconnect.
            log.info("reconnect: attempt #\(attempt + 1, privacy: .public)")
            await ConnectionManager.shared.disconnect(appState)
            await ConnectionManager.shared.connect(profile: appState.activeProfile, into: appState)

            if appState.connectionStatus == .connected {
                log.info("reconnect: succeeded on attempt #\(attempt + 1, privacy: .public)")
                return
            }

            // Wait, backed off. Cap at the last entry so we keep
            // retrying every 30s indefinitely (laptop might be closed
            // for hours).
            let delaySec = backoffSeconds[min(attempt, backoffSeconds.count - 1)]
            log.info("reconnect: attempt failed, waiting \(delaySec, privacy: .public)s")
            try? await Task.sleep(nanoseconds: delaySec * 1_000_000_000)
            attempt += 1
        }
    }
}
