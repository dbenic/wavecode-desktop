//
//  SettingsView.swift
//
//  Standard macOS settings window. Currently has one tab — server
//  profiles. List on the left, edit form on the right, +/− to add or
//  remove, "Set as active" to make a profile the connection target.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            ServerProfilesPane()
                .tabItem { Label("Servers", systemImage: "server.rack") }
        }
        .padding()
        .frame(width: 720, height: 460)
    }
}

struct ServerProfilesPane: View {
    @Environment(AppState.self) private var appState
    @State private var selectedId: UUID?

    var body: some View {
        HStack(spacing: 0) {
            // Profile list
            VStack(spacing: 0) {
                List(selection: $selectedId) {
                    ForEach(appState.profiles) { profile in
                        ProfileListRow(
                            profile: profile,
                            isActive: profile.id == appState.activeProfileId
                        )
                        .tag(profile.id as UUID?)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    Button {
                        let new = ServerProfile.newDraft()
                        appState.addProfile(new)
                        selectedId = new.id
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Add a new server profile")

                    Button {
                        if let id = selectedId, appState.profiles.count > 1 {
                            appState.removeProfile(id: id)
                            selectedId = appState.profiles.first?.id
                        }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedId == nil || appState.profiles.count <= 1)
                    .help("Remove the selected profile (must keep at least one)")

                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 220)
            .background(.regularMaterial)

            Divider()

            // Edit form
            if let id = selectedId ?? appState.activeProfileId,
               let profile = appState.profiles.first(where: { $0.id == id }) {
                ProfileEditForm(initial: profile)
                    .id(profile.id)  // remount when selection changes
            } else {
                ContentUnavailableView(
                    "No profile selected",
                    systemImage: "server.rack",
                    description: Text("Pick a profile on the left or add a new one.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selectedId == nil { selectedId = appState.activeProfileId }
        }
    }
}

struct ProfileListRow: View {
    let profile: ServerProfile
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isActive ? "circle.inset.filled" : "circle")
                .foregroundStyle(isActive ? .green : .secondary)
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.label)
                    .font(.system(size: 12, weight: .medium))
                Text(profile.sshHost)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Edit form. Keeps a local @State copy so the user can experiment
/// without instantly persisting; "Save" pushes back to AppState.
struct ProfileEditForm: View {
    @Environment(AppState.self) private var appState
    @State private var draft: ServerProfile
    private let initialId: UUID

    init(initial: ServerProfile) {
        self._draft = State(initialValue: initial)
        self.initialId = initial.id
    }

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Label", text: $draft.label)
                    .help("Friendly name shown in the sidebar (e.g. 'wave (personal)')")
            }

            Section("SSH connection") {
                TextField("Host", text: $draft.sshHost)
                    .help("Hostname or IP. Can match an alias from ~/.ssh/config.")
                TextField("User (optional)",
                          text: Binding(
                            get: { draft.sshUser ?? "" },
                            set: { draft.sshUser = $0.isEmpty ? nil : $0 }
                          ))
                .help("Defaults to your macOS login name.")
                TextField("Port", value: $draft.sshPort, format: .number)
                    .frame(maxWidth: 100)
            }

            Section("Identity file (optional)") {
                HStack {
                    TextField("Path",
                              text: Binding(
                                get: { draft.identityFile ?? "" },
                                set: { draft.identityFile = $0.isEmpty ? nil : $0 }
                              ),
                              prompt: Text("Leave blank to try ~/.ssh/id_ed25519 then id_rsa"))
                    Button("Browse…") {
                        chooseKeyFile()
                    }
                }
                Text("Use this to pin a specific private key for this server (e.g. ~/.ssh/wave_key).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("WaveCode") {
                TextField("API port", value: $draft.wavecodePort, format: .number)
                    .frame(maxWidth: 100)
                    .help("Port the WaveCode daemon listens on, server-side. Default 3777.")
            }

            Section {
                HStack {
                    Button("Set as active") {
                        appState.updateProfile(draft)
                        appState.setActive(id: draft.id)
                    }
                    .disabled(draft.id == appState.activeProfileId && isUnchanged)

                    Spacer()

                    Button("Revert") {
                        if let current = appState.profiles.first(where: { $0.id == initialId }) {
                            draft = current
                        }
                    }
                    .disabled(isUnchanged)

                    Button("Save") {
                        appState.updateProfile(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isUnchanged)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var isUnchanged: Bool {
        guard let current = appState.profiles.first(where: { $0.id == initialId }) else { return false }
        return current == draft
    }

    private func chooseKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)
        panel.treatsFilePackagesAsDirectories = true
        // Show hidden files so users can navigate into ~/.ssh
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            draft.identityFile = url.path
        }
    }
}

#if canImport(AppKit)
import AppKit
#endif
