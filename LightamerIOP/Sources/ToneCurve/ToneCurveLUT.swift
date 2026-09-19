import simd

// ─────────────────────────────────────────────────────────────────────────
// ToneCurveLUT (Plan 03-03-T3) — the CPU half of the tonecurve iop
// (IOP-TONE-03): the three interpolators, the 0x10000-point L/T/A/B table
// build, the unbounded power-law extrapolation fits, and the autoscale
// table re-derivations.
//
// Darktable reference (tree dc58cf0ba1):
//   - `src/iop/tonecurve.c:97-108`  params v5 (L/a/b node sets, types,
//     autoscale_ab, unbound_ab, preserve_colors)
//   - `:722-841`                    commit_params: table build + scaling
//                                   + XYZ/RGB re-derivations + 5 fits
//   - `src/common/curve_tools.c`    interpolators (curve_tools.c:393-653)
//   - `src/gui/draw.h:389-421`      CurveDataSample → table sampling
//   - `src/common/rgb_norms.h`      the preserve_colors norm family
//
// RECORDED DEVIATION (LUT integer quantization): dt quantizes its table
// samples to 1/65536 integers through CurveDataSample
// (`int(interp*0x10000/0x10000 + 0.5)`). Lightamer stores the raw
// interpolation value (Double → float32 buffer) — a ≤1 LSB difference
// that removes the quantization cliff from the TABLE side while keeping
// dt's NEAREST truncation LOOKUP semantics. The sampling convention is
// dt's: sample k covers x = k/0xffff (res = 1/(samplingRes−1)), values
// flat-clamped outside [x_first, x_last] and to [0, 1].
//
// Deviation (RGB-linked working space): dt derives the RGB-linked table
// over ProPhoto RGB; Lightamer derives it over the WORKING space (linear
// Rec2020) — semantic alignment with the working-domain decision (Plan
// 03-03 Goal; RESEARCH §1.3 "RGB-linked 走工作域亮度").
//
// All interpolation math uses only +−×÷√ (IEEE-deterministic), computed
// in Double — the synthesized float64 references (gen_fixtures.py)
// replicate the same op order, so no transcendental round-off enters the
// table side. powf appears only in the extrapolation fits (evaluated on
// x ≥ 1 inputs, not exercised by the in-domain fixtures).
// ─────────────────────────────────────────────────────────────────────────

public enum ToneCurveLUT {

    /// LUT resolution (dt `0x10000`, tonecurve.c:137).
    public static let resolution = 0x10000

    /// Max nodes per curve (dt `DT_IOP_TONECURVE_MAXNODES`, :47).
    public static let maxNodes = 20

    // MARK: - Types (dt raw values — tonecurve.c:102, curve_tools.h:27-29)

    public enum CurveType: Int, Codable, Hashable, Sendable {
        case cubicSpline = 0
        case catmullRom = 1
        case monotoneHermite = 2
    }

    /// dt `dt_iop_tonecurve_autoscale_t` (:82-95) raw values.
    public enum AutoscaleAb: Int, Codable, Hashable, Sendable {
        case manual = 0
        case labLinked = 1
        case xyzLinked = 2
        case rgbLinked = 3
    }

    /// dt `dt_iop_rgb_norms_t` (rgb_norms.h) raw values.
    public enum RGBNorm: Int, Codable, Hashable, Sendable {
        case none = 0
        case luminance = 1
        case max = 2
        case average = 3
        case sum = 4
        case norm = 5
        case power = 6
    }

    // MARK: - Interpolators (curve_tools.c verbatim, Double)

    /// `monotone_hermite_set` (curve_tools.c:393-452). Returns nil on
    /// non-strictly-increasing x (dt returns NULL → caller falls back to
    /// the identity curve).
    public static func monotoneHermiteTangents(x: [Double], y: [Double]) -> [Double]? {
        let n = x.count
        guard n >= 2 else { return nil }
        for i in 0..<(n - 1) where x[i + 1] <= x[i] { return nil }

        var delta = [Double](repeating: 0, count: n)
        var m = [Double](repeating: 0, count: n + 1)
        for i in 0..<(n - 1) {
            delta[i] = (y[i + 1] - y[i]) / (x[i + 1] - x[i])
        }
        delta[n - 1] = delta[n - 2]
        m[0] = delta[0]
        m[n - 1] = delta[n - 1]
        for i in 1..<(n - 1) {
            m[i] = (delta[i - 1] + delta[i]) * 0.5
        }
        let epsilon = 2.0 * Double.leastNormalMagnitude // dt EPSILON = 2*FLT_MIN
        for i in 0..<n {
            if abs(delta[i]) < epsilon {
                m[i] = 0
                m[i + 1] = 0
            } else {
                let alpha = m[i] / delta[i]
                let beta = m[i + 1] / delta[i]
                let tau = alpha * alpha + beta * beta
                if tau > 9.0 {
                    m[i] = 3.0 * alpha * delta[i] / tau.squareRoot()
                    m[i + 1] = 3.0 * beta * delta[i] / tau.squareRoot()
                }
            }
        }
        return Array(m[0..<n])
    }

    /// `catmull_rom_set` (curve_tools.c:467-499).
    public static func catmullRomTangents(x: [Double], y: [Double]) -> [Double]? {
        let n = x.count
        guard n >= 2 else { return nil }
        for i in 0..<(n - 1) where x[i + 1] <= x[i] { return nil }
        var m = [Double](repeating: 0, count: n)
        m[0] = (y[1] - y[0]) / (x[1] - x[0])
        for i in 1..<(n - 1) {
            m[i] = (y[i + 1] - y[i - 1]) / (x[i + 1] - x[i - 1])
        }
        m[n - 1] = (y[n - 1] - y[n - 2]) / (x[n - 1] - x[n - 2])
        return m
    }

    /// `spline_cubic_set` with dt's wrapper boundary conditions
    /// (natural spline: second derivative 0 at both ends,
    /// curve_tools.c:376-379) + the `d3_np_fs` tridiagonal solve
    /// (:95-132).
    public static func cubicSplineSecondDerivatives(x: [Double], y: [Double]) -> [Double]? {
        let n = x.count
        guard n >= 2 else { return nil }
        for i in 0..<(n - 1) where x[i + 1] <= x[i] { return nil }

        // dt wrapper: spline_cubic_set_internal(n, t, y, 2, 0.0, 2, 0.0)
        var a = [Double](repeating: 0, count: 3 * n)
        var b = [Double](repeating: 0, count: n)
        // first equation (ibcbeg == 2)
        b[0] = 0
        a[1] = 1
        a[0 + 3] = 0
        for i in 1..<(n - 1) {
            b[i] = (y[i + 1] - y[i]) / (x[i + 1] - x[i]) - (y[i] - y[i - 1]) / (x[i] - x[i - 1])
            a[2 + (i - 1) * 3] = (x[i] - x[i - 1]) / 6.0
            a[1 + i * 3] = (x[i + 1] - x[i - 1]) / 3.0
            a[0 + (i + 1) * 3] = (x[i + 1] - x[i]) / 6.0
        }
        // last equation (ibcend == 2)
        b[n - 1] = 0
        a[2 + (n - 2) * 3] = 0
        a[1 + (n - 1) * 3] = 1

        // dt's d3 special case (ypp ≡ 0) fires only for the (0,0)-BC
        // wrapper; the natural wrapper (2,0) solves through d3_np_fs.
        return d3NpFs(a: a, b: b, n: n)
    }

    /// `d3_np_fs` (curve_tools.c:95-132) — factors and solves the
    /// tridiagonal system; nil on a zero diagonal.
    static func d3NpFs(a: [Double], b: [Double], n: Int) -> [Double]? {
        var a = a
        var x = b
        for i in 0..<n where a[1 + i * 3] == 0 { return nil }
        for i in 1..<n {
            let xmult = a[2 + (i - 1) * 3] / a[1 + (i - 1) * 3]
            a[1 + i * 3] = a[1 + i * 3] - xmult * a[0 + i * 3]
            x[i] = x[i] - xmult * x[i - 1]
        }
        x[n - 1] = x[n - 1] / a[1 + (n - 1) * 3]
        for i in stride(from: n - 2, through: 0, by: -1) {
            x[i] = (x[i] - a[0 + (i + 1) * 3] * x[i + 1]) / a[1 + i * 3]
        }
        return x
    }

    /// `catmull_rom_val` (curve_tools.c:524-558) — the Hermite-form
    /// evaluation dt uses for BOTH catmull-rom AND monotone hermite.
    public static func hermiteVal(x: [Double], y: [Double], tangents: [Double], xval: Double) -> Double {
        let n = x.count
        var ival = n - 2
        for i in 0..<(n - 2) where xval < x[i + 1] {
            ival = i
            break
        }
        let m0 = tangents[ival], m1 = tangents[ival + 1]
        let h = x[ival + 1] - x[ival]
        let dx = (xval - x[ival]) / h
        let dx2 = dx * dx
        let dx3 = dx2 * dx
        let h00 = 2.0 * dx3 - 3.0 * dx2 + 1.0
        let h10 = dx3 - 2.0 * dx2 + dx
        let h01 = -2.0 * dx3 + 3.0 * dx2
        let h11 = dx3 - dx2
        return h00 * y[ival] + h10 * h * m0 + h01 * y[ival + 1] + h11 * h * m1
    }

    /// `spline_cubic_val` (curve_tools.c:616-653).
    public static func splineVal(x: [Double], y: [Double], ypp: [Double], tval: Double) -> Double {
        let n = x.count
        var ival = n - 2
        for i in 0..<(n - 1) where tval < x[i + 1] {
            ival = i
            break
        }
        let dt = tval - x[ival]
        let h = x[ival + 1] - x[ival]
        return y[ival]
            + dt * ((y[ival + 1] - y[ival]) / h
                - (ypp[ival + 1] / 6.0 + ypp[ival] / 3.0) * h
                + dt * (0.5 * ypp[ival] + dt * ((ypp[ival + 1] - ypp[ival]) / (6.0 * h))))
    }

    // MARK: - Table build (dt draw.h CurveDataSample shape, no int quant)

    /// Sample one curve into `resolution` table entries over [0,1].
    /// Flat-clamped outside the node x-range; values clamped to [0,1]
    /// (dt m_min_y/m_max_y with the box (0,0)-(1,1)). Nodes with < 2
    /// entries or non-increasing x degrade to the identity (dt's
    /// interpolators return NULL and the curve stays at its previous
    /// state; a fresh module has identity — documented sanitize).
    public static func buildTable(nodes: [(x: Double, y: Double)], type: CurveType) -> [Double] {
        var table = [Double](repeating: 0, count: resolution)
        guard nodes.count >= 2 else {
            for k in 0..<resolution { table[k] = Double(k) / Double(resolution - 1) }
            return table
        }
        let xs = nodes.map(\.x), ys = nodes.map(\.y)
        let tangents: [Double]?
        let ypp: [Double]?
        switch type {
        case .monotoneHermite, .catmullRom:
            tangents = type == .monotoneHermite
                ? monotoneHermiteTangents(x: xs, y: ys)
                : catmullRomTangents(x: xs, y: ys)
            ypp = nil
        case .cubicSpline:
            tangents = nil
            ypp = cubicSplineSecondDerivatives(x: xs, y: ys)
        }
        guard tangents != nil || ypp != nil else {
            for k in 0..<resolution { table[k] = Double(k) / Double(resolution - 1) }
            return table
        }
        let res = 1.0 / Double(resolution - 1)
        let firstX = xs[0], lastX = xs[nodes.count - 1]
        let firstY = ys[0], lastY = ys[nodes.count - 1]
        for k in 0..<resolution {
            let xk = Double(k) * res
            let v: Double
            if xk < firstX {
                v = firstY // dt: flat before the first point
            } else if xk > lastX {
                v = lastY // dt: flat after the last point
            } else if let tangents {
                v = hermiteVal(x: xs, y: ys, tangents: tangents, xval: xk)
            } else if let ypp {
                v = splineVal(x: xs, y: ys, ypp: ypp, tval: xk)
            } else {
                v = xk
            }
            table[k] = min(max(v, 0.0), 1.0)
        }
        return table
    }

    // MARK: - Full commit (tonecurve.c:722-841)

    /// The derived piece state for one pipe run.
    public struct Tables {
        /// table_L — Lab L / [0,1]-normalized channels, domain [0,100].
        public var tableL: [Double]
        /// table_a / table_b — domain [-128, 128].
        public var tableA: [Double]
        public var tableB: [Double]
        /// Extrapolation fits: {1/x0, y0, g} × (L-right, a-right, a-left,
        /// b-right, b-left).
        public var coeffsL: [Double]
        public var coeffsARight: [Double]
        public var coeffsALeft: [Double]
        public var coeffsBRight: [Double]
        public var coeffsBLeft: [Double]
        /// table_L[0.01 × resolution] (dt low_approximation, :401).
        public var lowApproximation: Double
    }

    /// dt `commit_params` :722-841 — build, scale, autoscale re-derive,
    /// fit. `tangents`-style failures degrade to identity per curve.
    public static func commit(
        nodesL: [(x: Double, y: Double)],
        nodesA: [(x: Double, y: Double)],
        nodesB: [(x: Double, y: Double)],
        typeL: CurveType,
        typeA: CurveType,
        typeB: CurveType,
        autoscaleAb: AutoscaleAb
    ) -> Tables {
        // build + scale (tonecurve.c:735-763)
        var tableL = buildTable(nodes: nodesL, type: typeL).map { $0 * 100.0 }
        var tableA = buildTable(nodes: nodesA, type: typeA).map { $0 * 256.0 - 128.0 }
        let tableB = buildTable(nodes: nodesB, type: typeB).map { $0 * 256.0 - 128.0 }

        // autoscale re-derivations (:766-791) — the L table becomes a
        // Y→Y (XYZ) or G→G (working RGB) mapping. Index sampling is
        // ROUNDED (deviation #2 — matches the kernel lookup and the
        // gen_fixtures reference).
        if autoscaleAb == .xyzLinked {
            var derived = [Double](repeating: 0, count: resolution)
            for k in 0..<resolution {
                let t = Double(k) / Double(resolution)
                let lab = LabRoundTrip.xyz50ToLab(SIMD3(t, t, t))
                let idx = min(max(Int(lab.x / 100.0 * Double(resolution) + 0.5), 0), resolution - 1)
                let labOut = SIMD3(tableL[idx], lab.y, lab.z)
                derived[k] = LabRoundTrip.labToXYZ50(labOut).y
            }
            tableL = derived
        } else if autoscaleAb == .rgbLinked {
            var derived = [Double](repeating: 0, count: resolution)
            for k in 0..<resolution {
                let t = Double(k) / Double(resolution)
                let lab = LabRoundTrip.rec2020ToLab(SIMD3(t, t, t))
                let idx = min(max(Int(lab.x / 100.0 * Double(resolution) + 0.5), 0), resolution - 1)
                let labOut = SIMD3(tableL[idx], lab.y, lab.z)
                derived[k] = LabRoundTrip.labToRec2020(labOut).y
            }
            tableL = derived
        }

        // extrapolation fits (:797-840) — sampled over 0.7..1.0 of the
        // relevant curve's last-node x (right) / mirrored first-node x
        // (left).
        let xs: [Double] = [0.7, 0.8, 0.9, 1.0]
        // rounded sampling (matches the kernel's rounded lookup + the
        // gen_fixtures lut_index)
        func sample(_ t: [Double], _ x: Double) -> Double {
            t[min(max(Int(x * Double(resolution) + 0.5), 0), resolution - 1)]
        }
        func fit(_ t: [Double], _ xm: Double) -> [Double] {
            IOPExpFit.estimateD(xs.map { $0 * xm }, xs.map { sample(t, $0 * xm) })
        }
        // left-side fits sample the MIRRORED positions (1 − x — dt
        // :818/:836 "we need to mirror the x-axis").
        func leftFit(_ t: [Double], _ xm: Double) -> [Double] {
            IOPExpFit.estimateD(xs.map { $0 * xm }, xs.map { sample(t, 1.0 - $0 * xm) })
        }
        let xmL = nodesL.last?.x ?? 1.0
        let xmAR = nodesA.last?.x ?? 1.0
        let xmAL = 1.0 - (nodesA.first?.x ?? 0.0)
        let xmBR = nodesB.last?.x ?? 1.0
        let xmBL = 1.0 - (nodesB.first?.x ?? 0.0)

        let coeffsL = fit(tableL, xmL)
        let coeffsARight = fit(tableA, xmAR)
        let coeffsALeft = leftFit(tableA, xmAL)
        let coeffsBRight = fit(tableB, xmBR)
        let coeffsBLeft = leftFit(tableB, xmBL)

        let lowApproximation = tableL[min(Int(0.01 * Double(resolution)), resolution - 1)]
        return Tables(
            tableL: tableL, tableA: tableA, tableB: tableB,
            coeffsL: coeffsL, coeffsARight: coeffsARight, coeffsALeft: coeffsALeft,
            coeffsBRight: coeffsBRight, coeffsBLeft: coeffsBLeft,
            lowApproximation: lowApproximation
        )
    }

    /// The preserved-colors norm family (rgb_norms.h:31-79) over the
    /// working domain. Deviation: LUMINANCE uses the Rec2020 Y row (dt
    /// uses the work profile's matrix luminance — the working-space
    /// equivalent).
    public static func rgbNorm(_ rgb: SIMD3<Double>, _ norm: RGBNorm) -> Double {
        switch norm {
        case .luminance:
            return rgb.x * 0.262700 + rgb.y * 0.678009 + rgb.z * 0.059291
        case .max:
            return max(rgb.x, max(rgb.y, rgb.z))
        case .average:
            return (rgb.x + rgb.y + rgb.z) / 3.0
        case .sum:
            return rgb.x + rgb.y + rgb.z
        case .norm:
            return (rgb.x * rgb.x + rgb.y * rgb.y + rgb.z * rgb.z).squareRoot()
        case .power:
            let r = rgb.x * rgb.x, g = rgb.y * rgb.y, b = rgb.z * rgb.z
            return (rgb.x * r + rgb.y * g + rgb.z * b) / (r + g + b)
        case .none:
            return (rgb.x + rgb.y + rgb.z) / 3.0
        }
    }
}
