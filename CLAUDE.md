# WaveCode Desktop — Project Instructions

> If you are an AI agent working on this codebase, read this first. These
> rules shape every architectural decision and override any default
> behaviour.

## What this is

A **native macOS** client for [WaveCode](https://github.com/dbenic/wavecode).
Built in Swift / SwiftUI with SwiftTerm (CoreText terminal renderer) and
Citadel (pure-Swift SSH). **No Electron, no webview, no xterm.js.** The
client connects to a remote WaveCode server over SSH and renders the
remote tmux PTYs in native NSViews.

## Non-negotiable architectural constraints

### 1. SSH-only. No local mode. Ever.

The desktop app never runs WaveCode locally, never spawns agents on the
user's machine, never calls the Anthropic/OpenAI APIs directly. All work
happens on a remote server the user controls. The app connects over a
single SSH connection that multiplexes three channels:

- **Port-forwarded HTTP/SSE** (`localhost:<dyn>` → server's WaveCode daemon)
- **PTY channels** for `tmux attach` rendered in SwiftTerm
- **SFTP channel** for drag-drop artifact uploads

If you find yourself wanting to add a "local fallback" or "offline mode" or
"run agents on the laptop too" — stop. The user explicitly chose SSH-only
because local computers sleep and servers don't. Adding local mode
fragments the architecture and defeats the entire point.

### 2. The server is the source of truth.

State lives on the server: agents, tasks, artifacts, runs, transcripts.
The desktop is a view on that state. Never cache long-term, never assume
the desktop can author state independently. When the desktop "creates"
something, it's making an HTTP POST to the server, which is the canonical
write.

### 3. Tmux is the work surface, not a rendered abstraction.

The terminal area embeds SwiftTerm rendering a real PTY connected to a
real tmux session on the server. We don't reimplement terminal logic,
don't fake the cursor, don't replace tmux's window/pane model with our
own. The sidebar and chrome are *additive* — they let you switch agents,
drop files, search, etc. — but every action ultimately translates to a
real operation on the real tmux session.

Rule of thumb: if a UI interaction can't be expressed as either an HTTP
call to the WaveCode API or a `tmux send-keys`/`tmux select-window`
command on the server, it's probably the wrong design.

### 4. The desktop app holds no secrets beyond the SSH connection.

- API keys (Anthropic, OpenAI, etc.) live on the server, in
  `config.yaml`. Never in the desktop.
- SSH credentials live in the OS (`~/.ssh/config`, ssh-agent, Keychain).
  The app reads them but doesn't manage them in v0.
- The optional WaveCode bearer token can be stored in the macOS Keychain.

This keeps the trust model identical to "I SSH into this server" — which
the user already does and already trusts.

### 5. Native, not web. Multi-window, not single.

This is a **native macOS app**. No web views for primary UI. SwiftUI for
the main UI, AppKit where SwiftUI falls short (NSWindow management,
deep drag-drop, menu bar items).

Multi-window is a first-class pattern, not an afterthought:
- One main control window (sidebar + workspace pane)
- Optional per-agent terminal windows (`WindowGroup(id: "agent", for: String.self)`)
- Settings as a standard macOS settings window
- Future: menu bar status app

Don't try to cram everything into one window. macOS users expect to
spread work across monitors and Mission Control spaces.

### 6. macOS-only is fine.

The cross-platform answer is the WaveCode PWA in the core repo. This
app is the **premium native tier** for macOS. Don't dilute it by trying
to be cross-platform via abstraction layers — that's how Mac apps end up
feeling foreign.

If a Windows/Linux native client is ever built, it should be a separate
repo with the same SSH/SSE protocol contract.

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| Min OS | macOS 14 (Sonoma) | `@Observable`, modern SwiftUI, no need to support ancient versions |
| Language | Swift 5.10+ | Standard for macOS-native |
| UI | SwiftUI primarily, AppKit where needed | Modern declarative + native interop |
| State | `@Observable` (Observation framework) | Replaces ObservableObject/StateObject |
| Terminal | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (Apache 2.0) | CoreText-native, AppKit `TerminalView`, production-mature |
| SSH | [Citadel](https://github.com/orlandos-nl/Citadel) (MIT) | Pure-Swift async/await SSH; no libssh2 baggage |
| Build | SwiftPM via `Package.swift` | Open-source-friendly; Xcode opens it natively |
| Persistence | UserDefaults (prefs), macOS Keychain (tokens), no DB | Server is source of truth |
| Tests | XCTest | Standard |

## Project layout (target)

```
wavecode-desktop/
├── Package.swift                            SPM manifest
├── Sources/WaveCodeDesktop/
│   ├── WaveCodeDesktopApp.swift             @main, WindowGroups, commands
│   ├── Models/
│   │   ├── Agent.swift                      hand-translated from WaveCode API
│   │   ├── ServerProfile.swift              SSH connection profile
│   │   └── ...
│   ├── Networking/
│   │   ├── ConnectionManager.swift          owns SSH session
│   │   ├── SSHClient.swift                  Citadel wrapper (week 1)
│   │   ├── PortForward.swift                TCP forward for WaveCode API (week 2)
│   │   ├── WaveCodeAPI.swift                URLSession HTTP client (week 2)
│   │   └── SSEClient.swift                  Server-sent events (week 2)
│   ├── Terminal/
│   │   ├── TerminalCoordinator.swift        bridges SwiftTerm ↔ SSH PTY
│   │   └── PTYChannel.swift                 SSH PTY lifecycle
│   ├── UI/
│   │   ├── MainWindow.swift
│   │   ├── Sidebar.swift
│   │   ├── AgentTerminalView.swift          wraps SwiftTerm NSView in SwiftUI
│   │   ├── ConnectionGate.swift
│   │   ├── DropZone.swift
│   │   ├── CommandPalette.swift
│   │   └── SettingsView.swift
│   ├── State/
│   │   └── AppState.swift                   @Observable, holds UI state
│   └── Util/
│       ├── KeychainHelper.swift
│       └── ...
├── Tests/WaveCodeDesktopTests/
└── docs/
    ├── architecture.md
    └── building.md
```

## Conventions

- **IDs**: ULIDs from the server; never generate locally.
- **Errors**: use `Result<T, Error>` or `throws` async functions; surface
  to the UI as user-readable strings.
- **Logging**: `OSLog` / `Logger` from `os` framework — appears in
  Console.app and the unified log system.
- **File paths**: `URL` always; never raw `String` concatenation.
- **Tests**: XCTest co-located in `Tests/WaveCodeDesktopTests/`; run via
  `swift test`.
- **Naming**: standard Swift (`camelCase` properties/functions,
  `PascalCase` types).
- **JSON keys**: server uses snake_case (`tmux_session`); map via
  `CodingKeys` enums on the Swift side.

## What NOT to do

- ❌ Don't add a `WKWebView` or any embedded web view for primary UI.
- ❌ Don't add SQLite or any local persistent store beyond UI prefs.
- ❌ Don't add an LLM SDK dependency. LLM calls happen on the server.
- ❌ Don't reimplement terminal logic. Use SwiftTerm as-is.
- ❌ Don't build a "local agent mode" or "offline mode" — see constraint #1.
- ❌ Don't import from the WaveCode core repo directly. Hand-translate
  types for v0; formalize a published Swift package later.
- ❌ Don't try to render multiple agent terminals in a single window via
  custom tab logic — use the OS's `WindowGroup` pattern with multiple
  windows.
- ❌ Don't store secrets in UserDefaults — Keychain only.
- ❌ Don't use `print` for logging — use `Logger`.

## Build order (v0)

1. **Week 1** — Citadel SSH client + PTY channel + SwiftTerm bidirectional
   wire. One agent terminal renders a real remote tmux session.
2. **Week 2** — Port-forward + URLSession HTTP client + SSE consumer. The
   sidebar shows the *real* live agent list with live status dots.
3. **Week 3** — Drag-drop → SFTP upload → artifact API → tmux send-keys.
   **Hero demo.**
4. **Week 4** — Multi-window: per-agent terminal windows opened via
   ⌘⏎ on a sidebar agent or "Open in new window" menu.
5. **Week 5** — Server profile management UI, OS Keychain integration,
   reconnect supervisor for sleep/wake.
6. **Week 6** — Command palette (⌘K), notifications, search across
   transcripts.
7. **Week 7+** — Polish, code-signing, notarization, .dmg distribution,
   Sparkle auto-update.

## Relationship to WaveCode core

This is a peer client to the WaveCode core server. Other clients exist or
may arrive:

- WaveCode PWA (in the core repo) — mobile + cross-platform, casual
- WaveCode CLI (in the core repo) — scripting and CI integration
- Hypothetical: VS Code extension, iOS app, Slack bot

The contract is the **HTTP/SSE API documented in
`wavecode/docs/api.md`**. If you need to change the contract, the change
goes in the core repo first and lands in `docs/api.md`. Desktop follows.

## Why not Tauri / Electron / webview-based?

We tried Tauri + xterm.js first (preserved on the `tauri-archive`
branch). It worked but the embedded web terminal had real limitations
vs. native:
- xterm.js doesn't support Kitty/iTerm image protocols
- Heavy output (e.g. `cargo check` floods) is visibly laggier than native
- Font rendering is webview-grade, not CoreText-sharp
- OS clipboard interop has more edge cases
- macOS multi-window from Tauri is rough (focus, fullscreen, Stage Manager)

The user wanted native feel from day one. We pivoted to Swift. The Tauri
work proved out the SSH protocol shape; that knowledge transferred. The
embedded-terminal decision was the wrong one to keep.
