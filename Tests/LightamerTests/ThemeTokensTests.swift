import AppKit
import SwiftUI
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// ThemeTokensTests (Plan M2-3-1 T1, AC #1) — the dark-glass token contract:
//
//   • all seven KD-1 families are in the registry, each member resolving to
//     a concrete color (no nil / placeholder)
//   • the dark ordering holds: windowBackground < cardSurface < textPrimary
//     (relative luminance over the raw sRGB components — the family reads
//     "dark base, slightly raised glass card, bright text")
//   • the stable marker surface is non-empty and single-spelled (T1 base —
//     the VIEW-level marker assertions land with T2's WorkspaceRoutingTests,
//     plan m8)
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ThemeTokensTests: XCTestCase {

    // MARK: - Component extraction

    /// The sRGB components of a token color (alpha preserved separately so
    /// ordering math sees the raw rgb).
    private func components(
        _ color: Color
    ) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        return (ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent)
    }

    /// Rec.709 weighted luma over the sRGB components (any sane formula
    /// preserves these orderings — the gaps are wide by design).
    private func luma(_ color: Color) -> Double {
        let c = components(color)
        return 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
    }

    // MARK: - AC #1: seven families in the registry, every member concrete

    func testAllSevenFamiliesAreRegistered() {
        let families = ThemeTokens.Family.allCases.map(\.rawValue)
        XCTAssertEqual(
            families.sorted(),
            [
                "accent", "busyDim", "cardBorder", "cardSurface",
                "selectedRing", "text", "windowBackground",
            ])
    }

    func testEveryFamilyMemberResolvesToAConcreteColor() {
        for family in ThemeTokens.Family.allCases {
            let members = ThemeTokens.members(of: family)
            XCTAssertFalse(
                members.isEmpty,
                "family \(family.rawValue) has no members")
            for member in members {
                let c = components(member)
                for channel in [c.red, c.green, c.blue] {
                    XCTAssertTrue(
                        channel.isFinite && channel >= 0 && channel <= 1,
                        "family \(family.rawValue) has a non-finite channel")
                }
            }
        }
    }

    func testCardSurfacesAreSemiTransparentForTheMaterialHook() {
        // The glass intent: card surfaces sit BELOW full opacity so views can
        // hang a material blur underneath; the border rim is a low-alpha rim.
        XCTAssertLessThan(
            components(ThemeTokens.cardSurface).alpha, 1.0,
            "cardSurface must stay semi-transparent (the 材质模糊挂点)")
        XCTAssertLessThan(
            components(ThemeTokens.cardBorder).alpha, 0.5,
            "cardBorder is a low-alpha hairline rim")
    }

    // MARK: - AC #1: the dark ordering (windowBackground < cardSurface <
    // textPrimary)

    func testWindowBackgroundIsDarkestAndTextBrightest() {
        let windowLuma = luma(ThemeTokens.windowBackground)
        let cardLuma = luma(ThemeTokens.cardSurface)
        let textLuma = luma(ThemeTokens.textPrimary)
        XCTAssertLessThan(
            windowLuma, cardLuma,
            "the window root must sit darker than the raised card base")
        XCTAssertLessThan(
            cardLuma, textLuma,
            "the card base must sit darker than primary text")
        XCTAssertGreaterThan(windowLuma, 0, "sanity: not pure black")
        XCTAssertLessThan(textLuma, 1, "sanity: not pure white")
    }

    func testSecondaryTextIsDimmerThanPrimary() {
        XCTAssertLessThan(
            luma(ThemeTokens.textSecondary), luma(ThemeTokens.textPrimary),
            "secondary text reads dimmer than primary text")
    }

    func testSelectedRingIsAccentFamilyBrightEnoughAgainstCardBase() {
        // The ring must out-shine the card base it draws over.
        XCTAssertGreaterThan(
            luma(ThemeTokens.selectedRing), luma(ThemeTokens.cardSurface))
        XCTAssertGreaterThan(
            luma(ThemeTokens.accent), luma(ThemeTokens.cardSurface))
    }

    // MARK: - The stable marker surface (T1 base; T2 view-level assertions
    // per plan m8)

    func testShellMarkersAreStableNonEmptySpellings() {
        XCTAssertEqual(ThemeTokens.Markers.workspaceHost, "shell.workspace.host")
        XCTAssertEqual(ThemeTokens.Markers.projectWorkspace, "library.project.workspace")
        XCTAssertFalse(ThemeTokens.Markers.workspaceHost.isEmpty)
        XCTAssertFalse(ThemeTokens.Markers.projectWorkspace.isEmpty)
    }
}
