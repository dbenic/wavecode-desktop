# WaveCode Desktop — Project Instructions

> If you are an AI agent working on this codebase, read this first. These
> rules shape every architectural decision and override any default
> behaviour.

## What this is

A native desktop client for [WaveCode](https://github.com/dbenic/wavecode).
The desktop app is **a client of a remote WaveCode server**, not a local
runtime for agents.

## Non-negotiable architectural constraints

### 1. SSH-only. No local mode. Ever.

The desktop app never runs WaveCode locally, never spawns agents on the
user's machine, never calls the Anthropic/OpenAI APIs directly. All work
happens on a remote server the user controls. The app connects over a
single SSH connection that multiplexes three channels:

- **Port-forwarded HTTP/SSE** (`localhost:3777` → server's WaveCode daemon)
- **PTY channel** for `tmux attach` rendered in xterm.js
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

The terminal area of the app embeds a real PTY connected to a real tmux
session on the server. We don't reimplement terminal logic, don't fake
the cursor, don't replace tmux's window/pane model with our own. The
sidebar and chrome are *additive* — they let you switch agents, drop
files, search, etc. — but every action ultimately translates to a real
operation on the real tmux session.

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

### 5. Cross-platform from day one.

Tauri + xterm.js + React works on macOS, Windows, and Linux. Don't write
macOS-only code paths unless the alternative is genuinely impossible. If
you find yourself reaching for AppKit-only APIs, find the Tauri or
web-platform equivalent first.

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| Shell | Tauri 2.x | Native windows + native APIs, ~15 MB binary, cross-platform |
| Native logic | Rust | Tauri requirement; needed for SSH layer anyway |
| SSH | `russh` + `russh-keys` + `russh-sftp` | Modern async Rust SSH stack |
| UI | React 19 + TypeScript | Reuse skills/components from WaveCode core PWA |
| Terminal | xterm.js + addon-fit + addon-search | Industry standard (VS Code, Warp use it) |
| Styling | Tailwind CSS | Same as WaveCode core; no custom CSS files |
| State | Zustand for UI, server is source of truth for everything else | Minimal |
| Command palette | `cmdk` | Battle-tested headless component |
| Notifications | `tauri-plugin-notification` | Native per-OS |
| Global hotkeys | `tauri-plugin-global-shortcut` | ⌘+1..9, ⌘K, ⌘N, ⌘F |
| Auto-update | `tauri-plugin-updater` | GitHub Releases as the channel |

## Project layout (target)

```
wavecode-desktop/
├── src-tauri/              Rust + Tauri shell
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   └── src/
│       ├── main.rs
│       ├── ssh.rs          russh client + reconnect loop
│       ├── pty.rs          PTY channel management (one per agent view)
│       ├── port_forward.rs HTTP API tunnel
│       ├── sftp.rs         drag-drop uploads
│       └── commands.rs     Tauri command bridge (frontend ↔ Rust)
├── src/                    React frontend
│   ├── main.tsx
│   ├── App.tsx
│   ├── components/
│   ├── hooks/
│   ├── stores/
│   ├── types/api.ts        hand-copied from WaveCode core (v0 only)
│   └── styles/tailwind.css
├── docs/
│   ├── architecture.md
│   ├── building.md
│   └── distribution.md
└── scripts/
```

## Conventions

- **IDs**: agents/tasks/etc come from the server pre-formed (ULIDs). Don't generate locally.
- **Errors**: never throw from async Rust commands. Return `Result<T, String>` and surface to the React side as toasts/inline errors.
- **Logging**: `tracing` on the Rust side, `console` for now on the React side.
- **File paths**: always `std::path::PathBuf` in Rust, `path.join` / `URL` in TS. No string concat.
- **Tests**: cargo test on Rust, vitest on TS. Co-locate tests with source.
- **CSS**: Tailwind utility classes only. No custom CSS files (mirrors WaveCode core).
- **Naming**: snake_case Rust, camelCase TS variables, PascalCase TS components, kebab-case files.

## What NOT to do

- ❌ Don't add a local SQLite or any local persistent state beyond UI prefs.
- ❌ Don't add an LLM SDK dependency to the desktop. LLM calls happen on the server.
- ❌ Don't reimplement terminal logic. Use xterm.js as-is.
- ❌ Don't build a "local agent mode" or "offline mode" — see constraint #1.
- ❌ Don't import from the WaveCode core repo directly. Hand-copy types for v0; formalize a published `@wavecode/api-types` package later.
- ❌ Don't add a custom title bar in v0. Use native macOS chrome.
- ❌ Don't use `localStorage` for anything sensitive. macOS Keychain for tokens, plain config files for non-sensitive UI prefs.
- ❌ Don't write CSS files. Tailwind only.

## Build order (v0)

1. **Week 1**: Tauri window + russh SSH connection + xterm.js rendering one
   attached tmux session.
2. **Week 2**: HTTP port-forward + React sidebar consuming SSE + agent
   switching via `tmux select-window`.
3. **Week 3**: Drag-drop → SFTP upload → artifact API → path injection at
   cursor. **(Hero demo.)**
4. **Week 4**: Multi-server profile management + robust reconnect across
   sleep/wake.
5. **Week 5–6**: ⌘K palette, ⌘F search, native notifications,
   code-signing, GitHub Releases pipeline.

## Relationship to WaveCode core

The two repos are peers. Core is the platform; Desktop is one client of
many. Other clients that may exist or arrive:

- WaveCode PWA (in the core repo) — mobile-friendly, casual monitoring
- WaveCode CLI (in the core repo) — scripting and CI integration
- Hypothetical: VS Code extension, iOS app, Slack bot, etc.

The contract between them is **the HTTP/SSE API documented in
`wavecode/docs/api.md`**. If you need to change the contract, the change
goes in the core repo first and lands in `docs/api.md`. Desktop follows.
