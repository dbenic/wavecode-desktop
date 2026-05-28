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
/// we bridge via NSViewRepresentable.
///
/// We wrap SwiftTerm's TerminalView in a plain container NSView and
/// pin it with Auto Layout constraints. Without this wrapper,
/// SwiftTerm's TerminalView resolves to a tiny intrinsic content size
/// inside SwiftUI's NSViewRepresentable and refuses to fill the
/// proposed frame — leaving the terminal as a one-line strip at the
/// top of the workspace.
struct TerminalHost: NSViewRepresentable {
    let tmuxSession: String
    @Environment(AppState.self) private var appState

    func makeCoordinator() -> TerminalCoordinator {
        TerminalCoordinator(tmuxSession: tmuxSession, appState: appState)
    }

    func makeNSView(context: Context) -> NSView {
        let container = TerminalHostContainer()

        let term = TerminalView(frame: .zero)
        term.configureNativeColors()
        term.allowMouseReporting = true
        term.font = appState.terminalPrefs.makeFont()
        term.terminalDelegate = context.coordinator
        // We manage SwiftTerm's frame manually from
        // TerminalHostContainer.layout() so Auto Layout (which has
        // misbehaved across our previous fix attempts here, leaving
        // the terminal at intrinsic size) is out of the picture for
        // the inner view. The container itself is laid out by
        // SwiftUI via the NSViewRepresentable's proposed frame.
        term.translatesAutoresizingMaskIntoConstraints = true
        term.autoresizingMask = []  // do nothing — we frame it ourselves

        container.addSubview(term)
        container.terminalView = term

        context.coordinator.attach(to: term)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? TerminalHostContainer,
              let term = container.terminalView else { return }

        // Live-update font when prefs change.
        let want = appState.terminalPrefs.makeFont()
        if term.font.pointSize != want.pointSize ||
           term.font.fontName != want.fontName {
            term.font = want
        }
        if context.coordinator.tmuxSession != tmuxSession {
            context.coordinator.tmuxSession = tmuxSession
            context.coordinator.reattach(to: term)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: TerminalCoordinator) {
        coordinator.detach()
    }
}

/// NSView container that holds the SwiftTerm TerminalView. We manage
/// the inner view's frame manually here in `setFrameSize` (and
/// `layout()` as belt-and-braces) rather than via Auto Layout
/// constraints — Auto Layout + NSViewRepresentable + SwiftTerm's
/// internal sizing has repeatedly produced one-cell-tall terminals
/// pinned to the corner. Manually setting the frame each time the
/// container is sized is deterministic: SwiftTerm's own setFrameSize
/// then processSizeChange fire synchronously, terminal.cols/rows
/// update, and our sizeChanged delegate fires with real numbers.
private final class TerminalHostContainer: NSView {
    weak var terminalView: TerminalView?

    /// setFrameSize fires whenever the container's frame is set
    /// (which SwiftUI's NSViewRepresentable does to size us to the
    /// proposed frame). Sync the inner SwiftTerm immediately so its
    /// own setFrameSize → processSizeChange → sizeChanged delegate
    /// fires within the same layout pass.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncInnerFrame()
    }

    /// layout() is also called by AppKit during the layout pass —
    /// secondary path in case setFrameSize hasn't kept up.
    override func layout() {
        super.layout()
        syncInnerFrame()
    }

    private func syncInnerFrame() {
        guard let term = terminalView else { return }
        if term.frame != bounds {
            term.frame = bounds
        }
    }

    /// No intrinsic size — let SwiftUI's proposed frame drive sizing.
    override var intrinsicContentSize: NSSize {
        .init(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
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

    // Latest size SwiftTerm has reported for our view. Tracked
    // separately from the session because sizeChanged fires AS THE
    // VIEW IS LAID OUT — which happens before our async startSession
    // can finish creating the PTY. Without this we'd lose the
    // post-layout size and the PTY would stay at the tiny initial
    // 20×5 we passed at startSession time, even though the view is
    // actually 200×50. We apply pendingSize as soon as `session`
    // becomes non-nil and on every subsequent sizeChanged.
    private var pendingCols: Int?
    private var pendingRows: Int?

    // Coalesce inbound byte chunks within one display frame so heavy
    // output (build logs, big diffs) doesn't trigger one render per
    // tiny SSH chunk. Buffer-and-flush approach: bytes arrive on the
    // SSH I/O queue → appended to a buffer guarded by a serial queue
    // → a coalescing timer (or immediate if first byte) drains to
    // SwiftTerm on the main thread.
    private let coalesceQueue = DispatchQueue(label: "com.wavenetic.wavecode-desktop.terminal.coalesce")
    private var coalesceBuffer: [UInt8] = []
    private var coalesceScheduled = false
    private static let coalesceWindowMs: Int = 16  // ~1 frame at 60 Hz

    init(tmuxSession: String, appState: AppState) {
        self.tmuxSession = tmuxSession
        self.appState = appState
    }

    func attach(to view: TerminalView) {
        // Defensive: SwiftUI shouldn't call makeNSView twice for the
        // same coordinator, but if it ever did, we'd leak the prior
        // event monitor. Uninstall first for symmetry with reattach.
        WheelForwarder.uninstall(wheelMonitor)
        wheelMonitor = nil
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
                        // Coalesce instead of feeding immediately — see
                        // enqueueBytes for the rationale.
                        self?.enqueueBytes(bytes)
                    },
                    onClosed: { [weak self] error in
                        Task { @MainActor in
                            // Flush any pending coalesced bytes before
                            // the closed message so we don't lose the
                            // tail of the output.
                            self?.flushCoalesceBufferImmediately()
                            let msg = error.map { "[session closed: \($0.localizedDescription)]" }
                                ?? "[session closed]"
                            self?.terminalView?.feed(text: "\r\n\u{001B}[90m\(msg)\u{001B}[0m\r\n")
                        }
                    }
                )
                self.session = session

                // Apply the post-layout size to the freshly-opened PTY.
                // Three paths (in priority order):
                //   1. pendingCols/Rows captured during the async wait
                //   2. terminal.cols/rows (if SwiftTerm has measured)
                //   3. delayed retry — last resort if layout hasn't
                //      settled by the time the session opens
                self.applyKnownSizeToSession(session)

                // Belt-and-braces: after a short delay, force-resize
                // using whatever SwiftTerm reports then. Handles the
                // case where the view IS sized but processSizeChange
                // hasn't fired our delegate yet (e.g. cellDimension
                // wasn't measured until first display).
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    self?.applyKnownSizeToSession(session)
                }
            } catch {
                self.terminalView?.feed(text: "\r\n\u{001B}[31m[failed to open session: \(error.localizedDescription)]\u{001B}[0m\r\n")
            }
        }
    }

    /// Push the best-known cols/rows to a (re-)opened session. Tries
    /// pending size first (captured before session existed), then the
    /// terminal's reported size. No-op if the terminal has nothing
    /// useful to report.
    private func applyKnownSizeToSession(_ session: TerminalSession) {
        if let cols = pendingCols, let rows = pendingRows, cols > 1, rows > 1 {
            session.resize(cols: cols, rows: rows)
            pendingCols = nil
            pendingRows = nil
            return
        }
        if let term = terminalView?.getTerminal(), term.cols > 1, term.rows > 1 {
            session.resize(cols: term.cols, rows: term.rows)
        }
    }

    // MARK: - Output coalescing

    /// Called from the SSH I/O task whenever a chunk of bytes arrives
    /// from the remote PTY. Appends to a buffer (on a serial queue to
    /// avoid races between concurrent SSH chunk deliveries), then
    /// either schedules a frame-aligned flush or — if already
    /// scheduled — just lets the existing timer fire.
    ///
    /// The net effect: dozens of tiny chunks during a heavy redraw
    /// (cargo build, vim re-paint) collapse into one feed() call per
    /// ~16 ms, which is what the display can actually present anyway.
    /// Smoother scrolling, less CPU on render thrash.
    private func enqueueBytes(_ bytes: ArraySlice<UInt8>) {
        coalesceQueue.async { [weak self] in
            guard let self else { return }
            self.coalesceBuffer.append(contentsOf: bytes)
            guard !self.coalesceScheduled else { return }
            self.coalesceScheduled = true
            self.coalesceQueue.asyncAfter(deadline: .now() + .milliseconds(Self.coalesceWindowMs)) { [weak self] in
                self?.flushCoalescedBuffer()
            }
        }
    }

    private func flushCoalescedBuffer() {
        // CRITICAL: this runs *on* coalesceQueue (it was scheduled via
        // coalesceQueue.asyncAfter). A previous version called
        // coalesceQueue.sync { ... } from here — that's a serial-queue
        // re-entrant sync, which deadlocks. Drain inline instead;
        // we're already on the right queue.
        let pending = coalesceBuffer
        coalesceBuffer.removeAll(keepingCapacity: true)
        coalesceScheduled = false
        guard !pending.isEmpty else { return }
        Task { @MainActor [weak self] in
            self?.terminalView?.feed(byteArray: ArraySlice(pending))
        }
    }

    /// Drain whatever's pending right now, used on session-end so the
    /// user always sees the tail of the output before the close banner.
    private func flushCoalesceBufferImmediately() {
        let pending: [UInt8] = coalesceQueue.sync {
            let out = coalesceBuffer
            coalesceBuffer.removeAll(keepingCapacity: true)
            coalesceScheduled = false
            return out
        }
        guard !pending.isEmpty else { return }
        terminalView?.feed(byteArray: ArraySlice(pending))
    }

    // MARK: - TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        session?.send(data)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        // Real SSH window_change message — the kernel signals SIGWINCH
        // to the remote process and tmux redraws cleanly. No stdin
        // interleaving, no artifacts, no `stty` hack.
        //
        // If the session isn't open yet, stash the size. startSession
        // applies pendingCols/Rows the moment it finishes — without
        // this, the post-layout sizeChanged that fires after we kick
        // off openTerminalSession would be lost and the PTY would
        // remain at its tiny initial dimensions forever.
        if let session = session {
            session.resize(cols: newCols, rows: newRows)
        } else {
            pendingCols = newCols
            pendingRows = newRows
        }
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
