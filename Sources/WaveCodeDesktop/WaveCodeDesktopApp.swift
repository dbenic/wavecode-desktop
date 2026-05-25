//
//  WaveCodeDesktopApp.swift
//  WaveCode Desktop — native macOS client.
//
//  See CLAUDE.md for the non-negotiable architectural rules. Short version:
//    - SSH-only, server is source of truth, no local mode of any kind.
//    - Multi-window via SwiftUI's `WindowGroup` + manual `NSWindow` where needed.
//    - The terminal area embeds SwiftTerm (CoreText, native), NOT xterm.js.
//    - One app binary, multiple windows.
//

import SwiftUI

@main
struct WaveCodeDesktopApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        // Main control window — sidebar + multi-pane workspace
        WindowGroup("WaveCode") {
            MainWindow()
                .environment(appState)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Agent…") { /* TODO */ }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .windowList) {
                Button("Command Palette…") { appState.paletteOpen = true }
                    .keyboardShortcut("k", modifiers: .command)
            }
        }

        // Separate window for a single agent's terminal (multi-window pattern).
        // The user opens these by ⌘⏎ on an agent in the sidebar.
        WindowGroup("Agent", id: "agent", for: String.self) { $agentId in
            if let id = agentId {
                AgentTerminalWindow(agentId: id)
                    .environment(appState)
                    .frame(minWidth: 600, minHeight: 400)
            }
        }

        // Settings — standard macOS settings window
        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
