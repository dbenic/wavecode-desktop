//
//  MainWindow.swift
//
//  The primary control window: sidebar (agents + artifacts) on the left,
//  workspace on the right (terminal embed or status view).
//
//  Additional terminal windows can be opened separately via the
//  "agent" WindowGroup (see WaveCodeDesktopApp).
//

import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .frame(minWidth: 200, idealWidth: 220)
        } detail: {
            WorkspacePane()
        }
        .navigationTitle("WaveCode")
        .navigationSubtitle(appState.profile.label)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ConnectionStatusPill()
            }
            ToolbarItem(placement: .primaryAction) {
                Button { appState.paletteOpen = true } label: {
                    Image(systemName: "command")
                }
                .help("Command palette (⌘K)")
            }
        }
        .task {
            await ConnectionManager.shared.connect(profile: appState.profile, into: appState)
        }
    }
}

struct WorkspacePane: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.connectionStatus != .connected {
            ConnectionGate()
        } else if let id = appState.activeAgentId, let agent = appState.agent(byId: id) {
            AgentTerminalView(agent: agent)
        } else {
            EmptyWorkspace()
        }
    }
}

struct EmptyWorkspace: View {
    var body: some View {
        ContentUnavailableView {
            Label("No agent selected", systemImage: "terminal")
        } description: {
            Text("Pick an agent from the sidebar to attach to its tmux session.")
        }
    }
}

struct ConnectionStatusPill: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: Capsule())
    }

    private var color: Color {
        switch appState.connectionStatus {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .error: .red
        case .disconnected: .secondary
        }
    }

    private var label: String {
        switch appState.connectionStatus {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .reconnecting: "Reconnecting…"
        case .error: "Error"
        case .disconnected: "Disconnected"
        }
    }
}
