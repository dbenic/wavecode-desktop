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
            HStack(spacing: 8) {
                StatusDot(status: agent.status)
                Text(agent.name)
                    .font(.system(.body, design: .monospaced).bold())
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(agent.runtime)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("tmux: \(agent.tmuxSession)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            TerminalHost(tmuxSession: agent.tmuxSession)
        }
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

    func makeCoordinator() -> TerminalCoordinator {
        TerminalCoordinator(tmuxSession: tmuxSession)
    }

    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView()
        view.configureNativeColors()
        view.allowMouseReporting = true
        view.terminalDelegate = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
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
    private var session: TerminalSession?

    init(tmuxSession: String) {
        self.tmuxSession = tmuxSession
    }

    func attach(to view: TerminalView) {
        self.terminalView = view
        startSession()
    }

    func reattach(to view: TerminalView) {
        self.terminalView = view
        session?.close()
        session = nil
        startSession()
    }

    func detach() {
        session?.close()
        session = nil
        terminalView = nil
    }

    private func startSession() {
        let tmuxSession = self.tmuxSession
        let command = "tmux attach -t \(tmuxSession)"

        // We're not @MainActor; hop to it via Task. SwiftTerm's feed is
        // safe off main but we keep all UI work on main to be safe.
        Task { @MainActor in
            self.terminalView?.feed(text: "\r\n\u{001B}[1;90m[attaching to tmux session: \(tmuxSession)]\u{001B}[0m\r\n")

            do {
                let manager = ConnectionManager.shared
                guard manager.isConnected else {
                    self.terminalView?.feed(text: "\r\n\u{001B}[31m[not connected — connect to the server first]\u{001B}[0m\r\n")
                    return
                }
                let session = try manager.openTerminalSession(
                    command: command,
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
        // TODO(week-2): wire to PTY window_change via Citadel — current
        // withTTY API doesn't expose resize cleanly; revisit when
        // refactoring to lower-level channel access.
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
