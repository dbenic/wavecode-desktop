//
//  SettingsView.swift
//
//  Standard macOS settings window — server profile management goes here
//  eventually. v0 is a placeholder so the Settings command in the app
//  menu has something to open.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            ServerProfileSettings()
                .tabItem { Label("Servers", systemImage: "server.rack") }
        }
        .padding()
        .frame(width: 520, height: 320)
    }
}

struct ServerProfileSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        Form {
            Section("Default server") {
                TextField("Label", text: $appState.profile.label)
                TextField("SSH host", text: $appState.profile.sshHost)
                TextField("SSH user (optional)", text: Binding(
                    get: { appState.profile.sshUser ?? "" },
                    set: { appState.profile.sshUser = $0.isEmpty ? nil : $0 }
                ))
                TextField("SSH port", value: $appState.profile.sshPort, format: .number)
                TextField("WaveCode port", value: $appState.profile.wavecodePort, format: .number)
            }
        }
        .formStyle(.grouped)
    }
}
