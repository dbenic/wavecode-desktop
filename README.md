# WaveCode Desktop

Premium native macOS client for [WaveCode](https://github.com/dbenic/wavecode) —
an open-source multi-agent orchestrator for CLI coding agents.

Built in Swift / SwiftUI with **SwiftTerm** (CoreText-rendered native
terminal) and **Citadel** (pure-Swift SSH). No Electron, no webview, no
xterm.js. The terminal feels like Terminal.app / Ghostty / iTerm — because
it's rendered the same way they are.

> **SSH-only by design.** WaveCode Desktop never runs agents locally —
> your laptop sleeps, your server doesn't. One SSH connection multiplexes
> the WaveCode HTTP/SSE API, tmux PTYs, and SFTP file uploads.
>
> **One app, multiple windows.** Per-agent terminal windows can be opened
> across multiple monitors. The control window stays focused on what
> matters: agents, artifacts, drop zone, palette.

## Status

Pre-alpha. v0 scaffold is in place; the SSH/PTY foundation lands in
week 1, multi-window per agent + drag-drop in week 2-3.

## Why a native Mac app

The WaveCode web PWA is good for mobile and casual monitoring. For deep
desk work it has friction: drag-drop is finicky, you can't paste images
without ceremony, notifications are weak, the terminal lags under heavy
output, and the dashboard sits in a browser tab that gets suspended when
your laptop sleeps.

The native macOS app fixes that by:

- **CoreText terminal rendering** — sharp HiDPI fonts, real OS clipboard,
  smooth scrolling under heavy output, native selection
- **Multi-window** — open each agent in its own NSWindow, spread across
  monitors, tabbed natively
- **Drag screenshot from Finder** → uploaded as artifact, path injected
  at the tmux cursor
- **Sidebar with live agent status** — green/amber/red dots driven by
  SSE, always visible
- **⌘K command palette** — spawn, dispatch, search, jump
- **Native macOS notifications** with reply actions when agents finish
- **Spotlight indexing** of agent transcripts (later)
- **Native menu bar status app** (later) — ambient awareness without
  needing the main window open

The web PWA stays as the mobile/anywhere surface. The native app is what
you reach for at your desk.

## Architecture

```
   Your Mac                                   Server (any reachable host)
┌─────────────────────────────┐             ┌──────────────────────────────┐
│  SwiftUI app                │             │   ┌──────────────────────┐   │
│   ├ Main window             │             │   │  WaveCode daemon     │   │
│   │   ├ Sidebar (agents)    │             │   │  Hono + SQLite       │   │
│   │   └ Workspace pane      │             │   └──────────┬───────────┘   │
│   ├ Per-agent windows       │             │              │                │
│   │   (SwiftTerm × N)       │             │   ┌──────────┴───────────┐   │
│   └ Settings, palette       │             │   │  tmux sessions       │   │
│                             │             │   │   - cl-backend        │   │
│  Citadel SSH client         │═════════════│═══│   - cl-api            │   │
│   ├ Port-forward → :3777    │  ONE SSH    │   │   - codex-tests       │   │
│   ├ PTY channels (per agent)│  CONNECTION │   │   ...                 │   │
│   └ SFTP (drag-drop)        │             │   └──────────────────────┘   │
└─────────────────────────────┘             └──────────────────────────────┘
```

One SSH connection multiplexes three channels — see
[`docs/architecture.md`](docs/architecture.md) for the full design.

## Requirements

- **macOS 14 (Sonoma)** or later
- A running [WaveCode](https://github.com/dbenic/wavecode) server you can
  SSH into
- An `~/.ssh/config` entry for that server, or app-managed credentials

## Building

```sh
git clone https://github.com/dbenic/wavecode-desktop.git
cd wavecode-desktop
swift run
```

For Xcode IDE experience: open the directory in Xcode (auto-detects
`Package.swift`).

See [`docs/building.md`](docs/building.md) for code-signing and
distribution setup.

## Cross-platform

WaveCode Desktop is macOS-only by design — it leans hard into native
AppKit/SwiftUI and CoreText for the premium feel.

Linux and Windows users:

- The [WaveCode web PWA](https://github.com/dbenic/wavecode) (bundled in
  the core repo) is the cross-platform answer — runs in any modern
  browser, mobile-friendly.
- A Tauri+xterm.js reference implementation lives on the
  [`tauri-archive` branch](https://github.com/dbenic/wavecode-desktop/tree/tauri-archive)
  of this repo (tagged `v0.0.1-tauri`). It's not maintained but works
  cross-platform if you want to fork it.

## Related projects

- [WaveCode](https://github.com/dbenic/wavecode) — the server / platform
- [Wavenetic](https://wavenetic.com) — the team behind WaveCode

## Contributing

Issues and PRs welcome. See `CONTRIBUTING.md` (TBA).

## License

Apache 2.0 — see [`LICENSE`](LICENSE).
