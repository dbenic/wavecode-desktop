//
//  Sidebar.swift
//
//  Dark, dense, typography-led sidebar. No translucent material — the
//  whole window reads as one continuous dark surface. Agent names use
//  SF Mono to match the terminal area; section headers are tiny
//  uppercase tracking-wider, the kind of restrained chrome you see in
//  Linear / Raycast / Ghostty.
//

import SwiftUI

struct Sidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    AgentsSection()
                        .padding(.top, 12)
                    Spacer().frame(height: 16)
                    ArtifactsSection()
                    Spacer().frame(height: 12)
                }
                .padding(.horizontal, 6)
            }
            .scrollContentBackground(.hidden)

            SpawnAgentBar()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WaveColors.chrome)
        .overlay(alignment: .trailing) {
            // 1-pixel hairline between sidebar and main column
            Rectangle()
                .fill(WaveColors.divider)
                .frame(width: 1)
        }
    }
}

// MARK: - Sections

private struct AgentsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(
                label: "Agents",
                count: appState.agents.count,
                trailing: AnyView(RefreshAgentsButton())
            )

            if appState.agents.isEmpty {
                EmptyAgentsRow()
            } else {
                ForEach(appState.agents) { agent in
                    AgentRow(
                        agent: agent,
                        isActive: appState.activeAgentId == agent.id
                    )
                    .onTapGesture { appState.activeAgentId = agent.id }
                }
            }
        }
    }
}

private struct ArtifactsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(label: "Artifacts", count: nil, trailing: nil)

            ArtifactRow(label: "Inbox", systemImage: "tray.and.arrow.down")
            ArtifactRow(label: "Latest", systemImage: "photo")
        }
    }
}

// MARK: - Rows

private struct AgentRow: View {
    let agent: Agent
    let isActive: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: agent.status)
            Text(agent.name)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isActive {
                Rectangle()
                    .fill(WaveColors.accent)
                    .frame(width: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        isActive ? WaveColors.primary : (isHovered ? WaveColors.primary : WaveColors.secondary)
    }

    private var rowBackground: Color {
        if isActive { return WaveColors.activeBg }
        if isHovered { return WaveColors.hoverBg }
        return .clear
    }
}

private struct ArtifactRow: View {
    let label: String
    let systemImage: String
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(WaveColors.tertiary)
                .font(.system(size: 11))
                .frame(width: 14)
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(isHovered ? WaveColors.primary : WaveColors.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? WaveColors.hoverBg : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

private struct EmptyAgentsRow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            if appState.connectionStatus == .connected {
                Text("No agents on this server.")
                    .font(.system(size: 11))
                    .foregroundStyle(WaveColors.tertiary)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(WaveColors.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: - Chrome pieces

private struct SectionHeader: View {
    let label: String
    let count: Int?
    let trailing: AnyView?

    var body: some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(WaveColors.tertiary)
            if let count {
                Text("\(count)")
                    .font(.system(size: 10, weight: .regular).monospacedDigit())
                    .foregroundStyle(WaveColors.muted)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }
}

private struct RefreshAgentsButton: View {
    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    var body: some View {
        Button {
            Task { await ConnectionManager.shared.refreshAgents(into: appState) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isHovered ? WaveColors.primary : WaveColors.tertiary)
                .padding(4)
                .background(isHovered ? WaveColors.hoverBg : .clear, in: RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .help("Refresh agent list")
        .disabled(appState.connectionStatus != .connected)
        .onHover { isHovered = $0 }
    }
}

private struct SpawnAgentBar: View {
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(WaveColors.divider)
                .frame(height: 1)
            Button {
                // TODO: spawn agent flow
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 11))
                    Text("Spawn agent")
                        .font(.system(size: 12))
                    Spacer()
                    Text("⌘N")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(WaveColors.muted)
                }
                .foregroundStyle(isHovered ? WaveColors.primary : WaveColors.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isHovered ? WaveColors.hoverBg : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .onHover { isHovered = $0 }
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
        case .working: WaveColors.statusWorking
        case .error: WaveColors.statusError
        case .idle: WaveColors.statusIdle
        }
    }
}
