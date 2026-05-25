# Building from source

## Prerequisites

| Tool | Version | Why |
|---|---|---|
| macOS | 14 (Sonoma) or later | Min platform target |
| Xcode | 15.0+ | Swift 5.10+ toolchain, AppKit/SwiftUI headers |
| Xcode Command Line Tools | matching Xcode | `swift`, `xcodebuild` from CLI |

Verify:

```sh
swift --version       # >= 5.10
xcodebuild -version   # Xcode 15+
```

## Run in dev mode

```sh
git clone https://github.com/dbenic/wavecode-desktop.git
cd wavecode-desktop
swift run
```

First build downloads dependencies (SwiftTerm, Citadel + transitive
NIO/Crypto stack). Subsequent builds are fast.

## Open in Xcode

Xcode auto-detects `Package.swift`:

```sh
open Package.swift
```

You get full IDE: source navigator, breakpoints, live previews for
SwiftUI views, profiling, the works.

## Running tests

```sh
swift test
```

## Production build

For a signed `.app` bundle suitable for distribution, we'll add an
Xcode project wrapper in week 7. For now, `swift build -c release`
produces an executable at `.build/release/WaveCodeDesktop` that runs
but isn't a proper app bundle (no Info.plist, no app icon, no
code-signing).

## Code-signing & notarization (future)

For distribution outside the App Store you need:
- Developer ID Application certificate ($99/yr)
- Notarization via `notarytool`

The Xcode project wrapper (TBA in week 7) will codify this.

## Running against a local WaveCode server

When developing the app, easiest path: run WaveCode locally and add a
profile pointing at `localhost`.

```sh
# In the sibling WaveCode/ repo:
cd ../wavecode
npm run dev

# Then in the Desktop Settings, configure:
#   SSH host: localhost
#   SSH port: 22 (System Settings → Sharing → Remote Login must be on)
#   WaveCode port: 3777
```

Alternatively, just point the default `wave` profile at your real
WaveCode server.
