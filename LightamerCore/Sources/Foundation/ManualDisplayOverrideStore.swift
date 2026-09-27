import AppKit
import CoreGraphics
import Foundation

// Plan 13-2 T6 — the manual per-display profile override (COLOR-03, the
// `DisplayProfile` header's Phase 13 preview landed): a hand-picked ICC
// replaces ONE display's auto resolution. The override walks the
// `.colorSyncFallback` precise leg, and the ICC BYTES are the identity
// (the stableID hashes them — `MultiDisplayProfileTests` pins the byte
// identity), so the documented sRGB workalike approximation of the
// fallback leg does not apply to a hand-picked profile (the exact-TRC
// ruling; see `DisplayProfile.linearCGColorSpace`).
//
// Storage: UserDefaults (displayID → ICC file path). A display's ID is the
// CGDirectDisplayID from its device description — stable across launches
// for a given physical connector; a stale entry (display gone / file gone)
// resolves to NO override (graceful, logged once by the caller).
/// `@unchecked Sendable`: UserDefaults is a thread-safe CF type (the same
/// immutability-in-practice contract the CGColorSpace payloads ride).
public struct ManualDisplayOverrideStore: @unchecked Sendable {

    public static let shared = ManualDisplayOverrideStore()

    private let defaults: UserDefaults
    private static let keyPrefix = "display.override.icc."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Store faces

    /// Set/clear the override for a display (nil path = clear). The ICC
    /// FILE's bytes are read at RESOLUTION time (a profile file the user
    /// manages stays the truth; Lightamer never copies profiles).
    public func setOverride(_ iccPath: String?, displayID: UInt32) {
        let key = Self.keyPrefix + String(displayID)
        if let iccPath {
            defaults.set(iccPath, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    public func overridePath(displayID: UInt32) -> String? {
        defaults.string(forKey: Self.keyPrefix + String(displayID))
    }

    /// The display's stable ID (`CGDirectDisplayID` from the device
    /// description). nil = the screen reports no display ID.
    public static func displayID(of screen: NSScreen) -> UInt32? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
    }

    // MARK: - The resolution hook

    /// Resolve a screen's display profile with the override precedence:
    /// a hand-picked ICC (readable, parseable) WINS; anything else falls
    /// through to the standard matching table. The override's colorspace
    /// carries the EXACT profile bytes (`CGColorSpace(iccProfileData:)`).
    public func resolvedProfile(screen: NSScreen?) -> DisplayProfile {
        if let displayID = screen.flatMap(Self.displayID(of:)),
           let path = overridePath(displayID: displayID),
           let icc = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let space = CGColorSpace(iccProfileData: icc as CFData) {
            return .colorSyncFallback(space)
        }
        return DisplayProfile.resolve(screen?.colorSpace)
    }
}
