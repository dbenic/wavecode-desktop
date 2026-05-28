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
import AppKit

@main
struct WaveCodeDesktopApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(WaveCodeAppDelegate.self) private var appDelegate

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

            // View → font size shortcuts. These mutate the shared
            // TerminalPrefs which the open TerminalHosts observe and
            // re-apply via updateNSView.
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Increase Font Size") {
                    appState.terminalPrefs.increaseSize()
                }
                .keyboardShortcut("=", modifiers: .command) // ⌘+ on US layout
                Button("Decrease Font Size") {
                    appState.terminalPrefs.decreaseSize()
                }
                .keyboardShortcut("-", modifiers: .command)
                Button("Reset Font Size") {
                    appState.terminalPrefs.resetSize()
                }
                .keyboardShortcut("0", modifiers: .command)
            }

            // Edit menu: Copy / Paste / Select All wired to the terminal.
            //   - Copy (⌘C): routed through the responder chain to
            //     SwiftTerm's copy(_:), which copies the current native
            //     selection to the macOS pasteboard. (tmux's own mouse
            //     selection is handled separately via OSC 52 + our
            //     clipboardCopy delegate — see TerminalCoordinator.)
            //   - Paste (⌘V): sends clipboard to the PTY with bracketed
            //     paste markers so shells don't auto-execute multi-line
            //     content.
            //   - Select All (⌘A): SwiftTerm selects the whole buffer.
            //
            // Previously this group defined only Paste, which (because
            // `replacing:` wipes the whole group) removed Copy/Select-All
            // and prevented ⌘C from ever reaching SwiftTerm.
            CommandGroup(replacing: .pasteboard) {
                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Paste") {
                    appState.activeTerminalCoordinator?.pasteFromClipboard()
                }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(appState.activeTerminalCoordinator == nil)

                Button("Select All") {
                    NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
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

/// When the app runs via `swift run` (i.e. as a raw executable rather
/// than a packaged .app bundle), macOS doesn't auto-activate it — so no
/// window appears even though the SwiftUI scene is mounted. We fix that
/// by explicitly setting `.regular` activation policy and forcing focus
/// on launch. This is a no-op for proper .app launches but harmless.
final class WaveCodeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Ensure at least one window is visible. With WindowGroup the
        // OS should restore the last window automatically, but on first
        // launch this guarantees the user sees something.
        if NSApp.windows.first(where: { $0.isVisible && !$0.title.isEmpty }) == nil {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
