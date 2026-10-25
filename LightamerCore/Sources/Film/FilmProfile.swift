import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// FilmProfile — the typed consumer face of a spektrafilm film/paper profile
// (Plan M3-3-01 T3, KD-3; spectral face extended M8-1a T1).
//
// CONSUMER-KEYS-ONLY contract (KD-3, the licensing mechanism): this type
// decodes ONLY the keys Lightamer consumes. JSONDecoder ignores unknown
// keys by construction, so the layer decompositions and the tone-map
// blocks never enter the Swift type face — re-encoding a decoded profile
// EMITS ONLY the consumer keys and the asset file on disk is never
// rewritten (CC BY-SA byte-verbatim discipline, MANIFEST.sha256 is the
// reconciliation authority).
//
// M8-1a T1 additive re-open (the M3-3-01 KD-3 consumer-face ruling
// naturally re-opens in the M8 spectral context): the consumer face
// extends by SIX spectral keys (the 亲核登记② list) — data.log_sensitivity,
// data.channel_density, data.midscale_neutral_density,
// data.hanatos2025_adaptation_window_params,
// data.hanatos2025_adaptation_surface_params, info.viewing_illuminant.
// Everything still outside the consumer face stays out (the layer
// decompositions, the tone-map blocks, development_time families, …).
// All six decode decodeIfPresent with TOLERANT shape checks: a
// wrong-shaped array degrades to nil (never throws — M3-3-01 tolerant
// convention), while point-wise JSON nulls are LEGAL DATA states that
// survive decode verbatim ([Float?] storage). Every consumption of the
// nullable arrays goes through the null-aware projection family
// (baseDensityProjection() 同位 — the single interpolation source); the
// engine never re-implements null filling.
//
// Spectral boundary (M3-2 D-M3-2-2 + the 2026-10-08 E2 erratum, KD-5):
// spectral REPLAY is architecturally unreachable (CIRAW decodes RGB). The
// consumption face is the density domain:
//   • data.log_exposure  — 256 log10 points (−3…+4), the curve x-axis;
//   • data.density_curves — 256×3 per-channel status-M (film) /
//     status-A (paper) print densities, the dye-approximation payload;
//   • data.base_density  — an 81-wavelength SPECTRAL array (film side:
//     the orange-mask shape, nullable at the ends; paper side: the
//     spectral Dmin), consumed ONLY through the registered three-point
//     calibration projection (baseDensityProjection) — never replayed;
//   • data.wavelengths   — the 81-point λ axis, used ONLY for the
//     projection's nearest-neighbour sampling and axis validation
//     (never hard-coded grid assumptions).
//
// Density-domain note (m3, KD-3): the solver inputs mix densitometer
// domains — the negative-film side is status_M and the paper side is
// status_A; mixing the two in one additive density chain is the
// registered stylized-approximation boundary (M3-3-01-DECISIONS) — the
// assets are not modified and no M/A conversion is attempted; the model
// closes on itself. (Set-wide actuals, machine-checked: paper → status_A;
// positive slide films → status_A; negative films → status_M except the
// kodak_2383/2393 print-film stocks → status_A.)
//
// LICENSING: schema facts only; the profile DATA is CC BY-SA 4.0
// (Andrea Volpato / spektrafilm) and lives untouched in
// Resources/FilmProfiles/ (NOTICE in that directory).
// ─────────────────────────────────────────────────────────────────────────────

/// The typed load/validation errors (KD-3). Fail-closed by design: a bad
/// asset NEVER silently degrades — the store surfaces the typed error.
public enum FilmProfileError: Error, Equatable, Sendable {
    /// The file could not be read from disk.
    case fileUnreadable
    /// The payload is not a decodable profile (malformed JSON, wrong key
    /// types, a missing/invalid structural requirement).
    case schemaMismatch(String)
    /// A data-array shape violates the domain contract (row counts, row
    /// widths, axis lengths).
    case curveShapeMismatch(expected: Int, actual: Int)
    /// The base-density projection sampled a nil (or out-of-axis) point —
    /// the film's orange-mask array is nullable at its spectral ends and
    /// a film whose array is null at a calibration wavelength cannot be
    /// projected (E2 ruling: fail-closed, never a default 0).
    case baseProjectionUnavailable(wavelength: Double)
}

/// The hanatos2025 adaptation parameter carrier (M8-1a T1, review B1):
/// the profile JSON carries TWO shapes under two keys —
/// `hanatos2025_adaptation_window_params` (4 scalars: the erf4 UV/IR
/// bandpass c_uv/s_uv/c_ir/s_ir, folded into the sensitivities at build
/// time) and `hanatos2025_adaptation_surface_params` (3 rows × 15
/// coefficients: the per-channel deg-4 polynomial family, dropped-constant
/// form). One typed carrier holds EITHER form; the shape is validated
/// eagerly and an unrecognized/mis-shaped payload decodes nil (the
/// M3-3-01 tolerant convention — a bad adaptation block degrades, it
/// never fails the load). The carrier is a PLAIN value type on purpose:
/// the profile's encode/decode unboxes it so the emitted JSON keeps the
/// asset's raw-array shape (byte-faithful re-encode face).
public enum FilmProfileAdaptationParams: Sendable, Equatable {
    /// The window form: exactly 4 scalars (c_uv, s_uv, c_ir, s_ir).
    case window([Float])
    /// The surface form: exactly 3 rows × 15 deg-4 coefficients.
    case surface([[Float]])
}

/// A loaded, shape-validated film or paper profile. All data arrays are
/// the on-disk Float values (the solver converts to Float64 locally —
/// Float→Double widening is exact, so determinism is preserved).
public struct FilmProfile: Codable, Sendable, Equatable {

    // MARK: - Consumer metadata

    public struct Metadata: Codable, Sendable, Equatable {
        public let version: String?
        public let license: String?
        public let copyright: String?
        public let citation: String?

        private enum CodingKeys: String, CodingKey {
            case version, license, copyright, citation
        }

        public init(
            version: String?, license: String?, copyright: String?,
            citation: String?
        ) {
            self.version = version
            self.license = license
            self.copyright = copyright
            self.citation = citation
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(String.self, forKey: .version)
            license = try c.decodeIfPresent(String.self, forKey: .license)
            copyright = try c.decodeIfPresent(String.self, forKey: .copyright)
            citation = try c.decodeIfPresent(String.self, forKey: .citation)
        }
    }

    // MARK: - Consumer info (the stock identity + material classification)

    public struct Info: Codable, Sendable, Equatable {
        /// The stock id (the FilmRecord.filmStock/paperStock reference).
        public let stock: String?
        public let name: String?
        /// "negative" | "positive" (asset vocabulary).
        public let type: String?
        /// "film" | "paper" — the material classification the store
        /// indexes by (KD-4).
        public let support: String?
        /// "filming" | "printing".
        public let stage: String?
        /// The paper stock id this film is calibrated to print on
        /// (nil on paper profiles).
        public let targetPrint: String?
        public let channelModel: String?
        /// "status_M" (film side) / "status_A" (paper side) — the m3
        /// mixed-domain boundary note above.
        public let densitometer: String?
        public let referenceIlluminant: String?
        /// The illuminant the stock is VIEWED/scaned under ("D50", "K75P", …
        /// — the asset vocabulary). M8-1a T1 additive; drives the scan leg's
        /// viewing SPD lookup.
        public let viewingIlluminant: String?

        private enum CodingKeys: String, CodingKey {
            case stock, name, type, support, stage
            case targetPrint = "target_print"
            case channelModel = "channel_model"
            case densitometer
            case referenceIlluminant = "reference_illuminant"
            case viewingIlluminant = "viewing_illuminant"
        }

        public init(
            stock: String?, name: String?, type: String?, support: String?,
            stage: String?, targetPrint: String?, channelModel: String?,
            densitometer: String?, referenceIlluminant: String?,
            viewingIlluminant: String? = nil
        ) {
            self.stock = stock
            self.name = name
            self.type = type
            self.support = support
            self.stage = stage
            self.targetPrint = targetPrint
            self.channelModel = channelModel
            self.densitometer = densitometer
            self.referenceIlluminant = referenceIlluminant
            self.viewingIlluminant = viewingIlluminant
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            stock = try c.decodeIfPresent(String.self, forKey: .stock)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            type = try c.decodeIfPresent(String.self, forKey: .type)
            support = try c.decodeIfPresent(String.self, forKey: .support)
            stage = try c.decodeIfPresent(String.self, forKey: .stage)
            targetPrint = try c.decodeIfPresent(String.self, forKey: .targetPrint)
            channelModel = try c.decodeIfPresent(String.self, forKey: .channelModel)
            densitometer = try c.decodeIfPresent(String.self, forKey: .densitometer)
            referenceIlluminant = try c.decodeIfPresent(
                String.self, forKey: .referenceIlluminant)
            viewingIlluminant = try c.decodeIfPresent(
                String.self, forKey: .viewingIlluminant)
        }
    }

    // MARK: - Consumer data (the density domain)

    public let metadata: Metadata
    public let info: Info
    /// 256 log10 exposure points (−3…+4), ascending — the curve x-axis.
    public let logExposure: [Float]
    /// 256×3 per-channel density curves (channel-major rows: one row per
    /// log-exposure point, [R, G, B] within the row — the on-disk layout).
    public let densityCurves: [[Float]]
    /// The 81-wavelength base-density array (film: the orange-mask
    /// spectral shape, nullable at the ends; paper: the spectral Dmin).
    /// Consumed ONLY through `baseDensityProjection()`.
    public let baseDensity: [Float?]
    /// The 81-point λ axis (nm, strictly ascending). Validation + the
    /// projection's sampling axis — nothing else.
    public let wavelengths: [Float]

    // MARK: - Spectral face (M8-1a T1, additive; the 亲核登记② six)

    /// 81×3 log10 sensitivity (the on-disk layout: one row per wavelength,
    /// [R, G, B] within the row). Tolerant: absent key or a wrong shape →
    /// nil; every point is a finite number (the asset set carries no nulls
    /// here — a null would fail the [Float] decode and degrade the field).
    public let logSensitivity: [[Float]]?
    /// 81×3 spectral channel densities, NULLABLE per point (null is a
    /// legal data state — 15-78 of 243 points across the vendored set).
    /// Consumed ONLY through `channelDensityProjected()`.
    public let channelDensity: [[Float?]]?
    /// 81-point mid-scale neutral density, NULLABLE per point (5-26 of 81
    /// across the vendored set). Consumed ONLY through
    /// `midscaleNeutralDensityProjected()`.
    public let midscaleNeutralDensity: [Float?]?
    /// The adaptation WINDOW params (4 scalars) — one of the two shapes the
    /// single typed carrier holds (the field NAME carries the shape
    /// contract; the carrier is shared, review B1).
    public let adaptationWindowParams: FilmProfileAdaptationParams?
    /// The adaptation SURFACE params (3×15 deg-4 family) — the other shape.
    /// Build-time-only model constants (D-M8-7: no user-facing switch).
    public let adaptationSurfaceParams: FilmProfileAdaptationParams?

    private enum CodingKeys: String, CodingKey {
        case metadata, info
        case data
    }

    /// The on-disk payload lives under the top-level `data` object —
    /// the consumer arrays are nested-container projections of it (the
    /// flat consumer face is preserved; the asset's grouping is honored).
    private enum DataKeys: String, CodingKey {
        case logExposure = "log_exposure"
        case densityCurves = "density_curves"
        case baseDensity = "base_density"
        case wavelengths
        case logSensitivity = "log_sensitivity"
        case channelDensity = "channel_density"
        case midscaleNeutralDensity = "midscale_neutral_density"
        case adaptationWindowParams = "hanatos2025_adaptation_window_params"
        case adaptationSurfaceParams = "hanatos2025_adaptation_surface_params"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(info, forKey: .info)
        var data = container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        try data.encode(logExposure, forKey: .logExposure)
        try data.encode(densityCurves, forKey: .densityCurves)
        try data.encode(baseDensity, forKey: .baseDensity)
        try data.encode(wavelengths, forKey: .wavelengths)
        // encodeIfPresent 同式 (M8-1a T1): a profile decoded from old-form
        // JSON (no spectral keys) re-encodes BYTE-IDENTICAL to the
        // pre-M8-1a face — the zero-drift negative test pins this. The
        // adaptation carrier unboxes so the emitted keys keep the asset's
        // raw-array shape.
        try data.encodeIfPresent(logSensitivity, forKey: .logSensitivity)
        try data.encodeIfPresent(channelDensity, forKey: .channelDensity)
        try data.encodeIfPresent(
            midscaleNeutralDensity, forKey: .midscaleNeutralDensity)
        switch adaptationWindowParams {
        case .window(let values)?:
            try data.encode(values, forKey: .adaptationWindowParams)
        case .surface(let rows)?:
            try data.encode(rows, forKey: .adaptationWindowParams)
        case nil: break
        }
        switch adaptationSurfaceParams {
        case .window(let values)?:
            try data.encode(values, forKey: .adaptationSurfaceParams)
        case .surface(let rows)?:
            try data.encode(rows, forKey: .adaptationSurfaceParams)
        case nil: break
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metadata = try container.decode(Metadata.self, forKey: .metadata)
        info = try container.decode(Info.self, forKey: .info)
        let data = try container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        logExposure = try data.decode([Float].self, forKey: .logExposure)
        densityCurves = try data.decode([[Float]].self, forKey: .densityCurves)
        baseDensity = try data.decode([Float?].self, forKey: .baseDensity)
        wavelengths = try data.decode([Float].self, forKey: .wavelengths)
        // Tolerant spectral face (M8-1a T1): decodeIfPresent + eager shape
        // validation; a violation degrades the FIELD to nil — it never
        // throws (point-wise nulls are legal data, they do not trigger the
        // downgrade; review B1).
        logSensitivity = Self.normalizedSpectralMatrix(
            try? data.decode([[Float]].self, forKey: .logSensitivity),
            axisCount: wavelengths.count)
        channelDensity = Self.normalizedSpectralNullableMatrix(
            try? data.decode([[Float?]].self, forKey: .channelDensity),
            axisCount: wavelengths.count)
        midscaleNeutralDensity = Self.normalizedSpectralNullableArray(
            try? data.decode([Float?].self, forKey: .midscaleNeutralDensity),
            axisCount: wavelengths.count)
        adaptationWindowParams = Self.normalizedAdaptation(
            try? data.decodeIfPresent([Float].self, forKey: .adaptationWindowParams),
            surface: try? data.decodeIfPresent(
                [[Float]].self, forKey: .adaptationWindowParams))
        adaptationSurfaceParams = Self.normalizedAdaptation(
            try? data.decodeIfPresent([Float].self, forKey: .adaptationSurfaceParams),
            surface: try? data.decodeIfPresent(
                [[Float]].self, forKey: .adaptationSurfaceParams))
    }

    /// The tolerant adaptation-payload gate: a 4-scalar array decodes as
    /// the window form, a 3×15 matrix as the surface form, anything else
    /// degrades to nil.
    private static func normalizedAdaptation(
        _ window: [Float]?, surface: [[Float]]?
    ) -> FilmProfileAdaptationParams? {
        if let window, window.count == 4 { return .window(window) }
        if let surface, surface.count == 3, surface.allSatisfy({ $0.count == 15 }) {
            return .surface(surface)
        }
        return nil
    }

    /// Shape gate for the log-sensitivity matrix: row count == the axis
    /// count, row width == 3; any violation → nil (tolerant downgrade).
    private static func normalizedSpectralMatrix(
        _ rows: [[Float]]?, axisCount: Int
    ) -> [[Float]]? {
        guard let rows, rows.count == axisCount,
            rows.allSatisfy({ $0.count == 3 }) else { return nil }
        return rows
    }

    /// Shape gate for the nullable channel-density matrix (same contract;
    /// point-wise nulls do NOT trigger the downgrade — review B1).
    private static func normalizedSpectralNullableMatrix(
        _ rows: [[Float?]]?, axisCount: Int
    ) -> [[Float?]]? {
        guard let rows, rows.count == axisCount,
            rows.allSatisfy({ $0.count == 3 }) else { return nil }
        return rows
    }

    /// Shape gate for a nullable axis-length array.
    private static func normalizedSpectralNullableArray(
        _ values: [Float?]?, axisCount: Int
    ) -> [Float?]? {
        guard let values, values.count == axisCount else { return nil }
        return values
    }

    /// Memberwise init (tests / synthetic fixtures) — validates before
    /// returning (fail-closed at construction, same contract as load).
    /// The spectral face normalizes through the SAME tolerant gates as the
    /// decoder (a wrong-shaped spectral input downgrades to nil, never
    /// throws — M8-1a T1).
    public init(
        metadata: Metadata, info: Info, logExposure: [Float],
        densityCurves: [[Float]], baseDensity: [Float?], wavelengths: [Float],
        logSensitivity: [[Float]]? = nil, channelDensity: [[Float?]]? = nil,
        midscaleNeutralDensity: [Float?]? = nil,
        adaptationWindowParams: FilmProfileAdaptationParams? = nil,
        adaptationSurfaceParams: FilmProfileAdaptationParams? = nil
    ) throws {
        self.metadata = metadata
        self.info = info
        self.logExposure = logExposure
        self.densityCurves = densityCurves
        self.baseDensity = baseDensity
        self.wavelengths = wavelengths
        self.logSensitivity = Self.normalizedSpectralMatrix(
            logSensitivity, axisCount: wavelengths.count)
        self.channelDensity = Self.normalizedSpectralNullableMatrix(
            channelDensity, axisCount: wavelengths.count)
        self.midscaleNeutralDensity = Self.normalizedSpectralNullableArray(
            midscaleNeutralDensity, axisCount: wavelengths.count)
        self.adaptationWindowParams = adaptationWindowParams
        self.adaptationSurfaceParams = adaptationSurfaceParams
        try validate()
    }

    // MARK: - Loader (KD-3)

    /// Load + decode + shape-validate. Fail-closed: every failure mode is
    /// a typed `FilmProfileError` (a bad asset never degrades silently).
    /// The decode path goes through the SYNTHESIZED Codable (which does
    /// not validate), so the shape contract is enforced explicitly here.
    public static func load(_ url: URL) throws -> FilmProfile {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw FilmProfileError.fileUnreadable
        }
        let profile: FilmProfile
        do {
            profile = try JSONDecoder().decode(FilmProfile.self, from: data)
        } catch {
            throw FilmProfileError.schemaMismatch("\(error)")
        }
        try profile.validate()
        return profile
    }

    // MARK: - Shape validation (KD-3 + the E2/m3 erratum)

    private func validate() throws {
        try Self.validateShape(
            logExposure: logExposure, densityCurves: densityCurves,
            baseDensity: baseDensity, wavelengths: wavelengths)
    }

    private static func validateShape(
        logExposure: [Float], densityCurves: [[Float]],
        baseDensity: [Float?], wavelengths: [Float]
    ) throws {
        // The curve block: one row per exposure point, each row [R, G, B].
        guard densityCurves.count == logExposure.count, logExposure.count >= 2
        else {
            throw FilmProfileError.curveShapeMismatch(
                expected: logExposure.count, actual: densityCurves.count)
        }
        for row in densityCurves where row.count != 3 {
            throw FilmProfileError.curveShapeMismatch(
                expected: 3, actual: row.count)
        }
        // The spectral-axis block: base_density and wavelengths are the
        // SAME axis length (81 in the vendored set; the invariant is the
        // equality, not the 81). The E2 note: this is the guard against
        // silently consuming a spectral-domain array as an RGB constant.
        guard baseDensity.count == wavelengths.count, wavelengths.count >= 1
        else {
            throw FilmProfileError.curveShapeMismatch(
                expected: wavelengths.count, actual: baseDensity.count)
        }
        // Axis validation (wavelengths' ONLY job): strictly ascending and
        // finite, so nearest-neighbour sampling is well-defined and
        // deterministic.
        var previous = -Float.infinity
        for value in wavelengths {
            guard value.isFinite, value > previous else {
                throw FilmProfileError.schemaMismatch(
                    "wavelengths axis must be finite and strictly ascending")
            }
            previous = value
        }
    }

    // MARK: - The registered base-density projection (E2 ruling, KD-5)

    /// The three calibration wavelengths of the registered projection
    /// (E2, 2026-10-08): base_R/G/B := base_density(λ≈650/550/450 nm).
    public enum CalibrationWavelength {
        public static let red = 650.0
        public static let green = 550.0
        public static let blue = 450.0
    }

    /// The registered three-point calibration projection (E2 ruling —
    /// M3-3-01-DECISIONS is the registration authority): sample the
    /// base-density spectral array at the nearest-neighbour wavelength of
    /// each calibration point and return the RGB constants the negative
    /// segment adds (film: the orange-mask constant half, RFC-028; paper:
    /// the Dmin constants). Ties (a target exactly between two axis
    /// points) resolve to the LOWER index — deterministic by construction.
    ///
    /// Fail-closed: a nil (or axis-missing) sample point throws
    /// `.baseProjectionUnavailable` — never a silent default 0.
    public func baseDensityProjection() throws
        -> (r: Double, g: Double, b: Double) {
        let r = try projectedSample(at: Self.CalibrationWavelength.red)
        let g = try projectedSample(at: Self.CalibrationWavelength.green)
        let b = try projectedSample(at: Self.CalibrationWavelength.blue)
        return (r, g, b)
    }

    private func projectedSample(at wavelength: Double) throws -> Double {
        guard let index = nearestIndex(to: wavelength) else {
            throw FilmProfileError.baseProjectionUnavailable(wavelength: wavelength)
        }
        guard let value = baseDensity[index] else {
            throw FilmProfileError.baseProjectionUnavailable(wavelength: wavelength)
        }
        return Double(value)
    }

    /// The nearest-neighbour axis index (lowest index on ties).
    func nearestIndex(to wavelength: Double) -> Int? {
        guard !wavelengths.isEmpty else { return nil }
        var best = 0
        var bestDistance = abs(Double(wavelengths[0]) - wavelength)
        for index in wavelengths.indices.dropFirst() {
            let distance = abs(Double(wavelengths[index]) - wavelength)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    // MARK: - The null-aware spectral projection family (M8-1a T1, review B1)

    /// THE single null-resolution source for every nullable spectral array
    /// (review B1: no consumer ever re-implements null filling). A null
    /// sample resolves by linear interpolation in wavelength between its
    /// nearest non-null neighbours; at an array end (a neighbour is
    /// missing on one side) the nearest non-null sample extends
    /// constantly. An all-null array has no projection (nil). Outputs are
    /// Float64 (Float→Double widening is exact).
    private static func projectedSpectralSeries(_ samples: [Float?], axis: [Float])
        -> [Double]? {
        guard samples.count == axis.count, !samples.isEmpty else { return nil }
        let nonNull = samples.enumerated().compactMap { $1 == nil ? nil : $0 }
        guard !nonNull.isEmpty else { return nil }
        return samples.indices.map { index in
            if let value = samples[index] { return Double(value) }
            let left = nonNull.last(where: { $0 < index })
            let right = nonNull.first(where: { $0 > index })
            switch (left, right) {
            case (let l?, let r?):
                let wl = Double(axis[l]), wr = Double(axis[r])
                let vl = Double(samples[l]!), vr = Double(samples[r]!)
                let t = (Double(axis[index]) - wl) / (wr - wl)
                return vl + t * (vr - vl)
            case (let l?, nil):
                return Double(samples[l]!)
            case (nil, let r?):
                return Double(samples[r]!)
            default:
                fatalError("unreachable: a null with no non-null neighbours")  // swiftlint:disable:this line_length
            }
        }
    }

    /// The projected (null-resolved) 81-point base-density series — the
    /// full-array twin of the registered three-point
    /// `baseDensityProjection()` face (the M8 spectral engine consumes the
    /// whole axis through THIS face).
    public func baseDensityProjected() -> [Double]? {
        Self.projectedSpectralSeries(baseDensity, axis: wavelengths)
    }

    /// The projected (null-resolved) 81×3 channel-density matrix — each
    /// channel's ALONG-AXIS series resolves through the single projection
    /// source. Layout is channel-major: `[channel][wavelength]` (the
    /// engine reassembles the [wavelength][channel] form for its integrals).
    /// Returns nil when the field itself degraded at decode; an all-null
    /// channel yields an empty series (the engine's coverage gate rejects
    /// it).
    public func channelDensityProjected() -> [[Double]]? {
        guard let channelDensity, !channelDensity.isEmpty else { return nil }
        return (0..<3).map { channel in
            Self.projectedSpectralSeries(
                channelDensity.map { $0[channel] }, axis: wavelengths) ?? []
        }
    }

    /// The projected (null-resolved) 81-point mid-scale neutral density —
    /// same family, same single source.
    public func midscaleNeutralDensityProjected() -> [Double]? {
        guard let midscaleNeutralDensity else { return nil }
        return Self.projectedSpectralSeries(
            midscaleNeutralDensity, axis: wavelengths)
    }
}
