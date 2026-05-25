//
//  AgentTerminalView.swift
//
//  Embeds SwiftTerm to render an SSH PTY attached to the agent's tmux
//  session. Native CoreText rendering, real OS clipboard, true colors,
//  full terminal feel. NO web view, NO xterm.js.
//
//  v0 stub: renders a placeholder SwiftTerm view. Real PTY wiring lands
//  in week 1 alongside the Citadel SSH layer.
//

import SwiftUI
import SwiftTerm

struct AgentTerminalView: View {
    let agent: Agent
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Header strip — agent name, status, elapsed
            HStack(spacing: 8) {
                StatusDot(status: agent.status)
                Text(agent.name)
                    .font(.system(.body, design: .monospaced).bold())
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(agent.runtime)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // The terminal itself — wraps SwiftTerm's NSView in SwiftUI
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
/// we bridge via NSViewRepresentable. The actual SSH PTY hook-up lives
/// in TerminalCoordinator (week 1 — currently a stub).
struct TerminalHost: NSViewRepresentable {
    let tmuxSession: String

    func makeCoordinator() -> TerminalCoordinator {
        TerminalCoordinator(tmuxSession: tmuxSession)
    }

    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView()
        view.allowMouseReporting = true
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        // Re-attach if the underlying session changed
        if context.coordinator.tmuxSession != tmuxSession {
            context.coordinator.tmuxSession = tmuxSession
            context.coordinator.attach(to: nsView)
        }
    }
}

/// Owns the SSH PTY channel for one terminal view. Bridges bytes
/// between SwiftTerm and the Citadel SSH client.
///
/// v0 stub: writes a placeholder message into the terminal. Real PTY
/// wiring lands in week 1 (see Networking/SSHClient.swift TODO).
final class TerminalCoordinator: NSObject {
    var tmuxSession: String
    private weak var terminalView: TerminalView?

    init(tmuxSession: String) {
        self.tmuxSession = tmuxSession
    }

    func attach(to view: TerminalView) {
        self.terminalView = view
        let header = """

        \u{001B}[1;92m[WaveCode Desktop — v0 Swift]\u{001B}[0m
        \u{001B}[90m  Would attach to tmux session: \(tmuxSession)\u{001B}[0m
        \u{001B}[90m  SSH PTY wiring lands in week 1.\u{001B}[0m

        """
        view.feed(text: header)
        // TODO(week-1): open Citadel SSH channel, request PTY, exec
        //               `tmux attach -t \(tmuxSession)`, pipe bytes both ways.
    }
}
