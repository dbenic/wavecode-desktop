# Architecture

WaveCode Desktop is an **SSH-first remote client** for a WaveCode server.
The user's laptop hosts the rendering and user-facing UX; the server hosts
everything else (agents, tmux, SQLite, LLM API calls, artifact storage).

## Why SSH-only

Laptops sleep. Servers don't. The user's flow is:

1. Start agents on a server you control (Hetzner box, home server, AWS, whatever)
2. Open the desktop app, connect over SSH
3. Work for an hour, close laptop, go to dinner
4. Agents continue running on the server
5. Come back, open laptop, app reconnects, you see what happened

If we had a "local mode," step 4 would be impossible. So we don't.

## The one connection

One process-wide SSH connection per active server profile. That connection
multiplexes:

```
┌─────────────────── SSH session ───────────────────┐
│                                                   │
│  Channel 1: TCP port-forward (HTTP/SSE)           │
│    localhost:<dyn-port> → server:3777             │
│    Used by: React frontend for /api/* + /events    │
│                                                   │
│  Channel 2..N: PTY channels                       │
│    Each runs `tmux attach -t <session>`           │
│    Used by: TerminalView (xterm.js)               │
│                                                   │
│  Channel N+1: SFTP                                │
│    Used by: drag-drop file uploads                │
│                                                   │
└───────────────────────────────────────────────────┘
```

One auth, one trust boundary, one reconnect surface.

## Process model

```
                Desktop App (Tauri process)
              ┌─────────────────────────────────┐
              │  WebView (React + xterm.js)     │
              │    ↕ invoke / emit              │
              │  Rust core                      │
              │    ├─ ssh::SshConnection        │
              │    │     └─ russh::client       │
              │    ├─ port_forward task          │
              │    ├─ pty channels (N)           │
              │    └─ sftp client                │
              └─────────────────────────────────┘
                          ║
                          ║  SSH (TCP 22)
                          ║
              ┌─────────────────────────────────┐
              │  Server (any reachable host)    │
              │    sshd                         │
              │     ├─ port forward → 3777      │
              │     ├─ tmux server (sessions)   │
              │     └─ sftp subsystem           │
              │                                 │
              │  WaveCode daemon                │
              │    Hono + SQLite                │
              │    spawns / monitors agents     │
              │    serves /api/* + /events       │
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
| Discovery / QA reports | Server (filesystem) | Where agents can read them |
| Active server, active agent, sidebar state | Desktop (Zustand) | Transient UI prefs |
| Server profiles (SSH config) | Desktop (config dir) | Per-user |
| Bearer tokens | macOS Keychain / equivalent | Sensitive |

## Reconnect lifecycle

The single most important quality bar.

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

Tmux sessions on the server keep running through all of this. Re-attaching
after reconnect is loss-free — the user sees the same scrollback they would
have seen if they'd never disconnected.

## Drag-drop pipeline (the hero feature)

```
1. User drops file(s) on window
   ↓
2. JS: DropOverlay catches `drop` event with file paths
   ↓
3. JS: invoke('upload_files', { agent_id, paths })
   ↓
4. Rust: sftp.put(local_path → server staging dir)
   ↓
5. Rust: POST /api/artifacts/upload (via port-forward)
   ↓
6. Rust: tmux send-keys "<artifact_path>" to active pane
   ↓
7. JS: terminal shows the path landing at the cursor
```

End-to-end target: <500 ms for a typical screenshot (~500 KB).

## What this app deliberately does NOT do

- **Run agents locally** — see the SSH-only rationale
- **Hold LLM API keys** — they live on the server in `config.yaml`
- **Implement a terminal** — xterm.js handles ANSI/escape sequences
- **Cache server data persistently** — server is source of truth, SSE drives UI
- **Support offline mode** — there is no offline mode; if SSH is down, the app shows "reconnecting"
- **Manage agent lifecycle independently** — every action flows through the WaveCode API

## Multi-server, multi-user, team mode (future)

Once the single-server case works, multi-server falls out almost for free
(it's just multiple SSH connections, one selected as active). Multi-user
(multiple Macs connecting to the same server) also requires no special
logic — the server already broadcasts SSE events to every connected client.

This is the long-game payoff of SSH-first: collaboration becomes
"everyone SSH into the same box," which already works.
