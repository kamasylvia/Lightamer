import Foundation
import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// WATERMARK — the yiyin 终局水印 module (Plan 08-2, YIYIN-02..05; v50 slot
// 77.0 — ALREADY in the V50Order table, zero rows inserted). The functional
// spec is the yiyin text system (RESEARCH §1.3/§1.4; the dt `watermark.c`
// SVG/position face is NOT ported): template rows `{Field}`-filled from the
// capture EXIF, rendered per-row (CoreText, T4) and stacked bottom-up on
// the terminal canvas.
//
// DOMAIN: display-referred terminal segment, AFTER borders (76.0) — the
// input plane is the borders OUTPUT (the grown canvas) when borders is
// active, or the untouched main image otherwise (the watermark-only face,
// D-08-CONTEXT Specific Ideas: 画布即原图、文字直接叠主图).
//
// JOINT LAYOUT (08-CONTEXT 继承定案): the borders canvas RESERVES the text
// block. The watermark owns the ROWS — it computes the joint record via
// `YiyinLayout.layout` (two-pass canvas + row stacking) from:
//   mainImageSize ⊕ borders params ⊕ row metrics
// The per-run injection seam is `jointContext` (the 8-3 coordinator wires
// it from the borders instance record; tests inject directly). When the
// borders instance is ABSENT/neutral the yiyin formula is NOT used (its
// ceil-quirk can grow a canvas that is in fact identity — D-08-1-2); the
// watermark-only placement stacks rows directly on the image instead.
//
// SEED (enabled-neutral): the 3 system templates present but ALL use=false
// → rowless → byte-identical blit (exposure-0EV style; D-08-CONTEXT-4 —
// 新图不自动挂默认印框/水印: the seed carries the panel's instance, it
// never applies a look).
//
// EXIF: `captureExif` is the per-image CaptureMetadata injection (the 8-3
// walk fills CaptureMetadata; the coordinator feeds the box). It does NOT
// enter the params hash — params are per-image CONFIG, the values are
// per-image DATA (the text cache keys fold them in, T4).
// ─────────────────────────────────────────────────────────────────────────

public final class WatermarkModule: IOPModule {

    public static let opName = "watermark"

    /// v50 order 77.0 (V50Order table, verbatim Darktable position —
    /// between borders 76.0 and gamma 78.0; display-referred seam).
    public static let iopOrder: Float = 77.0

    /// dt flags analog: single-instance, tiling NEVER (a whole-canvas
    /// overlay — same tile contract as borders, D-08-1-3 twin).
    public static let flags: IOPFlags = [.oneInstance]

    public static let defaultColorspace: IOPColorspace = .RGB

    public struct Params: Codable, Hashable, Sendable {
        /// Template rows (list order = the yiyin stacking order — the LAST
        /// active row lands nearest the bottom).
        public var templates: [YiyinTemplate]
        /// The row-level default font (the yiyin `options.font` family seat
        /// + the panel's default font settings; templates override).
        public var font: YiyinFont
        /// The field configs (the yiyin `tempFields` list).
        public var fields: [YiyinField]
        /// The date pattern (default `yyyy/MM/dd hh:mm:ss`).
        public var dateFormat: String
        /// The row text margin as % of the canvas height (yiyin
        /// `text_margin`, default 0.4).
        public var lineSpacing: Double
        /// The text-block anchor (D-08-CONTEXT-2 — nine-grid extension;
        /// `.bottomCenter` is the yiyin-exact default).
        public var anchor: YiyinNineGridAnchor
        /// Logo slot opacity 0...1 (D-08-CONTEXT-2's low-cost-high-value
        /// addition; text rows are unaffected).
        public var logoOpacity: Double

        public init(
            templates: [YiyinTemplate] = YiyinTemplate.systemDefaults(),
            font: YiyinFont = YiyinFont(),
            fields: [YiyinField] = Self.defaultFields,
            dateFormat: String = "yyyy/MM/dd hh:mm:ss",
            lineSpacing: Double = 0.4,
            anchor: YiyinNineGridAnchor = .bottomCenter,
            logoOpacity: Double = 1
        ) {
            self.templates = templates
            self.font = font
            self.fields = fields
            self.dateFormat = dateFormat
            self.lineSpacing = lineSpacing
            self.anchor = anchor
            self.logoOpacity = logoOpacity
        }

        /// The 15-field config list in def-fields order (yiyin config.ts
        /// getDefConf: show true / use false / forceUse false / type text).
        public static var defaultFields: [YiyinField] {
            YiyinExifField.allCases.map { YiyinField(key: $0.rawValue) }
        }

        /// The enabled-neutral seed: the system catalog present but ALL
        /// rows OFF → rowless → byte-identical blit (D-08-CONTEXT-4).
        public static var neutralSeed: Params {
            var p = Params()
            p.templates = YiyinTemplate.systemDefaults().map {
                var t = $0
                t.use = false
                return t
            }
            return p
        }
    }

    /// The commit-clamped working copy (dt `piece->data` analog).
    private var committed: Params = Params.neutralSeed

    public init() {}

    /// Fresh images: the rowless seed (D-08-CONTEXT-4 — the watermark look
    /// applies only through explicit user action).
    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params.neutralSeed
    }

    /// dt `commit_params`: clamp into the working copy, hash the RAW
    /// params (ParamsCoding + StableHash — L013).
    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        committed = Self.clamp(params)
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        piece.data = nil
    }

    /// Input clamps: opacity 0...1, lineSpacing 0...100, sizes ≥ 0.
    static func clamp(_ params: Params) -> Params {
        var out = params
        out.lineSpacing = min(max(params.lineSpacing, 0), 100)
        out.logoOpacity = min(max(params.logoOpacity, 0), 1)
        out.font.sizePercent = max(params.font.sizePercent, 0)
        for index in out.templates.indices {
            out.templates[index].font.sizePercent =
                max(out.templates[index].font.sizePercent, 0)
        }
        return out
    }

    // MARK: - Per-run injections (8-3 wiring; tests inject directly)

    /// The per-image capture EXIF (formatted by `YiyinExifFormat` at
    /// process time). nil = no EXIF → every field's display value is ""
    /// (forceUse custom values still render).
    public var captureExif: CaptureMetadata?

    /// The personal-sign free text (the PersonalSign display value).
    public var personalSign: String?

    /// The joint-layout context: the MAIN IMAGE size (the borders piece's
    /// dscIn) + the borders instance's committed params. nil = the borders
    /// instance is absent/disabled → the watermark-only face (canvas ==
    /// image). A borders instance with NEUTRAL params also renders the
    /// watermark-only face (the yiyin formula's ceil-quirk must never size
    /// a canvas that is in fact identity — D-08-1-2).
    public struct JointContext: Sendable {
        public var mainImageSize: SIMD2<Int>
        public var bordersParams: BordersModule.Params?

        public init(mainImageSize: SIMD2<Int>, bordersParams: BordersModule.Params?) {
            self.mainImageSize = mainImageSize
            self.bordersParams = bordersParams
        }
    }

    public var jointContext: JointContext?

    /// The timezone the capture time formats in (capture-local; injectable
    /// for determinism in tests).
    public var captureTimeZone: TimeZone = .current

    // MARK: - Resolution (the engine + format layers)

    /// The engine inputs for THIS run (the pass-1 canvas height is the
    /// font % basis — yiyin's two-pass order).
    func engineInputs(bgHeight: Double) -> YiyinTemplateEngine.Inputs {
        let bordersP = jointContext?.bordersParams
        let backdropIsBlur: Bool
        if case .blur = bordersP?.mode {
            backdropIsBlur = true
        } else {
            backdropIsBlur = false
        }
        return YiyinTemplateEngine.Inputs(
            fields: YiyinExifFormat.fields(
                from: captureExif, personalSign: personalSign,
                dateFormat: committed.dateFormat, timeZone: captureTimeZone),
            fieldConfigs: Dictionary(uniqueKeysWithValues: committed.fields.map { ($0.key, $0) }),
            defaultFont: committed.font,
            backdropIsBlur: backdropIsBlur,
            bgHeight: bgHeight,
            logoExists: logoExists)
    }

    /// The active template list (list order = stacking order).
    func activeTemplates() -> [YiyinTemplate] {
        committed.templates.filter { $0.use }
    }

    /// Resolve the rows WITHOUT metrics (the existence face — drives the
    /// identity fast path). Empty = the render is a no-op.
    func resolvedRows(inputs: YiyinTemplateEngine.Inputs) -> [YiyinTemplateEngine.ResolvedRow] {
        activeTemplates().compactMap { YiyinTemplateEngine.resolve(template: $0, inputs: inputs) }
    }

    // MARK: - Layout (the joint rows leg)

    /// The pipe-level coordinator's joint-record face (08-3 wiring,
    /// D-08-2-10): compute the joint layout record for the given
    /// main-image plane size and borders params from THIS module's
    /// committed params + injected context (captureExif / logo faces /
    /// jointContext — the coordinator injects them BEFORE calling this;
    /// `jointContext.bordersParams` drives the blur→white logo dispatch
    /// inside `engineInputs`). The record then rides
    /// `BordersModule.jointLayoutOverride` so borders reserves the text
    /// band from the SAME computation (one record, two consumers).
    /// nil = no reserve needed (borders absent/neutral, or no resolved
    /// rows) — borders keeps its local empty-rows layout.
    public func makeJointLayoutRecord(
        mainImageSize: SIMD2<Int>, bordersParams: BordersModule.Params?
    ) -> YiyinLayoutRecord? {
        let bordersP = bordersParams ?? BordersModule.Params.neutralSeed
        let bordersActive = bordersParams.map { !isNeutralBorders($0) } ?? false
        guard bordersActive else { return nil }
        let bgHeight = Double(
            YiyinLayout.firstPassCanvasSize(imageSize: mainImageSize, borders: bordersP).y)
        let inputs = engineInputs(bgHeight: bgHeight)
        let rows = resolvedRows(inputs: inputs)
        guard !rows.isEmpty else { return nil }
        let metrics = rows.map {
            renderer.layoutRow(
                row: $0, bgHeight: bgHeight,
                lineSpacingPercent: committed.lineSpacing,
                logoProvider: logoProvider).metrics
        }
        return YiyinLayout.layout(
            imageSize: mainImageSize, borders: bordersP, rows: metrics)
    }

    /// The pass-1 canvas (the font-sizing basis, yiyin `clacBgImgSize()`
    /// default). Borders-absent/neutral → the image itself.
    func pass1CanvasHeight(mainImageSize: SIMD2<Int>) -> Int {
        let bordersP = jointContext?.bordersParams ?? BordersModule.Params.neutralSeed
        let bordersActive = jointContext?.bordersParams.map { !isNeutralBorders($0) } ?? false
        guard bordersActive else { return mainImageSize.y }
        return YiyinLayout.firstPassCanvasSize(
            imageSize: mainImageSize, borders: bordersP).y
    }

    /// The borders-neutral predicate (BordersModule.isNeutral is internal
    /// to its type — mirror the param face here; the seed identity is
    /// PARAM-based, D-08-1-2).
    private func isNeutralBorders(_ p: BordersModule.Params) -> Bool {
        guard p.mainImageWidthRate >= 100, p.miniTopBottomMargin == 0,
            p.aspectRatio == nil, !p.landscapeOutput,
            p.cornerRadius == nil || p.cornerRadius! <= 0,
            p.shadow == nil || p.shadow! <= 0
        else { return false }
        return true
    }

    /// The effective row placement for THIS run: the joint record's rows
    /// when borders is active, else the watermark-only stacking (canvas ==
    /// image). `metrics` = the CoreText-measured rows (T4) in LIST ORDER.
    func placedRows(mainImageSize: SIMD2<Int>, metrics: [YiyinLayout.TextRowMetrics]) -> (
        rows: [YiyinLayoutRecord.PlacedRow], canvas: SIMD2<Int>
    ) {
        let bordersP = jointContext?.bordersParams ?? BordersModule.Params.neutralSeed
        let bordersActive = jointContext?.bordersParams.map { !isNeutralBorders($0) } ?? false
        if bordersActive {
            let record = YiyinLayout.layout(
                imageSize: mainImageSize, borders: bordersP, rows: metrics)
            let rows = YiyinLayout.applyAnchor(
                committed.anchor, rows: record.rows, canvas: record.canvasSize,
                marginPx: record.textBottomOffsetPx)
            return (rows, record.canvasSize)
        }
        // Watermark-only: canvas == image (D-08-CONTEXT Specific Ideas);
        // the bottom margin = the yiyin slot fraction (the borders param
        // when injected, else the 0.027 constant) of the IMAGE height.
        let offsetFraction = jointContext?.bordersParams?.textBottomOffset ?? 0.027
        let offset = Double(mainImageSize.y) * offsetFraction
        let stacked = YiyinLayout.stackRows(
            rows: metrics, canvasWidth: mainImageSize.x, canvasHeight: mainImageSize.y,
            bottomOffsetPx: offset)
        let rows = YiyinLayout.applyAnchor(
            committed.anchor, rows: stacked, canvas: mainImageSize, marginPx: offset)
        return (rows, mainImageSize)
    }

    // MARK: - Process

    /// Kernel function name (`YiyinKernels.metal`; the Registry prewarm
    /// list consumes it).
    static let kernelRow = "yiyin_watermark_row"

    /// The module-owned CoreText renderer (its row-bitmap cache lives
    /// here — single-owner like every box-owned scratch).
    public let renderer = YiyinTextRenderer()

    /// The logo slot provider (the YiyinLogoStore wires this — T5; nil =
    /// every logo slot renders as whitespace). MEASURE and RENDER see the
    /// same answers (the provider contract).
    public var logoProvider: YiyinLogoProvider?

    /// The engine's logo-existence probe (the Make-slot dispatch gate —
    /// wire from YiyinLogoStore.embeddedExists; nil = no asset store →
    /// every Make degrades to text).
    public var logoExists: YiyinTemplateEngine.LogoExists?

    /// The display override twin (BordersModule/ColorOutModule): the row
    /// color matrix follows the resolved display profile. nil = the
    /// current screen.
    public var displayProfileOverride: DisplayProfile?

    /// The row uniforms (the MSL `YiyinRowUniforms` mirror — all-4-byte
    /// members keep the layouts identical, no float3 alignment hazards).
    struct RowUniforms {
        var rowW: Int32
        var rowH: Int32
        var destX: Int32
        var destY: Int32
        var planeW: Int32
        var planeH: Int32
        var pad0: Float
        var pad1: Float
        var cm: (Float, Float, Float, Float, Float, Float, Float, Float, Float)
    }

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        let mainImageSize = SIMD2(
            max(jointContext?.mainImageSize.x ?? input.width, 1),
            max(jointContext?.mainImageSize.y ?? input.height, 1))
        let bgHeight = Double(pass1CanvasHeight(mainImageSize: mainImageSize))
        let inputs = engineInputs(bgHeight: bgHeight)
        let rows = resolvedRows(inputs: inputs)

        // The identity fast path: no resolved rows → byte-identical blit
        // (空模板/全字段关 == 无实例).
        guard !rows.isEmpty else {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }

        // The joint rows leg: FULL-WINDOW blit first (the pipe expects the
        // whole output plane written — the rows only patch their rects),
        // then measure → place → composite each row. Same-queue FIFO
        // orders the blit before the row encoders.
        try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
        let metrics = rows.map { row in
            renderer.layoutRow(
                row: row, bgHeight: bgHeight,
                lineSpacingPercent: committed.lineSpacing,
                logoProvider: logoProvider).metrics
        }
        let (placed, _) = placedRows(mainImageSize: mainImageSize, metrics: metrics)
        precondition(
            placed.count == rows.count,
            "placedRows count (\(placed.count)) != resolved rows (\(rows.count))")

        var target: DisplayProfile
        if let override = displayProfileOverride {
            target = override
        } else {
            target = .current()
        }
        let matrix = YiyinColor.sRGBToDisplayMatrixRows(target: target)

        for (index, placedRow) in placed.enumerated() {
            let bitmap = renderer.renderRow(
                row: rows[index], bgHeight: bgHeight,
                lineSpacingPercent: committed.lineSpacing,
                logoOpacity: committed.logoOpacity,
                logoProvider: logoProvider)
            try await compositeRow(
                bitmap: bitmap, placed: placedRow, input: input, output: output,
                roiOut: roiOut, matrix: matrix, metal: metal)
        }
    }

    /// Upload the row bitmap and dispatch the composite over the row's
    /// extent (the kernel clips to the output plane — windowed rendering
    /// only pays for the visible slice).
    func compositeRow(
        bitmap: YiyinRowBitmap,
        placed: YiyinLayoutRecord.PlacedRow,
        input: any MTLTexture,
        output: any MTLTexture,
        roiOut: ROI,
        matrix: [Float],
        metal: MetalContext
    ) async throws {
        precondition(matrix.count == 9)
        let texture = try Self.makeRowTexture(bitmap: bitmap, metal: metal)
        var u = RowUniforms(
            rowW: Int32(bitmap.width), rowH: Int32(bitmap.height),
            destX: Int32(placed.left - roiOut.x), destY: Int32(placed.top - roiOut.y),
            planeW: Int32(output.width), planeH: Int32(output.height),
            pad0: 0, pad1: 0,
            cm: (matrix[0], matrix[1], matrix[2], matrix[3], matrix[4], matrix[5],
                 matrix[6], matrix[7], matrix[8]))
        guard let buffer = metal.device.makeBuffer(
            bytes: &u, length: MemoryLayout<RowUniforms>.stride,
            options: .storageModeShared)
        else { throw MetalError.deviceUnavailable }

        let session = try await metal.makeEncoder(functionName: Self.kernelRow)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(texture, index: 1)
        session.encoder.setTexture(output, index: 2)
        session.encoder.setBuffer(buffer, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: bitmap.width, height: bitmap.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    /// The rgba8Unorm row texture (UNORM read = the encoded byte / 255 —
    /// the kernel decodes manually). Fresh per row per run — the bitmaps
    /// are the cached artifact (YiyinTextRenderer), the upload is cheap.
    static func makeRowTexture(
        bitmap: YiyinRowBitmap, metal: MetalContext
    ) throws -> (any MTLTexture) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: max(bitmap.width, 1),
            height: max(bitmap.height, 1), mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = metal.device.makeTexture(descriptor: descriptor) else {
            throw MetalError.bufferAllocationFailed(bitmap.width * bitmap.height * 4)
        }
        bitmap.pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: texture.width * 4)
        }
        return texture
    }

    /// The whole-window blit (BordersModule twin — the sync identity path).
    func blitIdentity(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        metal: MetalContext
    ) throws {
        let dx = roiOut.x - roiIn.x
        let dy = roiOut.y - roiIn.y
        guard dx >= 0, dy >= 0 else { return }
        let width = min(roiOut.width, roiIn.width, output.width, max(0, input.width - dx))
        let height = min(roiOut.height, roiIn.height, output.height, max(0, input.height - dy))
        guard width > 0, height > 0 else { return }
        guard let commandBuffer = metal.commandQueue.makeCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            throw MetalError.deviceUnavailable
        }
        blit.copy(
            from: input, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: dx, y: dy, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: output, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding() // L008: encode close precedes commit, never defer
        commandBuffer.commit()
    }

    // MARK: - Tile seam (borders twin, D-08-1-3)

    public func tileHalo(roi: ROI, piece: IOPiece) -> Int { 0 }
    public func tileWorkingSetBytesPerPixel(piece: IOPiece) -> Int { 0 }
}
