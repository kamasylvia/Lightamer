import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ThemeTokens (Plan M2-3-1 T1, KD-1 / D-M2-3-CONTEXT-1) — the DARK-GLASS
// color family of the NEW shell, the SINGLE color source for every view
// under `UI/Shell/` and the M2-3 library faces (P2 grid / Inspector / search
// dialog). The legacy tree keeps consuming `LightamerColors` — the two
// palettes coexist with ZERO cross-references (KD-1: 并存零迁移).
//
// VALUE PROVENANCE (the D1 red line): every number below is SELF-WRITTEN to
// the "dark, low-contrast, glass card" visual intent — Alcedo's DESIGN.md
// values are GPL and are NEVER copied value-for-value (OQ-1 A). The family
// is deliberately blue-shifted like the legacy neutrals (a photo editor's
// chrome must not bias white-balance judgment) and every card surface is
// semi-transparent so consumers can drop a `.regularMaterial`/`.ultraThinMaterial`
// blur underneath (the 材质模糊挂点).
//
// BARE-HEX EXEMPTION: this file is the ONLY file in the new-shell tree
// (`UI/Shell/` + `UI/Theme/` + `Library/`) allowed to carry `#RRGGBB`
// literals — the T1 machine check greps the tree and asserts this file is
// the sole hit.
// ─────────────────────────────────────────────────────────────────────────────

enum ThemeTokens {

    // ───────── The seven glass families (KD-1) ─────────

    /// Deep cool near-black — the window root / editor workspace surround.
    static let windowBackground = rgba(0x0B0D11, alpha: 1.0)

    /// Semi-transparent raised card base — layer over a material blur for
    /// the glass read (the alpha IS the intent; rgb stands alone darker than
    /// text, brighter than the window root).
    static let cardSurface = rgba(0x171B22, alpha: 0.80)

    /// Cool light hairline at low alpha — the glass card rim.
    static let cardBorder = rgba(0x93A7C4, alpha: 0.18)

    /// Default text on glass surfaces.
    static let textPrimary = rgba(0xE7EAF0, alpha: 1.0)

    /// Metadata captions, placeholders, secondary labels.
    static let textSecondary = rgba(0x9AA3B2, alpha: 1.0)

    /// Selection / active / focus — a cool blue written for the dark glass
    /// family (not the system accent: the shell's identity color).
    static let accent = rgba(0x5E9BFF, alpha: 1.0)

    /// The selected thumbnail ring (library grid / filmstrip) — a lighter
    /// accent-family blue so the ring reads against both the card base and
    /// the window root.
    static let selectedRing = rgba(0x9CC2FF, alpha: 0.90)

    /// Busy-state scrim (two-level busy, task-dialog dim).
    static let busyDim = rgba(0x000000, alpha: 0.45)

    // MARK: - Family registry (the AC-1 completeness face)

    /// The seven token families (KD-1). New tokens MUST join a family here —
    /// the T1 completeness test iterates exactly these keys, and the bare-hex
    /// grep exemption presumes this file stays the single color locale.
    enum Family: String, CaseIterable, Sendable {
        case cardSurface
        case cardBorder
        case windowBackground
        case text
        case accent
        case selectedRing
        case busyDim
    }

    /// Family → its member tokens (field-structured; the tests assert the
    /// seven keys and that every member resolves to a concrete color).
    static func members(of family: Family) -> [Color] {
        switch family {
        case .cardSurface: [cardSurface]
        case .cardBorder: [cardBorder]
        case .windowBackground: [windowBackground]
        case .text: [textPrimary, textSecondary]
        case .accent: [accent]
        case .selectedRing: [selectedRing]
        case .busyDim: [busyDim]
        }
    }

    // MARK: - Stable marker surface (T1 base; view-level assertions land
    // with T2's WorkspaceRoutingTests — plan m8)

    /// The shell's accessibility identifiers, single-sourced here so the T2
    /// views and their tests quote ONE spelling.
    enum Markers {
        /// The gate=false shell root (WorkspaceHostView).
        static let workspaceHost = "shell.workspace.host"
        /// The library face / project workspace container (kept from M2-2-4).
        static let projectWorkspace = "library.project.workspace"
    }

    // MARK: - Helpers

    /// `0xRRGGBB` + alpha → sRGB `Color`. Self-written values only (D1).
    private static func rgba(_ hex: UInt32, alpha: Double) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
