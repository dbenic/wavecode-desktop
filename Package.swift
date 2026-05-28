// swift-tools-version: 6.0
//
// WaveCode Desktop — native macOS client for WaveCode.
//
// Building from CLI:
//   swift build
//   swift run
//
// Or open this directory in Xcode for a full IDE experience (Xcode auto-
// detects Package.swift). For app bundle distribution (signed .app /
// .dmg) we'll add an Xcode project wrapper later — for v0, `swift run`
// is enough.

import PackageDescription

let package = Package(
    name: "WaveCodeDesktop",
    platforms: [
        // macOS 15 (Sequoia) needed for Citadel's `withTTY` bidirectional
        // TTY API. Plus modern SwiftUI / @Observable / Span. Released Oct 2024;
        // safe baseline for a 2026+ native app.
        .macOS(.v15),
    ],
    products: [
        .executable(name: "WaveCodeDesktop", targets: ["WaveCodeDesktop"]),
    ],
    dependencies: [
        // Pure-Swift SSH client — async/await native, modern, MIT.
        // We use Citadel for the high-level connection + executeCommand
        // (curl over SSH for the WaveCode API fetch). PTYs are handled
        // directly via NIOSSH because Citadel doesn't expose
        // window_change or proper controlling-terminal semantics.
        // https://github.com/orlandos-nl/Citadel
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.7.0"),

        // Apple's low-level SSH library — what Citadel wraps. We use it
        // directly for PTY channels so we can request a proper PTY with
        // terminal modes set, send SSH window_change messages on resize,
        // and avoid the `script` wrapper hack.
        //
        // Citadel pins an older fork (wellz26/swift-nio-ssh) at 0.3.x —
        // we point at the same fork at the same range so SPM resolves
        // one version of the package. When Citadel upgrades, we follow.
        // https://github.com/wellz26/swift-nio-ssh
        .package(url: "https://github.com/wellz26/swift-nio-ssh.git", from: "0.3.4"),

        // Native macOS terminal renderer using CoreText. Apache 2.0.
        // https://github.com/migueldeicaza/SwiftTerm
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "WaveCodeDesktop",
            dependencies: [
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/WaveCodeDesktop",
            swiftSettings: [
                // Use Swift 5 language mode while Citadel + SwiftTerm haven't
                // adopted strict Sendable annotations. Revisit when those
                // libraries ship Swift 6 conformances.
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "WaveCodeDesktopTests",
            dependencies: ["WaveCodeDesktop"],
            path: "Tests/WaveCodeDesktopTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
