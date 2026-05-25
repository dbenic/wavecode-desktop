# Building from source

## Prerequisites

| Tool | Version | Why |
|---|---|---|
| Node.js | 22+ | Frontend toolchain (Vite, TS, React) |
| Rust | 1.77+ stable | Tauri shell + SSH client |
| Xcode CLI tools | macOS only | Code-signing + native deps |
| `pkg-config`, `libgtk` etc. | Linux only | Tauri webview deps |
| WiX 3.x | Windows only | MSI bundling |

Install Rust:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

Install Node deps:

```sh
npm install
```

## Run in dev mode

```sh
npm run tauri:dev
```

This starts Vite on `http://localhost:1420`, compiles the Rust shell, and
opens a native window. Hot-reload works for both React (instant) and Rust
(rebuild + restart).

## Production build

```sh
npm run tauri:build
```

Outputs into `src-tauri/target/release/bundle/`:

- `macos/WaveCode Desktop.app` (+ `.dmg`)
- `msi/WaveCode-Desktop_x.y.z_x64_en-US.msi` (Windows)
- `appimage/`, `deb/` (Linux)

## Code-signing (macOS)

For distribution outside the App Store you need a Developer ID Application
certificate ($99/yr) and to notarize the build:

```sh
export APPLE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_PASSWORD="@keychain:AC_PASSWORD"
export APPLE_TEAM_ID="TEAMID"
npm run tauri:build
```

Tauri will sign + notarize during the bundle step.

## CI

The repo ships a GitHub Actions workflow at `.github/workflows/release.yml`
(TBA) that triggers on tags `v*.*.*` and produces signed artifacts for
macOS, Windows, and Linux as a GitHub Release.

## Running against a local WaveCode server (for development)

When developing the app you usually want to connect to a local WaveCode
daemon rather than a remote server. Two options:

**Option A — run WaveCode locally** in the sibling `WaveCode/` repo:

```sh
cd ../WaveCode && npm run dev
```

Then add a profile in WaveCode Desktop with `ssh_host: localhost`. You
SSH to your own machine via loopback. Make sure `sshd` is enabled in
System Settings → Sharing → Remote Login.

**Option B — port-forward to a real WaveCode server.** Works fine; just
slower iteration when you also need to change server code.

Recommended for v0 dev: Option A.
