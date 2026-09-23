import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The parametric (blendif) mask record (Plan 06-04 T1; IOP-MASK-02) — the
// dt parametric mask transcribed onto Lightamer's single working space.
//
// DOMAIN (D-06-CONTEXT-3): v1 ships ONE kernel covering the luma + JzCzhz
// channel families — the OpenCL `blendif_factor_rgb_jzczhz`
// (blendop.cl:329-408) supports ALL of them in one body (gray/RGB via the
// profile luminance row, JzCzhz via the perceptual chain), so `domain` is
// the UI-facing declaration while the kernel gates per-channel by bitmask.
//
// CHANNEL SLOTS are dt's `dt_develop_blendif_channels_t` indices verbatim
// (blend.h:120-172) — the RGB_SCENE numbering, which is what the
// single-kernel body evaluates:
//   0 gray_in  1 red_in  2 green_in  3 blue_in
//   4 gray_out 5 red_out 6 green_out 7 blue_out
//   8 Jz_in 9 Cz_in 10 hz_in   (11 unused)
//   12 Jz_out 13 Cz_out 14 hz_out
// `DEVELOP_BLENDIF_RGB_MASK` = 0x77FF (slots 0-10 + 12-14; bit 11 excluded).
//
// PER-CHANNEL CURVE = dt's 4-point UI trapezoid (`blendif_parameters[i*4 +
// 0..3]`, 0..1 domain) + the per-channel invert bit (blend.h upper half of
// `blendif`) + the boost exponent (`blendif_boost_factors[i]` — parameters
// scale by exp2(boost), blend.c:170-190 `_blendif_process_parameters`).
//
// ONE-WAY format lock: this payload freezes at 06-04 ship (SidecarMaskSpec
// optional field). Later payload arrives ONLY as optional decodeIfPresent
// fields. The mask identity hash stays DERIVED (`MaskSpec.stableHash()`),
// never persisted.
// ─────────────────────────────────────────────────────────────────────────────

/// The parametric mask payload (`MaskSpec.parametric`).
public struct ParametricMask: Codable, Sendable, Equatable, Hashable {

    /// The declared selection domain (D-06-CONTEXT-3). The kernel is the
    /// SAME for both — the bitmask decides which channels participate.
    public enum Domain: String, Codable, Sendable, Equatable, Hashable {
        case luma
        case jzczhz
    }

    /// One channel's 4-point curve. `points` = dt's
    /// `[p0, p1, p2, p3]` (0..1): below p0 → 0, ramp up to p1, plateau to
    /// p2, ramp down to p3, above → 0 (`_blendif_compute_factor`,
    /// blendif_rgb_jzczhz.c:64-94). `inverted` = the per-channel invert bit
    /// (1 − factor). `boost` = the exp2 exponent the 4 points scale by
    /// (dt boost factor — Jz/Cz default −6.64385619 in dt's GUI offset
    /// convention is NOT applied here: we store the FINAL exponent).
    public struct ChannelCurve: Codable, Sendable, Equatable, Hashable {
        public var points: [Float]
        public var inverted: Bool
        public var boost: Float
        public var enabled: Bool

        public init(points: [Float], inverted: Bool = false, boost: Float = 0, enabled: Bool = true) {
            precondition(points.count == 4, "blendif curve needs exactly 4 points")
            self.points = points
            self.inverted = inverted
            self.boost = boost
            self.enabled = enabled
        }
    }

    /// One (channel slot, curve) pair — an array (not a dictionary) so the
    /// canonical JSON spelling is a plain list.
    public struct ChannelEntry: Codable, Sendable, Equatable, Hashable {
        public var channel: Int
        public var curve: ChannelCurve

        public init(channel: Int, curve: ChannelCurve) {
            self.channel = channel
            self.curve = curve
        }
    }

    /// Form version (NDE-3) — 1 until a payload shape migrates.
    public var version: Int
    public var domain: Domain
    public var channels: [ChannelEntry]

    // ── The mask post-processing parameters (dt blend params; the chain
    //    order blur → feather → tone curve is pinned by
    //    `_get_post_operations` blend.c:305-355 — plan 06-04 T2).
    public var blurRadius: Float
    public var featherRadius: Float
    public var contrast: Float
    public var brightness: Float

    /// The mask-level invert (dt `DEVELOP_COMBINE_INV`: opacity = 1 − mask).
    public var invert: Bool

    public init(
        version: Int = 1,
        domain: Domain,
        channels: [ChannelEntry],
        blurRadius: Float = 0,
        featherRadius: Float = 0,
        contrast: Float = 0,
        brightness: Float = 0,
        invert: Bool = false
    ) {
        self.version = version
        self.domain = domain
        self.channels = channels
        self.blurRadius = blurRadius
        self.featherRadius = featherRadius
        self.contrast = contrast
        self.brightness = brightness
        self.invert = invert
    }

    // MARK: - dt channel constants (blend.h:120-176)

    /// `DEVELOP_BLENDIF_RGB_MASK` — the channels the RGB_SCENE kernel walks.
    public static let rgbMask: UInt32 = 0x77FF

    /// `DEVELOP_BLENDIF_SIZE` — the packed parameter stride (16 slots × 6).
    public static let slotCount = 16

    /// dt `DEVELOP_BLENDIF_PARAMETER_ITEMS` — 6 floats per slot.
    public static let itemsPerSlot = 6

    // MARK: - Bitmask packing

    /// The `blendif` word: low 16 bits = enabled channels, high 16 bits =
    /// inverted channels (dt: `invert_mask = blendif >> 16`).
    public func channelBitmask() -> UInt32 {
        var enabled: UInt32 = 0
        var inverted: UInt32 = 0
        for entry in channels where entry.curve.enabled {
            precondition(
                (0..<Self.slotCount).contains(entry.channel) && entry.channel != 11,
                "invalid blendif channel slot \(entry.channel)")
            enabled |= 1 << UInt32(entry.channel)
            if entry.curve.inverted { inverted |= 1 << UInt32(entry.channel) }
        }
        return enabled | (inverted << 16)
    }

    /// Whether any channel participates (a mask with an empty bitmask is
    /// semantically "all 1" — the caller may skip the kernel).
    public var hasActiveChannels: Bool { channelBitmask() & Self.rgbMask != 0 }

    // MARK: - dt `_blendif_process_parameters` (blend.c:167-216) — the CPU
    // parameter packing the kernel consumes: 96 floats = 16 slots × 6
    // [p0', p1', p2', p3', slopeUp, slopeDown].

    /// The packed parameters (Float — the kernel ABI; the derivation is
    /// 32-bit faithful to dt, which packs in float32 too).
    public func packedParameters() -> [Float] {
        var parameters = [Float](repeating: 0, count: Self.slotCount * Self.itemsPerSlot)
        // UI curve values are ALREADY the 0..1 domain (no Lab a/b 0.5 offset
        // exists in the luma/JzCzhz families — blend.c:181-188 applies the
        // offset only for DEVELOP_BLEND_CS_LAB a/b slots; the branch is
        // recorded here as the dt structure we deliberately do not reach).
        let offset: Float = 0
        for entry in channels where entry.curve.enabled {
            let ch = entry.channel
            let ui = entry.curve.points
            let boost = exp2(entry.curve.boost)
            for k in 0..<4 {
                parameters[ch * Self.itemsPerSlot + k] = (ui[k] - offset) * boost
            }
            // Pre-computed increasing/decreasing slopes (0.001 floor).
            parameters[ch * Self.itemsPerSlot + 4] =
                1.0 / max(0.001, parameters[ch * Self.itemsPerSlot + 1] - parameters[ch * Self.itemsPerSlot + 0])
            parameters[ch * Self.itemsPerSlot + 5] =
                1.0 / max(0.001, parameters[ch * Self.itemsPerSlot + 3] - parameters[ch * Self.itemsPerSlot + 2])
            // Open-end handling: both lower points at/below 0 → unbounded
            // low; both upper points at/above 1 → unbounded high.
            if ui[0] <= 0 && ui[1] <= 0 {
                parameters[ch * Self.itemsPerSlot + 0] = -Float.greatestFiniteMagnitude
                parameters[ch * Self.itemsPerSlot + 1] = -Float.greatestFiniteMagnitude
            }
            if ui[2] >= 1 && ui[3] >= 1 {
                parameters[ch * Self.itemsPerSlot + 2] = Float.greatestFiniteMagnitude
                parameters[ch * Self.itemsPerSlot + 3] = Float.greatestFiniteMagnitude
            }
        }
        // INACTIVE slots get the full-range pass-through trapezoid
        // (blend.c:206-214: ±FLT_MAX bounds with zero slopes → factor 1
        // for every finite value; the kernel also skips them by bitmask —
        // both defenses stay so the buffer is never read uninitialized).
        for slot in 0..<Self.slotCount {
            let base = slot * Self.itemsPerSlot
            let active = channels.contains { $0.channel == slot && $0.curve.enabled }
            if !active {
                parameters[base + 0] = -Float.greatestFiniteMagnitude
                parameters[base + 1] = -Float.greatestFiniteMagnitude
                parameters[base + 2] = Float.greatestFiniteMagnitude
                parameters[base + 3] = Float.greatestFiniteMagnitude
                parameters[base + 4] = 0
                parameters[base + 5] = 0
            }
        }
        return parameters
    }
}
