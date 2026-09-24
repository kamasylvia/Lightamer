import Foundation
import LightamerCore
import Vision

// ─────────────────────────────────────────────────────────────────────────
// SkinRegionLocator (Plan 07-2 T3) — the AI-05 skin-mask geometry chain:
//
//   VNDetectFaceLandmarksRequest landmarks
//     → faceContour hull + forehead band closure (eyebrow-top lift)
//     − (eyes ∪ brows ∪ outerLips ∪ nostrils) protection zones
//     → per-face mask, multi-face UNION
//     ⊗ VNGeneratePersonSegmentationRequest person matte
//     → skin mask plane → bake(featherRadius:) (the 07-1 feather rides
//       RasterMaskStore.bake — no new mask primitive)
//
// PURITY CONTRACT (the testability hinge): the geometry is PURE SWIFT on
// synthesized point lists — no model inference needed to unit-test hull /
// protection / union / yaw gate (07-RESEARCH §2.2). Vision only SUPPLIES
// the point lists, through the injected `FaceLandmarkProviding` seam (the
// 07-1 AIMaskService handler/fence/device skeleton reused — the provider
// never touches the Metal pipe).
//
// COORDINATES: everything image-NORMALIZED with a TOP-LEFT origin (view
// convention — the same space the mask plane rasterizes into, row 0 =
// image top). The Vision (lower-left, boundingBox-relative) → this space
// conversion is `FaceLandmarkSet.init(faceBox:regionPoints:)` — the
// Swift equivalent of `VNImagePointForFaceLandmarkPoint` at roll ≈ 0
// (the roll-rotated variant is not needed for the ±45° yaw gate's
// working range; DECISIONS D-07-2-T3-3).
//
// YAW GATE (T3 action 2): |yaw| > limit (default 45°) faces are EXCLUDED
// from the union with a typed WARNING (never a silently bad mask); a
// run where every face was gated produces `SkinRegionError.noUsableFace`
// (still no mask — the generation-failure strictness, 07-CONTEXT
// 継承定案「生成失败 ≠ load 失败」).
//
// EMPTY LANDMARKS: a face without a usable faceContour is a typed error
// (`.emptyLandmarks`) — not an all-ones/blank degrade.
// ─────────────────────────────────────────────────────────────────────────

// MARK: - Face landmark payload (post-conversion, top-left normalized)

/// One face's landmark set, already converted to image-normalized
/// TOP-LEFT coordinates ∈ [0,1]. Vision only ever fills this; tests
/// synthesize it directly.
public struct FaceLandmarkSet: Sendable, Equatable {

    /// The face outline polyline (jaw, ear-to-ear, U-open at the forehead —
    /// the forehead band closes it at hull time).
    public var faceContour: [SIMD2<Double>]
    public var leftEye: [SIMD2<Double>]
    public var rightEye: [SIMD2<Double>]
    public var leftEyebrow: [SIMD2<Double>]
    public var rightEyebrow: [SIMD2<Double>]
    public var outerLips: [SIMD2<Double>]
    public var nostrils: [SIMD2<Double>]
    /// Face yaw in DEGREES (positive = looking right per Vision). nil =
    /// unknown (no gate).
    public var yawDegrees: Double?

    public init(
        faceContour: [SIMD2<Double>],
        leftEye: [SIMD2<Double>] = [],
        rightEye: [SIMD2<Double>] = [],
        leftEyebrow: [SIMD2<Double>] = [],
        rightEyebrow: [SIMD2<Double>] = [],
        outerLips: [SIMD2<Double>] = [],
        nostrils: [SIMD2<Double>] = [],
        yawDegrees: Double? = nil
    ) {
        self.faceContour = faceContour
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.leftEyebrow = leftEyebrow
        self.rightEyebrow = rightEyebrow
        self.outerLips = outerLips
        self.nostrils = nostrils
        self.yawDegrees = yawDegrees
    }

    /// The bounding box of the contour points (normalized, top-left).
    public var contourBounds: (min: SIMD2<Double>, max: SIMD2<Double>)? {
        guard let first = faceContour.first else { return nil }
        var lo = first, hi = first
        for p in faceContour {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        return (lo, hi)
    }

    /// The Vision → top-left conversion (boundingBox-relative,
    /// lower-left-origin region points → image-normalized top-left) —
    /// the `VNImagePointForFaceLandmarkPoint` equivalent at roll ≈ 0:
    ///
    ///   image.x = bb.x + p.x · bb.w
    ///   image.y = 1 − (bb.y + p.y · bb.h)     (the Y flip)
    ///
    /// `faceBox` is the Vision-normalized bounding rect (lower-left
    /// origin). `internal` for the coordinate unit test.
    static func convert(
        _ points: [SIMD2<Double>], faceBox: SIMD4<Double>
    ) -> [SIMD2<Double>] {
        points.map { p in
            SIMD2<Double>(
                x: faceBox.x + p.x * faceBox.z,
                y: 1.0 - (faceBox.y + p.y * faceBox.w))
        }
    }

    /// Build from a Vision `FaceObservation`'s region point lists (each in
    /// boundingBox-relative normalized coordinates). Throws
    /// `SkinRegionError.emptyLandmarks` when the face has no contour.
    public init(
        faceBox: SIMD4<Double>, // (x, y, w, h) lower-left normalized
        contour: [SIMD2<Double>],
        leftEye: [SIMD2<Double>],
        rightEye: [SIMD2<Double>],
        leftEyebrow: [SIMD2<Double>],
        rightEyebrow: [SIMD2<Double>],
        outerLips: [SIMD2<Double>],
        nostrils: [SIMD2<Double>],
        yawDegrees: Double?
    ) throws {
        guard contour.count >= 3 else {
            throw SkinRegionError.emptyLandmarks(
                reason: "faceContour has \(contour.count) points (< 3)")
        }
        self.faceContour = Self.convert(contour, faceBox: faceBox)
        self.leftEye = Self.convert(leftEye, faceBox: faceBox)
        self.rightEye = Self.convert(rightEye, faceBox: faceBox)
        self.leftEyebrow = Self.convert(leftEyebrow, faceBox: faceBox)
        self.rightEyebrow = Self.convert(rightEyebrow, faceBox: faceBox)
        self.outerLips = Self.convert(outerLips, faceBox: faceBox)
        self.nostrils = Self.convert(nostrils, faceBox: faceBox)
        self.yawDegrees = yawDegrees
    }
}

// MARK: - Errors and warnings (typed faces — no silent degradation)

public enum SkinRegionError: Error, Equatable, Sendable {
    /// Zero faces detected — no mask (NOT an all-ones degrade).
    case noFaces
    /// Faces existed but the yaw gate excluded every one.
    case noUsableFace(gated: Int)
    /// A face had no usable landmark contour.
    case emptyLandmarks(reason: String)
}

public enum SkinRegionWarning: Equatable, Sendable {
    /// The face at `index` exceeded the yaw limit and was excluded.
    case faceExcludedHighYaw(index: Int, yawDegrees: Double, limitDegrees: Double)
    /// A protection region was missing/empty and skipped (the rest of the
    /// face mask is still valid — surfaced, not swallowed).
    case protectionRegionSkipped(face: Int, region: String)
}

// MARK: - Configuration (the geometry knobs — UI sliders land in 07-3)

public struct SkinRegionConfig: Sendable, Equatable {

    /// Hull outward expansion, as a fraction of the contour bounds'
    /// diagonal (DECISIONS D-07-2-T3-1: 6% — covers the Vision contour's
    /// skin-edge undercut).
    public var hullExpand: Double
    /// Forehead top lift above the eyebrow-top line, as a fraction of the
    /// contour bounds' HEIGHT (D-07-2-T3-2: 12% — the forehead band).
    public var foreheadLift: Double
    /// Protection-zone shrink toward each region's centroid (D-07-2-T3-1:
    /// 0.78 — the inward margin so lashes/lip edges stay inside the
    /// protection, not on the boundary).
    public var protectShrink: Double
    /// Yaw gate limit in degrees (plan T3: 45°).
    public var yawLimitDegrees: Double
    /// The bake-time feather radius in px (rides RasterMaskStore.bake's
    /// featherRadius — the 07-1 primitive; the locator itself stays
    /// crisp-edged so the geometry tests pin exact boundaries).
    public var featherRadius: Float

    public init(
        hullExpand: Double = 0.06,
        foreheadLift: Double = 0.12,
        protectShrink: Double = 0.78,
        yawLimitDegrees: Double = 45.0,
        featherRadius: Float = 4.0
    ) {
        self.hullExpand = hullExpand
        self.foreheadLift = foreheadLift
        self.protectShrink = protectShrink
        self.yawLimitDegrees = yawLimitDegrees
        self.featherRadius = featherRadius
    }
}

// MARK: - Pure geometry (Double, no Metal, no Vision)

public enum SkinGeometry {

    /// Andrew's monotone chain convex hull. Output is counter-clockwise,
    /// starting at the lexicographically smallest point. < 3 distinct
    /// points returns the input (degenerate — callers gate).
    public static func convexHull(_ points: [SIMD2<Double>]) -> [SIMD2<Double>] {
        let pts = points.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        guard pts.count >= 3 else { return pts }
        func cross(_ o: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [SIMD2<Double>] = []
        for p in pts {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }
        var upper: [SIMD2<Double>] = []
        for p in pts.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    /// Even-odd ray casting (boundary-inclusive at the polygon's own
    /// vertices is not needed — the rasterizer samples pixel centers).
    public static func pointInPolygon(_ p: SIMD2<Double>, _ poly: [SIMD2<Double>]) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let xAtY = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < xAtY { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    public static func centroid(_ poly: [SIMD2<Double>]) -> SIMD2<Double> {
        guard !poly.isEmpty else { return .zero }
        var sum = SIMD2<Double>.zero
        for p in poly { sum += p }
        return sum / Double(poly.count)
    }

    /// Uniform scale about `center` (convexity-preserving — the hull
    /// expansion and protection shrink both go through here).
    public static func scaleAbout(
        _ poly: [SIMD2<Double>], center: SIMD2<Double>, factor: Double
    ) -> [SIMD2<Double>] {
        poly.map { center + ($0 - center) * factor }
    }
}

// MARK: - The locator (pure CPU rasterization)

public enum SkinRegionLocator {

    /// The face's skin polygon: contour hull ∪ forehead band, expanded.
    /// Returns nil when the face has no contour bounds (degenerate).
    public static func facePolygon(
        _ face: FaceLandmarkSet, config: SkinRegionConfig
    ) -> [SIMD2<Double>]? {
        guard let bounds = face.contourBounds else { return nil }
        let diag = simd_distance(bounds.min, bounds.max)
        guard diag > 0 else { return nil }

        // The forehead band: three synthetic points above the eyebrow-top
        // line spanning the brows' horizontal extent (the hull's top edge
        // closes the contour's U — D-07-2-T3-2).
        let browTops = (face.leftEyebrow + face.rightEyebrow)
        var foreheadY = bounds.min.y
        var spanMinX = bounds.min.x
        var spanMaxX = bounds.max.x
        if !browTops.isEmpty {
            foreheadY = browTops.map(\.y).min()!
            foreheadY -= (bounds.max.y - bounds.min.y) * config.foreheadLift
            spanMinX = min(browTops.map(\.x).min()!, spanMinX)
            spanMaxX = max(browTops.map(\.x).max()!, spanMaxX)
        }
        let midX = (spanMinX + spanMaxX) / 2
        let band: [SIMD2<Double>] = [
            SIMD2(x: spanMinX, y: foreheadY),
            SIMD2(x: midX, y: foreheadY),
            SIMD2(x: spanMaxX, y: foreheadY),
        ]

        let hull = SkinGeometry.convexHull(face.faceContour + band)
        guard hull.count >= 3 else { return nil }
        // Outward expansion about the hull centroid (a fraction of the
        // contour diagonal, not of 1 — resolution-independent).
        return SkinGeometry.scaleAbout(
            hull, center: SkinGeometry.centroid(hull),
            factor: 1.0 + config.hullExpand)
    }

    /// The face's protection zones: each region's hull shrunk toward its
    /// own centroid (empty regions are skipped with a warning).
    public static func protectionPolygons(
        _ face: FaceLandmarkSet, config: SkinRegionConfig, faceIndex: Int
    ) -> (polygons: [[SIMD2<Double>]], warnings: [SkinRegionWarning]) {
        let regions: [(name: String, points: [SIMD2<Double>])] = [
            ("leftEye", face.leftEye),
            ("rightEye", face.rightEye),
            ("leftEyebrow", face.leftEyebrow),
            ("rightEyebrow", face.rightEyebrow),
            ("outerLips", face.outerLips),
            ("nostrils", face.nostrils),
        ]
        var polygons: [[SIMD2<Double>]] = []
        var warnings: [SkinRegionWarning] = []
        for region in regions {
            guard region.points.count >= 3 else {
                if !region.points.isEmpty {
                    warnings.append(
                        .protectionRegionSkipped(face: faceIndex, region: region.name))
                }
                continue
            }
            let hull = SkinGeometry.convexHull(region.points)
            guard hull.count >= 3 else { continue }
            polygons.append(SkinGeometry.scaleAbout(
                hull, center: SkinGeometry.centroid(hull), factor: config.protectShrink))
        }
        return (polygons, warnings)
    }

    /// Rasterize the per-face mask (1 inside hull, 0 inside any protection
    /// zone) at `width × height`. Pure CPU — the geometry-test seam.
    public static func faceMask(
        _ face: FaceLandmarkSet, width: Int, height: Int, config: SkinRegionConfig
    ) -> [Float]? {
        guard let hull = facePolygon(face, config: config) else { return nil }
        let protect = protectionPolygons(face, config: config, faceIndex: 0).polygons
        var mask = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            // Pixel centers, normalized, top-left origin (row 0 = image top).
            let ny = (Double(y) + 0.5) / Double(height)
            for x in 0..<width {
                let nx = (Double(x) + 0.5) / Double(width)
                let p = SIMD2<Double>(x: nx, y: ny)
                guard SkinGeometry.pointInPolygon(p, hull) else { continue }
                var protected = false
                for poly in protect where SkinGeometry.pointInPolygon(p, poly) {
                    protected = true
                    break
                }
                if !protected {
                    mask[y * width + x] = 1
                }
            }
        }
        return mask
    }

    /// The full skin mask: yaw-gated faces, unioned, ⊗ the person matte
    /// (resampled to the target size when it differs — bilinear, the
    /// 07-1 AIMaskResample leg). THROWS on the no-mask legs (noFaces /
    /// noUsableFace / emptyLandmarks) — the generation-failure strictness.
    public static func skinMask(
        faces: [FaceLandmarkSet],
        personMatte: AIMaskPlane?,
        width: Int,
        height: Int,
        config: SkinRegionConfig = SkinRegionConfig()
    ) throws -> (plane: AIMaskPlane, warnings: [SkinRegionWarning]) {
        guard !faces.isEmpty else { throw SkinRegionError.noFaces }

        var usable: [(index: Int, face: FaceLandmarkSet)] = []
        var warnings: [SkinRegionWarning] = []
        for (index, face) in faces.enumerated() {
            if let yaw = face.yawDegrees, abs(yaw) > config.yawLimitDegrees {
                warnings.append(
                    .faceExcludedHighYaw(
                        index: index, yawDegrees: yaw, limitDegrees: config.yawLimitDegrees))
                continue
            }
            guard face.faceContour.count >= 3 else {
                throw SkinRegionError.emptyLandmarks(
                    reason: "face \(index) contour has \(face.faceContour.count) points")
            }
            usable.append((index, face))
        }
        guard !usable.isEmpty else {
            throw SkinRegionError.noUsableFace(gated: faces.count)
        }

        // Union of per-face masks + per-face protection warnings.
        var union = [Float](repeating: 0, count: width * height)
        for (slot, entry) in usable.enumerated() {
            guard var mask = faceMask(entry.face, width: width, height: height, config: config)
            else { continue }
            warnings.append(
                contentsOf: protectionPolygons(
                    entry.face, config: config, faceIndex: entry.index
                ).warnings)
            for i in 0..<union.count {
                union[i] = max(union[i], mask[i])
            }
            mask.removeAll()
        }

        // ⊗ person matte (exclude background skin-toned objects).
        if let matte = personMatte {
            let plane: AIMaskPlane
            if matte.width == width && matte.height == height {
                plane = matte
            } else {
                plane = AIMaskResample.bilinear(matte, toWidth: width, toHeight: height)
            }
            for i in 0..<union.count {
                union[i] = min(union[i], plane.floats[i])
            }
        }
        return (AIMaskPlane(width: width, height: height, floats: union), warnings)
    }
}

// MARK: - Vision provider (the injected inference seam)

/// The face-landmark inference seam — pure geometry tests inject a stub;
/// production runs `VisionFaceLandmarkProvider` (the 07-1 AIMaskService
/// handler/device skeleton, L014 fence at `AIMaskInput`).
public protocol FaceLandmarkProviding: Sendable {
    func detectFaces(input: AIMaskInput, device: AIDevicePolicy) async throws -> [FaceLandmarkSet]
}

/// The production provider: `DetectFaceLandmarksRequest` → converted
/// `FaceLandmarkSet`s. Device pinning follows AIMaskService's validated
/// policy (an impossible pin is a typed `AIMaskError`, never a trap).
public struct VisionFaceLandmarkProvider: FaceLandmarkProviding {

    public init() {}

    public func detectFaces(
        input: AIMaskInput, device: AIDevicePolicy = .anePreferred
    ) async throws -> [FaceLandmarkSet] {
        var request = DetectFaceLandmarksRequest()
        try AIMaskService.apply(device, toFaceLandmarks: &request)
        let handler = ImageRequestHandler(input.ciImage)
        do {
            let observations = try await handler.perform(request)
            var faces: [FaceLandmarkSet] = []
            for observation in observations {
                guard let landmarks = observation.landmarks else { continue }
                let bb = observation.boundingBox
                let faceBox = SIMD4<Double>(
                    Double(bb.origin.x), Double(bb.origin.y),
                    Double(bb.width), Double(bb.height))
                func pts(_ region: FaceObservation.Landmarks2D.Region?) -> [SIMD2<Double>] {
                    region?.points.map {
                        SIMD2<Double>(x: Double($0.x), y: Double($0.y))
                    } ?? []
                }
                let yaw = observation.yaw.converted(to: .degrees).value
                let face = try FaceLandmarkSet(
                    faceBox: faceBox,
                    contour: pts(landmarks.faceContour),
                    leftEye: pts(landmarks.leftEye),
                    rightEye: pts(landmarks.rightEye),
                    leftEyebrow: pts(landmarks.leftEyebrow),
                    rightEyebrow: pts(landmarks.rightEyebrow),
                    outerLips: pts(landmarks.outerLips),
                    nostrils: pts(landmarks.nose), // the nose region (nostril outline)
                    yawDegrees: yaw)
                faces.append(face)
            }
            return faces
        } catch let error as SkinRegionError {
            throw error
        } catch {
            throw AIMaskError.inferenceFailed(String(describing: error))
        }
    }
}

// MARK: - The locate service (the 07-3 「定位皮肤」button's backend)

public enum SkinRegionService {

    /// Run the full chain: landmarks (provider) + optional person matte
    /// (AIMaskService personSegmentationMask, quality .accurate) →
    /// `SkinRegionLocator.skinMask`. No bake here — the caller (07-3 UI)
    /// bakes via `RasterMaskStore.bake(featherRadius:)` so the mask lands
    /// in the standard Phase 6 raster channel.
    public static func locate(
        input: AIMaskInput,
        width: Int,
        height: Int,
        config: SkinRegionConfig = SkinRegionConfig(),
        withPersonMatte: Bool = true,
        device: AIDevicePolicy = .anePreferred,
        landmarks: FaceLandmarkProviding = VisionFaceLandmarkProvider()
    ) async throws -> (plane: AIMaskPlane, warnings: [SkinRegionWarning]) {
        async let facesTask = landmarks.detectFaces(input: input, device: device)
        var personMatte: AIMaskPlane?
        if withPersonMatte {
            // Same-inference quality (.accurate per 07-CONTEXT 継承定案).
            personMatte = try? await AIMaskService.personSegmentationMask(
                input: input, quality: .accurate, device: device)
        }
        let faces = try await facesTask
        return try SkinRegionLocator.skinMask(
            faces: faces, personMatte: personMatte,
            width: width, height: height, config: config)
    }

    /// Bake a located skin mask into the standard raster channel (the
    /// feather rides the 07-1 bake primitive — `config.featherRadius`).
    public static func bake(
        skinMask: AIMaskPlane, directory: URL, fileName: String,
        invert: Bool = false, config: SkinRegionConfig,
        metal: MetalContext
    ) async throws -> RasterMaskRef {
        try await RasterMaskStore.bake(
            plane: AIMaskResample.texture(from: skinMask, metal: metal),
            directory: directory,
            fileName: fileName,
            invert: invert,
            featherRadius: config.featherRadius,
            metal: metal)
    }
}
