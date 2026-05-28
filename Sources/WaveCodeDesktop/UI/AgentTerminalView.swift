//
//  AgentTerminalView.swift
//
//  Embeds SwiftTerm to render an SSH PTY attached to the agent's tmux
//  session. Native CoreText rendering, real OS clipboard, true colors.
//  No web view, no xterm.js.
//
//  The wiring:
//    SwiftUI AgentTerminalView
//      → TerminalHost (NSViewRepresentable, makes SwiftTerm.TerminalView)
//        → TerminalCoordinator (TerminalViewDelegate)
//          → ConnectionManager.openTerminalSession
//            → TerminalSession (Citadel withTTY) → tmux attach -t <session>
//

import SwiftUI
import SwiftTerm
import AppKit

struct AgentTerminalView: View {
    let agent: Agent
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Header strip — agent name, status, runtime
            HStack(spacing: 10) {
                StatusDot(status: agent.status)
                Text(agent.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WaveColors.primary)
                Text("·")
                    .foregroundStyle(WaveColors.muted)
                Text(agent.runtime)
                    .font(.system(size: 11))
                    .foregroundStyle(WaveColors.tertiary)
                Text("·")
                    .foregroundStyle(WaveColors.muted)
                Text("tmux: \(agent.tmuxSession)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WaveColors.tertiary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(WaveColors.chrome)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(WaveColors.divider)
                    .frame(height: 1)
            }

            TerminalHost(tmuxSession: agent.tmuxSession)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Window-presented variant — used by the per-agent WindowGroup.
struct AgentTerminalWindow: View {
    let agentId: String
    @Environment(AppState.self) private var appState

    var body: some View {
        if let agent = appState.agent(byId: agentId) {
            AgentTerminalView(agent: agent)
                .navigationTitle(agent.name)
        } else {
            ContentUnavailableView("Agent not found", systemImage: "questionmark.circle")
        }
    }
}

/// SwiftUI wrapper around SwiftTerm's NSView. SwiftTerm is AppKit-based;
/// we bridge via NSViewRepresentable. The PTY hook-up lives in
/// TerminalCoordinator.
struct TerminalHost: NSViewRepresentable {
    let tmuxSession: String
    @Environment(AppState.self) private var appState

    func makeCoordinator() -> TerminalCoordinator {
        TerminalCoordinator(tmuxSession: tmuxSession, appState: appState)
    }

    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView()
        view.configureNativeColors()
        view.allowMouseReporting = true
        view.font = appState.terminalPrefs.makeFont()
        view.terminalDelegate = context.coordinator
        // Ensure the NSView grows with its container so SwiftTerm reports
        // accurate cols/rows for the layout we actually have on screen.
        view.autoresizingMask = [.width, .height]
        view.translatesAutoresizingMaskIntoConstraints = true
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        // Live-update font when prefs change.
        let want = appState.terminalPrefs.makeFont()
        if nsView.font.pointSize != want.pointSize ||
           nsView.font.fontName != want.fontName {
            nsView.font = want
        }
        if context.coordinator.tmuxSession != tmuxSession {
            context.coordinator.tmuxSession = tmuxSession
            context.coordinator.reattach(to: nsView)
        }
    }

    static func dismantleNSView(_ nsView: TerminalView, coordinator: TerminalCoordinator) {
        coordinator.detach()
    }
}

/// Bridges SwiftTerm's TerminalView with a TerminalSession (SSH PTY).
/// - Implements `TerminalViewDelegate` so keystrokes from the user
///   get forwarded to the remote PTY.
/// - Owns the lifetime of the TerminalSession.
final class TerminalCoordinator: NSObject, TerminalViewDelegate {
    var tmuxSession: String
    private weak var terminalView: TerminalView?
    private weak var appState: AppState?
    private var session: TerminalSession?
    private var wheelMonitor: Any?

    init(tmuxSession: String, appState: AppState) {
        self.tmuxSession = tmuxSession
        self.appState = appState
    }

    func attach(to view: TerminalView) {
        self.terminalView = view
        installWheelForwarder(on: view)
        registerAsActive()
        startSession()
    }

    func reattach(to view: TerminalView) {
        WheelForwarder.uninstall(wheelMonitor)
        wheelMonitor = nil
        self.terminalView = view
        installWheelForwarder(on: view)
        registerAsActive()

        // HOTFIX: do NOT close the previous session here. Closing the
        // SSH child channel was somehow terminating the user's tmux
        // session on the server (not just our client view), causing
        // long-running Claude/Codex agents to die on every agent switch.
        //
        // Until we understand the root cause, orphan the old session:
        // the SSH channel stays open, tmux attach keeps running on the
        // server (the bytes it produces stream into a now-orphaned
        // pumpTask whose callback's `terminalView` weak ref is nil →
        // silent drop). User-visible: no data loss, no killed sessions.
        // Cost: each switch leaks one SSH channel + one pumpTask. After
        // hundreds of switches, the user should restart the app. We'll
        // replace this with a proper per-agent session registry next.
        //
        // session?.close() ← DO NOT REINSTATE WITHOUT FIXING ROOT CAUSE.
        session = nil
        clearTerminal()
        startSession()
    }

    func detach() {
        WheelForwarder.uninstall(wheelMonitor)
        wheelMonitor = nil
        // Only clear AppState's pointer if we're still the active one
        // (a newer coordinator may have taken over before this teardown).
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.appState?.activeTerminalCoordinator === self {
                self.appState?.activeTerminalCoordinator = nil
            }
        }
        // HOTFIX: same as reattach — don't close. See comment above.
        // The Coordinator may be torn down by SwiftUI when the view
        // dismantles, but that doesn't mean the user wants the session
        // killed.
        session = nil
        terminalView = nil
    }

    private func registerAsActive() {
        Task { @MainActor [weak self] in
            self?.appState?.activeTerminalCoordinator = self
        }
    }

    private func installWheelForwarder(on view: TerminalView) {
        wheelMonitor = WheelForwarder.install(on: view)
    }

    /// Wipe SwiftTerm's screen + scrollback so the new session starts on a
    /// clean view. ESC[2J = clear visible; ESC[3J = clear scrollback;
    /// ESC[H = home cursor.
    private func clearTerminal() {
        terminalView?.feed(text: "\u{001B}[2J\u{001B}[3J\u{001B}[H")
    }

    /// Pull text from NSPasteboard and send it through the active PTY.
    /// Wired to ⌘V at the App's command level. No-op when no session is
    /// open or the pasteboard is empty / non-textual.
    func pasteFromClipboard() {
        guard let session else { return }
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        // Bracketed-paste-aware terminals (tmux/bash/zsh) handle the
        // \e[200~ ... \e[201~ envelope to distinguish typed input from
        // pasted input (so the shell doesn't auto-execute multi-line
        // commands). Tmux passes it through to the program inside.
        let bracketed = "\u{1B}[200~" + text + "\u{1B}[201~"
        let bytes = Array(bracketed.utf8)
        session.send(ArraySlice(bytes))
    }

    private func startSession() {
        let tmuxSession = self.tmuxSession
        let cols = max(20, terminalView?.getTerminal().cols ?? 120)
        let rows = max(5, terminalView?.getTerminal().rows ?? 30)

        // The command does four things:
        //
        //  1. `TERM=xterm-256color` — Citadel's PTY request sends an
        //     empty (or "dumb") TERM by default; tmux can't find a
        //     terminfo entry for that, hence
        //     "terminal does not support clear". xterm-256color is the
        //     near-universal default and matches SwiftTerm's own
        //     emulation.
        //
        //  2. `stty cols X rows Y` — runs *inside* the script subshell
        //     so the new openpty PTY adopts our actual SwiftTerm view
        //     dimensions. Without this, tmux renders at the default
        //     80x24 even though the view is much wider.
        //
        //  3. `script -qc '...' /dev/null` — wraps tmux in a freshly
        //     allocated PTY via openpty(3), with proper
        //     controlling-terminal semantics. Bash works without a
        //     /dev/tty; tmux specifically opens /dev/tty and would
        //     otherwise fail with "not a terminal" because Citadel's
        //     SSH-channel PTY isn't assigned as the controlling
        //     terminal of child processes.
        //
        //  4. `|| true` — defensive. If `script` is somehow missing
        //     (it's part of util-linux on every modern Linux), we
        //     still keep the SSH channel alive so the user sees the
        //     error and can debug from a shell.
        // Three tmux server-level settings, all best-effort (2>/dev/null
        // swallows errors if tmux server isn't up yet or already configured):
        //   - mouse on: enable wheel scrolling via tmux copy mode
        //   - set-clipboard on: OSC 52 escape sequence on copy → tmux's
        //     selection lands on our OS clipboard automatically
        //   - history-limit 100000: deep scrollback (default is only ~2000)
        //
        // These are global server settings that persist until tmux server
        // restart. Sensible defaults that most modern users want.
        let tmuxSetup = """
        tmux set -g mouse on 2>/dev/null; \
        tmux set -g set-clipboard on 2>/dev/null; \
        tmux set -g history-limit 100000 2>/dev/null
        """
        let inner = "stty cols \(cols) rows \(rows); \(tmuxSetup); tmux attach -t \(tmuxSession)"
        let command = "TERM=xterm-256color script -qc '\(inner)' /dev/null || true"

        Task { @MainActor in
            self.terminalView?.feed(text: "\u{001B}[90m[attaching to tmux session: \(tmuxSession)]\u{001B}[0m\r\n")

            do {
                let manager = ConnectionManager.shared
                guard manager.isConnected else {
                    self.terminalView?.feed(text: "\r\n\u{001B}[31m[not connected — connect to the server first]\u{001B}[0m\r\n")
                    return
                }
                let session = try await manager.openTerminalSession(
                    command: command,
                    cols: cols,
                    rows: rows,
                    onBytes: { [weak self] bytes in
                        guard let view = self?.terminalView else { return }
                        // Bytes arrive on the SSH I/O task; SwiftTerm's
                        // feed must be called on main.
                        Task { @MainActor in
                            view.feed(byteArray: bytes)
                        }
                    },
                    onClosed: { [weak self] error in
                        Task { @MainActor in
                            let msg = error.map { "[session closed: \($0.localizedDescription)]" }
                                ?? "[session closed]"
                            self?.terminalView?.feed(text: "\r\n\u{001B}[90m\(msg)\u{001B}[0m\r\n")
                        }
                    }
                )
                self.session = session
            } catch {
                self.terminalView?.feed(text: "\r\n\u{001B}[31m[failed to open session: \(error.localizedDescription)]\u{001B}[0m\r\n")
            }
        }
    }

    // MARK: - TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        session?.send(data)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        // Real SSH window_change message — the kernel signals SIGWINCH
        // to the remote process and tmux redraws cleanly. No stdin
        // interleaving, no artifacts, no `stty` hack.
        session?.resize(cols: newCols, rows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        // No-op for v0; future: bubble to AppState so windows pick it up.
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        guard let str = String(data: content, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func bell(source: TerminalView) {
        NSSound.beep()
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
}

// MARK: - Visual tuning helpers

private extension TerminalView {
    func configureNativeColors() {
        // Match WaveCode brand: dark slate background, emerald accents.
        // SwiftTerm uses NSColor; tune to taste.
        self.nativeBackgroundColor = NSColor(red: 0.008, green: 0.024, blue: 0.090, alpha: 1.0)  // slate-950
        self.nativeForegroundColor = NSColor(red: 0.886, green: 0.910, blue: 0.941, alpha: 1.0)  // slate-200
    }
}
