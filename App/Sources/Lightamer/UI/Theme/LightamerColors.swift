import SwiftUI

/// Lightamer design-system color tokens (UI-SPEC "Color" — the contract all
/// phases inherit; do not invent new tokens downstream).
///
/// Dark-mode-first (D-10 forces dark). Neutrals are slightly blue-shifted
/// (hue 240-255, saturation <= 6%) so the chrome reads as perceptually
/// neutral gray — a photo editor's chrome must not bias white-balance
/// judgment. Accent/danger/warning/success deliberately use system colors per
/// UI-SPEC Accent Discipline.
internal enum LightamerColors {

    // ───────── Neutral scale (dark-mode hex values from UI-SPEC) ─────────

    /// neutral-0 `#0E0E10` — window background; editor canvas surround.
    static let neutral0 = color(0x0E0E10)
    /// neutral-1 `#161619` — editor area background (the "mat").
    static let neutral1 = color(0x161619)
    /// neutral-2 `#1E1E22` — sidebar / inspector panel background.
    static let neutral2 = color(0x1E1E22)
    /// neutral-3 `#26262B` — raised surface (inspector sections, toolbar).
    static let neutral3 = color(0x26262B)
    /// neutral-4 `#303035` — control backgrounds, slider tracks.
    static let neutral4 = color(0x303035)
    /// neutral-5 `#3A3A40` — hover states on rows / buttons.
    static let neutral5 = color(0x3A3A40)
    /// neutral-6 `#3F3F45` — hairline borders between regions.
    static let neutral6 = color(0x3F3F45)
    /// neutral-7 `#4A4A52` — strong borders around the editor canvas.
    static let neutral7 = color(0x4A4A52)

    // ───────── Text ─────────

    /// `#ECECEE` — default text on dark surfaces.
    static let textPrimary = color(0xECECEE)
    /// `#9A9AA0` — metadata captions, placeholder text.
    static let textSecondary = color(0x9A9AA0)
    /// `#6E6E76` — disabled controls, "no value" readouts.
    static let textTertiary = color(0x6E6E76)
    /// `#FFFFFF` — text rendered on accent-color fills.
    static let textOnAccent = color(0xFFFFFF)

    // ───────── Semantic surfaces ─────────

    /// Window root (neutral-0).
    static let background = neutral0
    /// Editor area surround (neutral-1).
    static let canvas = neutral1
    /// Sidebar / inspector / toolbar surface (neutral-2; raised = neutral3).
    static let surface = neutral2
    /// Raised surface (neutral-3).
    static let surfaceRaised = neutral3
    /// Hairline separators (neutral-6).
    static let border = neutral6
    /// Canvas edge (neutral-7).
    static let borderStrong = neutral7

    // ───────── Accent / status (system colors per UI-SPEC) ─────────

    /// Selection / active / focused — system blue via `.accentColor`.
    static let accent = Color.accentColor
    /// Destructive actions only — system red.
    static let danger = Color.red
    /// Out-of-gamut warnings, unsaved-state — system orange.
    static let warning = Color.orange
    /// Decode-complete / export success — system green.
    static let success = Color.green

    // ───────── Helpers ─────────

    /// `0xRRGGBB` literal to `Color` (sRGB values from the UI-SPEC tables).
    private static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
