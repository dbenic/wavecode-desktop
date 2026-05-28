//
//  WaveColors.swift
//
//  The WaveCode Desktop palette. Centralized so we never end up with
//  three slightly-different "near-black" colors scattered across views.
//
//  Design principles:
//    - Match the terminal's slate-950 base. The whole window reads as
//      one dark surface, not "sidebar + main".
//    - Use opacity, not new colors, for hover / press / divider states.
//    - Accent (emerald) used sparingly — only for "active" affordances
//      and status indicators. Never as decoration.
//    - Three text tiers: primary (readable headlines, agent names),
//      secondary (counts, helper text), tertiary (timestamps, hints).
//

import SwiftUI

enum WaveColors {
    // Surfaces
    static let chrome     = Color(red: 0.043, green: 0.063, blue: 0.118)   // slate-950-ish (sidebar/toolbar)
    static let terminal   = Color(red: 0.008, green: 0.024, blue: 0.090)   // slate-950 (terminal area)
    static let activeBg   = Color.white.opacity(0.06)                       // subtle row highlight
    static let hoverBg    = Color.white.opacity(0.03)
    static let divider    = Color.white.opacity(0.06)

    // Text tiers
    static let primary    = Color(red: 0.886, green: 0.910, blue: 0.941)   // slate-200
    static let secondary  = Color(red: 0.580, green: 0.639, blue: 0.722)   // slate-400
    static let tertiary   = Color(red: 0.392, green: 0.455, blue: 0.545)   // slate-500
    static let muted      = Color(red: 0.282, green: 0.333, blue: 0.412)   // slate-600

    // Accent
    static let accent     = Color(red: 0.063, green: 0.725, blue: 0.506)   // emerald-500
    static let accentDim  = Color(red: 0.063, green: 0.725, blue: 0.506).opacity(0.6)

    // Status
    static let statusWorking = accent
    static let statusIdle    = tertiary
    static let statusError   = Color(red: 0.937, green: 0.267, blue: 0.267) // red-500
    static let statusWarn    = Color(red: 0.961, green: 0.620, blue: 0.043) // amber-500
}
