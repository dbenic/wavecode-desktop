//
//  TerminalPrefs.swift
//
//  Persisted terminal display preferences (font, size, line spacing).
//  Lives separately from per-server profiles because it applies to the
//  whole app, not any one connection.
//
//  Persistence: UserDefaults. Defaults sized for "feels iTerm-sharp"
//  on a Retina display.
//

import Foundation
import AppKit
import Observation
import OSLog

@MainActor
@Observable
final class TerminalPrefs {
    private let log = OSLogger.terminal

    var fontFamily: String {
        didSet { save() }
    }
    var fontSize: CGFloat {
        didSet { save() }
    }

    init() {
        let defaults = UserDefaults.standard
        self.fontFamily = defaults.string(forKey: Keys.fontFamily) ?? Self.defaultFontFamily
        self.fontSize = CGFloat(defaults.double(forKey: Keys.fontSize)).nonZero ?? Self.defaultFontSize
    }

    /// Build an NSFont from the current preferences with sensible
    /// fallbacks: try the named family first, then SF Mono, then any
    /// monospaced system font. Never returns nil.
    func makeFont() -> NSFont {
        if fontFamily != Self.systemMonoSentinel,
           let f = NSFont(name: fontFamily, size: fontSize) {
            return f
        }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    // MARK: - Mutations with bounds

    func increaseSize() { setSize(fontSize + 1) }
    func decreaseSize() { setSize(fontSize - 1) }
    func resetSize() { setSize(Self.defaultFontSize) }
    func setSize(_ size: CGFloat) {
        fontSize = max(8, min(36, size))
    }

    // MARK: - Catalog

    /// Curated list of monospaced fonts likely to be installed on macOS,
    /// for a quick-pick UI. "System" maps to NSFont.monospacedSystemFont
    /// (== SF Mono).
    static let suggestedFonts: [String] = [
        systemMonoSentinel,
        "Menlo",
        "Monaco",
        "Courier New",
        "JetBrains Mono",
        "Fira Code",
        "Cascadia Mono",
        "MonoLisa",
        "IBM Plex Mono",
    ]

    static let systemMonoSentinel = "System (SF Mono)"
    static let defaultFontFamily = systemMonoSentinel
    static let defaultFontSize: CGFloat = 14

    // MARK: - Persistence

    private func save() {
        let d = UserDefaults.standard
        d.set(fontFamily, forKey: Keys.fontFamily)
        d.set(Double(fontSize), forKey: Keys.fontSize)
    }

    private enum Keys {
        static let fontFamily = "wavecode.terminal.fontFamily.v1"
        static let fontSize = "wavecode.terminal.fontSize.v1"
    }
}

private extension CGFloat {
    /// Returns nil if zero (treated as "not set" from UserDefaults default).
    var nonZero: CGFloat? { self == 0 ? nil : self }
}

// Single shared logger so we don't import os everywhere.
enum OSLogger {
    static let terminal = Logger(subsystem: "com.wavenetic.wavecode-desktop", category: "terminal")
}
