//
//  ConnectionGate.swift
//
//  Shown in the workspace pane while the SSH connection is not yet
//  `connected`. Surfaces auth errors with the actual message from
//  Citadel so the user can fix their ~/.ssh/config or key permissions.
//

import SwiftUI

struct ConnectionGate: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("WAVECODE DESKTOP")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }

            Text("Connect to ")
                .foregroundStyle(.secondary)
            + Text(appState.activeProfile.sshHost)
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.green)

            Text(statusDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if let error = appState.connectionError {
                ScrollView {
                    Text(error)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                        .padding(8)
                }
                .frame(maxWidth: 480, maxHeight: 120)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }

            Button(action: connect) {
                Text(appState.connectionStatus == .connecting ? "Connecting…" : "Connect")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.connectionStatus == .connecting)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusDescription: String {
        switch appState.connectionStatus {
        case .connecting:
            "Authenticating via SSH key…"
        case .error:
            "Could not authenticate. Make sure ~/.ssh/config has an entry for this host and a valid key is present."
        case .disconnected:
            "Ready to connect."
        case .reconnecting:
            "Reconnecting after network change…"
        case .connected:
            "Connected."
        }
    }

    private func connect() {
        Task {
            await ConnectionManager.shared.connect(profile: appState.activeProfile, into: appState)
        }
    }
}
