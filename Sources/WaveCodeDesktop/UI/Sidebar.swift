//
//  Sidebar.swift
//
//  Agent list (top) + artifacts (middle) + spawn button (bottom).
//  Data comes from AppState, which is fed by SSE from the WaveCode server.
//  v0: shows sample agents until the SSE consumer lands in week 2.
//

import SwiftUI

struct Sidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.activeAgentId) {
            Section {
                if appState.agents.isEmpty {
                    if appState.connectionStatus == .connected {
                        Text("No agents on this server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.vertical, 4)
                    }
                } else {
                    ForEach(appState.agents) { agent in
                        AgentRow(agent: agent)
                            .tag(agent.id as String?)
                            .contextMenu {
                                Button("Open in new window") {
                                    // TODO: openWindow(id: "agent", value: agent.id)
                                }
                            }
                    }
                }
            } header: {
                HStack {
                    Text("Agents (\(appState.agents.count))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await ConnectionManager.shared.refreshAgents(into: appState) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh agent list")
                    .disabled(appState.connectionStatus != .connected)
                }
            }

            Section("Artifacts") {
                Label("Inbox", systemImage: "tray.and.arrow.down")
                Label("Latest", systemImage: "photo")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    // TODO: spawn agent flow
                } label: {
                    Label("Spawn agent", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }
}

struct AgentRow: View {
    let agent: Agent

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: agent.status)
            Text(agent.name)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

struct StatusDot: View {
    let status: AgentStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: status == .working ? color.opacity(0.6) : .clear, radius: 2)
    }

    private var color: Color {
        switch status {
        case .working: .green
        case .error: .red
        case .idle: .secondary
        }
    }
}
