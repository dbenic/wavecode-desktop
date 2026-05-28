//
//  ConnectionBanner.swift
//
//  Shown at the top of the workspace when the SSH connection is in a
//  non-connected state AFTER an initial successful connection. Keeps
//  the workspace visible (so the user can see their cached terminal
//  views) while making the failure mode + recovery affordance explicit.
//
//  The initial connect splash (ConnectionGate) is still used for the
//  very first connection — before there's any terminal state to
//  preserve. The banner is for "we WERE connected, now we aren't".
//

import SwiftUI

struct ConnectionBanner: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let banner = bannerKind {
            HStack(spacing: 10) {
                Circle()
                    .fill(banner.color)
                    .frame(width: 7, height: 7)
                    .modifier(PulseIfActive(active: banner.pulses))

                VStack(alignment: .leading, spacing: 1) {
                    Text(banner.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WaveColors.primary)
                    if let detail = banner.detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(WaveColors.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }

                Spacer()

                if banner.showRetry {
                    Button("Reconnect") {
                        ReconnectSupervisor.shared.kickReconnect()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(banner.color.opacity(0.08))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(banner.color.opacity(0.25))
                    .frame(height: 1)
            }
        }
    }

    private var bannerKind: BannerKind? {
        switch appState.connectionStatus {
        case .connected, .disconnected:
            return nil
        case .connecting:
            return BannerKind(
                title: "Connecting…",
                detail: nil,
                color: WaveColors.statusWarn,
                pulses: true,
                showRetry: false
            )
        case .reconnecting:
            return BannerKind(
                title: "Reconnecting…",
                detail: "Waiting for \(appState.activeProfile.sshHost) to come back. Your tmux sessions are safe on the server.",
                color: WaveColors.statusWarn,
                pulses: true,
                showRetry: true
            )
        case .error:
            return BannerKind(
                title: "Connection lost",
                detail: appState.connectionError ?? "Unknown error.",
                color: WaveColors.statusError,
                pulses: false,
                showRetry: true
            )
        }
    }
}

private struct BannerKind {
    let title: String
    let detail: String?
    let color: Color
    let pulses: Bool
    let showRetry: Bool
}

/// Animates a subtle "breathing" effect on the indicator dot while
/// the underlying state is in progress (connecting / reconnecting).
private struct PulseIfActive: ViewModifier {
    let active: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        if active {
            content
                .opacity(on ? 1 : 0.4)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: on)
                .onAppear { on = true }
                .onDisappear { on = false }
        } else {
            content
        }
    }
}
