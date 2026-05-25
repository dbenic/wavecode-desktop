// swift-tools-version: 5.10
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
        .macOS(.v14), // Sonoma+ for modern SwiftUI + @Observable
    ],
    products: [
        .executable(name: "WaveCodeDesktop", targets: ["WaveCodeDesktop"]),
    ],
    dependencies: [
        // Pure-Swift SSH client — async/await native, modern, MIT.
        // https://github.com/orlandos-nl/Citadel
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.7.0"),

        // Native macOS terminal renderer using CoreText. Apache 2.0.
        // https://github.com/migueldeicaza/SwiftTerm
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "WaveCodeDesktop",
            dependencies: [
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/WaveCodeDesktop"
        ),
        .testTarget(
            name: "WaveCodeDesktopTests",
            dependencies: ["WaveCodeDesktop"],
            path: "Tests/WaveCodeDesktopTests"
        ),
    ]
)
