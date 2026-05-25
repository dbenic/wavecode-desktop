# Architecture

WaveCode Desktop is a **native macOS, SSH-first remote client** for a
WaveCode server. Your Mac hosts the rendering and UX; the server hosts
everything else (agents, tmux, SQLite, LLM API calls, artifact storage).

## Why SSH-only

Laptops sleep. Servers don't. The user's flow is:

1. Start agents on a server you control (Hetzner box, home server, AWS, whatever)
2. Open the desktop app, connect over SSH
3. Work for an hour, close laptop, go to dinner
4. Agents continue running on the server
5. Come back, open laptop, app reconnects, you see what happened

If we had a "local mode," step 4 would be impossible. So we don't.

## Why native (not Tauri / Electron / webview)

We tried Tauri + xterm.js first (preserved on the `tauri-archive`
branch). It worked end-to-end and shipped a real v0. But the embedded
web terminal had ceiling limitations vs. native:

- xterm.js doesn't support Kitty/iTerm image protocols
- Heavy output is visibly laggy compared to CoreText rendering
- macOS multi-window from Tauri has rough edges
- OS clipboard, fonts, scrolling feel webby

The point of the app is the **premium native macOS experience**. SwiftUI
+ SwiftTerm gets us there; Tauri couldn't.

## The one connection

One SSH connection per active server profile. That connection multiplexes:

```
┌─────────────────── SSH session ───────────────────┐
│                                                   │
│  Channel 1: TCP port-forward (HTTP/SSE)           │
│    localhost:<dyn-port> → server:3777             │
│    Used by: WaveCodeAPI + SSEClient (URLSession)  │
│                                                   │
│  Channel 2..N: PTY channels                       │
│    Each runs `tmux attach -t <session>`           │
│    Used by: TerminalCoordinator → SwiftTerm       │
│                                                   │
│  Channel N+1: SFTP                                │
│    Used by: drag-drop file uploads                │
│                                                   │
└───────────────────────────────────────────────────┘
```

One auth, one trust boundary, one reconnect surface.

## Process model

```
                Desktop App (one Swift process)
              ┌─────────────────────────────────┐
              │  Main window (NSWindow)          │
              │    SwiftUI + AppKit                │
              │                                    │
              │  Per-agent windows (NSWindow × N)  │
              │    SwiftTerm in NSViewRepresentable│
              │                                    │
              │  Settings window                   │
              │                                    │
              │  Citadel SSH client (singleton)    │
              │    ├ port forward                  │
              │    ├ PTY channels                  │
              │    └ SFTP client                   │
              └─────────────────────────────────┘
                          ║
                          ║  SSH (TCP 22)
                          ║
              ┌─────────────────────────────────┐
              │  Server (any reachable host)    │
              │    sshd                         │
              │     ├ port forward → 3777      │
              │     ├ tmux server (sessions)   │
              │     └ sftp subsystem           │
              │                                 │
              │  WaveCode daemon                │
              │    Hono + SQLite                │
              │                                 │
              │  Agents (tmux sessions)          │
              │    Claude Code / Codex / Aider   │
              └─────────────────────────────────┘
```

## State ownership

| State | Lives | Why |
|---|---|---|
| Agents, tasks, artifacts, runs | Server (SQLite) | Source of truth |
| Tmux sessions | Server | Survive laptop sleep |
| LLM API keys | Server (`config.yaml`) | Never on the laptop |
| Discovery / QA reports | Server (filesystem) | Where agents read them |
| Active server, active agent, sidebar state | Desktop (`@Observable AppState`) | Transient UI prefs |
| Server profiles | UserDefaults + Keychain | Per-user |
| Bearer tokens | macOS Keychain | Sensitive |

## Reconnect lifecycle

```
              CONNECTED
                  │
        network/sleep death
                  ↓
              ERROR ─────────────┐
                  │              │
            backoff retry        │ user clicks
            (0.5s, 1s, 2s, 5s,    │ "reconnect"
             10s, 30s)            │
                  │              │
                  ↓              │
            RECONNECTING ←───────┘
                  │
            ssh handshake ok
                  ↓
            re-fetch agent list, re-attach PTYs
                  ↓
              CONNECTED
```

Tmux sessions on the server keep running through all of this.
Re-attaching after reconnect is loss-free.

## Drag-drop pipeline (the hero feature)

```
1. User drops file(s) on app window
   ↓
2. SwiftUI .onDrop catches NSItemProvider(s)
   ↓
3. ConnectionManager.shared.upload(paths, toAgent: id)
   ↓
4. SFTPClient.put(local → server staging dir)
   ↓
5. POST /api/artifacts/upload (via port-forwarded HTTP)
   ↓
6. SSH exec: tmux send-keys -t <session> "<artifact_path>"
   ↓
7. SwiftTerm shows the path landing at the cursor
```

End-to-end target: <500 ms for a typical screenshot.

## What this app deliberately does NOT do

- **Run agents locally** — see the SSH-only rationale
- **Hold LLM API keys** — they live on the server
- **Implement a terminal** — SwiftTerm handles ANSI/escape sequences
- **Cache server data persistently** — server is source of truth, SSE drives UI
- **Support offline mode** — if SSH is down, the app shows "reconnecting"
- **Manage agent lifecycle independently** — every action flows through the WaveCode API
- **Run on Windows / Linux** — the web PWA in the core repo is the cross-platform answer

## Multi-server, multi-user, team mode (future)

Once the single-server case works, multi-server falls out almost for free
(multiple SSH connections, one selected as active). Multi-user (multiple
Macs connecting to the same server) requires no special logic — the
server already broadcasts SSE events to every connected client.

This is the long-game payoff of SSH-first: collaboration becomes
"everyone SSH into the same box," which already works.
