//
//  WaveTerminalView.swift
//
//  Helpers for wiring SwiftTerm.TerminalView scroll behaviour to the
//  remote application (tmux) instead of SwiftTerm's local — and in
//  tmux alt-screen mode, empty — scrollback buffer.
//
//  Why this isn't a TerminalView subclass: SwiftTerm marks
//  `scrollWheel` as `public override` (not `open`), so cross-module
//  subclasses can't override it. Workaround: install an app-local
//  NSEvent monitor for scrollWheel events; when the event lands over
//  one of our managed TerminalView instances, encode it as an xterm
//  SGR mouse event and dispatch via the TerminalViewDelegate.send
//  path (the same path keystrokes take, which then forwards to our
//  SSH PTY).
//
//  The monitor is registered/unregistered per TerminalCoordinator
//  attach/detach, so it doesn't leak across the app's lifetime.
//

import AppKit
import SwiftTerm

enum WheelForwarder {
    /// Install a local event monitor that intercepts scrollWheel events
    /// landing on `view` and forwards them to the remote app as xterm
    /// SGR mouse press events. Returns the monitor token — pass it to
    /// `uninstall` on teardown.
    static func install(on view: TerminalView) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak view] event in
            guard let view = view, view.allowMouseReporting else { return event }
            guard event.window === view.window else { return event }

            // Hit-test against the terminal view's bounds in window coords.
            let pt = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(pt) else { return event }

            // Forward to the remote and consume the event so SwiftTerm
            // doesn't also scroll its own (empty) buffer.
            sendWheel(event, in: view)
            return nil
        }
    }

    static func uninstall(_ monitor: Any?) {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }

    /// Build and send xterm SGR mouse press for a wheel event:
    ///   ESC [ < {code} ; {col} ; {row} M
    /// where code = 64 (up) or 65 (down), plus modifier flags
    /// (shift=4, meta=8, ctrl=16). Wheel events only send the press
    /// (M), not a release — matches xterm behaviour.
    private static func sendWheel(_ event: NSEvent, in view: TerminalView) {
        guard event.deltaY != 0, let delegate = view.terminalDelegate else { return }

        let baseButton = event.deltaY > 0 ? 64 : 65
        var code = baseButton
        let mods = event.modifierFlags
        if mods.contains(.shift) { code |= 4 }
        if mods.contains(.option) { code |= 8 }
        if mods.contains(.control) { code |= 16 }

        let pt = view.convert(event.locationInWindow, from: nil)
        let term = view.getTerminal()
        let cols = max(1, term.cols)
        let rows = max(1, term.rows)
        let cellW = max(1, view.bounds.width / CGFloat(cols))
        let cellH = max(1, view.bounds.height / CGFloat(rows))
        let col = max(1, min(cols, Int(pt.x / cellW) + 1))
        // NSView origin is bottom-left; terminal grid is top-left.
        let row = max(1, min(rows, Int((view.bounds.height - pt.y) / cellH) + 1))

        let seq = "\u{1B}[<\(code);\(col);\(row)M"
        let seqBytes = Array(seq.utf8)

        // Cap ticks per event so a trackpad swipe doesn't blast a
        // hundred events at tmux at once.
        let ticks = max(1, min(5, Int(abs(event.deltaY))))
        var bytes: [UInt8] = []
        bytes.reserveCapacity(seqBytes.count * ticks)
        for _ in 0..<ticks {
            bytes.append(contentsOf: seqBytes)
        }

        delegate.send(source: view, data: ArraySlice(bytes))
    }
}
