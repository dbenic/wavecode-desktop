# WaveCode Desktop

Native desktop client for [WaveCode](https://github.com/dbenic/wavecode) — an
open-source multi-agent orchestrator for CLI coding agents.

WaveCode Desktop gives you a **tmux-first work surface** with rich desktop
affordances (drag-drop, native notifications, instant agent switching, command
palette) without giving up the SSH/tmux experience you already use. All agents
run on a remote server you control; the desktop app is a thin, fast lens on
top.

> **SSH-only by design.** WaveCode Desktop never runs agents locally — your
> laptop sleeps, your server doesn't. The app connects to a remote WaveCode
> instance over a single SSH connection that multiplexes the HTTP/SSE API,
> tmux PTYs, and SFTP file uploads.

## Status

Pre-alpha. The architecture is settled; the v0 is being built.

## What's the point?

The WaveCode web PWA is great for mobile and casual monitoring. For deep
desk work it has friction: drag-drop is finicky, you can't paste images
without ceremony, notifications are weak, switching between agents is
slower than it should be, and the dashboard sits in a browser tab that gets
suspended when your laptop sleeps.

The desktop app fixes those papercuts by treating the **real tmux session
as the work surface** and wrapping it in native chrome:

- **Drag a screenshot from Finder** → uploaded as artifact, path injected at
  the tmux cursor. One gesture instead of seven.
- **Sidebar with live agent status** — green/amber/red dots, always visible
  while you work.
- **⌘+1/2/3** — instant agent switching, faster than `tmux select-window`.
- **⌘K command palette** — spawn, dispatch, search, jump.
- **⌘F search** across all agent transcripts at once.
- **Native macOS notifications** when long-running agents finish, with reply
  actions.
- **Multi-monitor** — pin a different agent per window.
- **Multi-server** — switch between personal, staging, prod servers like
  Slack workspaces.

The web PWA stays as the mobile/anywhere surface. The desktop app is what
you reach for at your desk.

## Architecture

```
   Mac (Desktop app)                          Server (any reachable host)
┌──────────────────────────┐               ┌───────────────────────────────────┐
│  Sidebar (React)         │               │   ┌─────────────────────────┐    │
│  Terminal (xterm.js)     │               │   │ WaveCode daemon         │    │
│  SSH client (russh)      │═══════════════│═══│  Hono + SQLite + agents │    │
│   ├── HTTP port-forward  │  ONE SSH      │   └────────┬────────────────┘    │
│   ├── PTY channel        │  CONNECTION   │   ┌────────┴────────────────┐    │
│   └── SFTP channel       │               │   │  tmux sessions          │    │
└──────────────────────────┘               │   └─────────────────────────┘    │
                                           └───────────────────────────────────┘
```

One SSH connection multiplexes three channels:

1. **HTTP/SSE port-forward** — talk to the WaveCode API via `localhost:3777`
   as if it were local
2. **PTY channel** — `tmux attach` rendered in xterm.js
3. **SFTP channel** — file uploads land in agent workspaces

One auth, one connection, one trust boundary. See
[`docs/architecture.md`](docs/architecture.md) for details.

## Requirements

- macOS 14+ / Windows 10+ / Linux (modern distro)
- A running [WaveCode](https://github.com/dbenic/wavecode) server you can
  SSH into
- An `~/.ssh/config` entry for that server (or app-managed credentials)

## Building from source

See [`docs/building.md`](docs/building.md).

## Related projects

- [WaveCode](https://github.com/dbenic/wavecode) — the server / platform
- [Wavenetic](https://wavenetic.com) — the team behind WaveCode

## Contributing

Issues and PRs welcome. See `CONTRIBUTING.md` (TBA).

## License

Apache 2.0 — see [`LICENSE`](LICENSE).
