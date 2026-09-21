import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────
// NoiseProfileStore (Plan 05-01-T3) — per-camera 噪声剖面加载/匹配/插值。
//
// 数据源：dt `data/noiseprofiles.json` 经构建期规范化转换后内置 bundle
// （`LightamerIOP/Resources/NoiseProfiles/noiseprofiles.json`，转换脚本
// `input/golden/fixtures/gen_noise_profiles.py`；D-05-CONTEXT-2）。
// 标定域 = 传感器线性域（文件头 "raw-raw data"）；方差模型 `var = a·I + b`
// 逐通道（R/G/B）。
//
// dt 语义对照（`src/common/noiseprofiles.c`，树 dc58cf0ba1）：
// - generic（:28）：`{a: 1e-4×3, b: 0}`（纯 Poisson 回落）；
// - 匹配（:227-333）：maker 用子串包含（`g_strstr_len(cimg->camera_maker,
//   -1, json_maker)`——注意方向：EXIF Make 包含 JSON maker 串即命中，如
//   "SONY" 含 "Sony"？不——strstr 大小写敏感，"SONY" 不含 "Sony"；
//   此处逐字直译该语义）、model 用精确相等（`g_strcmp0` 大小写敏感）；
//   `skip:true` 档跳过；结果按 ISO 排序（`g_list_sort _sort_by_iso`）；
// - 插值（:375-390 `dt_noiseprofile_interpolate`）："stupid linear
//   interpolation"——`t = clamp((iso−iso1)/(iso2−iso1), 0, 1)`，a/b 逐通道
//   线性插值。
//
// 设计：值类型 `NoiseProfile`（单档）+ actor `NoiseProfileStore`
// （懒加载：首问才解析 bundle JSON，一次 ~50ms 级；按 maker 建索引缓存）。
// 剖面不进任何跨进程身份（L013——哈希键序风险低，但仍不进身份）。
// EXIF 读取不归此处（RAW-06 的 `CaptureMetadata.cameraMake/cameraModel/iso`
// 已有；消费接线在 05-07，本 plan 只供 API）。
// ─────────────────────────────────────────────────────────────────────────

/// 单 ISO 档噪声剖面（dt `dt_noiseprofile_t` 子集：maker/model/name/iso/a/b）。
public struct NoiseProfile: Sendable, Equatable {
    public var maker: String
    public var model: String
    public var name: String
    public var iso: Double
    /// Poisson 系数（R/G/B）。
    public var a: SIMD3<Double>
    /// Gaussian 基座（R/G/B）。
    public var b: SIMD3<Double>

    public init(
        maker: String, model: String, name: String, iso: Double,
        a: SIMD3<Double>, b: SIMD3<Double>
    ) {
        self.maker = maker
        self.model = model
        self.name = name
        self.iso = iso
        self.a = a
        self.b = b
    }

    /// dt `dt_noiseprofile_generic`（noiseprofiles.c:28）——miss 回落。
    public static var generic: NoiseProfile {
        NoiseProfile(
            maker: "", model: "", name: "generic poissonian", iso: 0,
            a: SIMD3<Double>(repeating: 1e-4), b: SIMD3<Double>(repeating: 0))
    }

    /// ISO 括弧两档线性插值（noiseprofiles.c:375-390 直译）。
    /// - precondition：p1.iso < p2.iso（dt 注释 "the smaller iso" / "can't be == iso1"）。
    /// - 档外：调用方 clamp 首末档（t clamp 在 [0,1] 内，`profile(at:)` 负责）。
    public static func interpolate(
        _ p1: NoiseProfile, _ p2: NoiseProfile, iso: Double
    ) -> NoiseProfile {
        precondition(p1.iso < p2.iso, "interpolate 需要 p1.iso < p2.iso")
        let t = min(max((iso - p1.iso) / (p2.iso - p1.iso), 0.0), 1.0)
        return NoiseProfile(
            maker: p1.maker, model: p1.model,
            name: "interpolated iso \(iso)",
            iso: iso,
            a: (1.0 - t) * p1.a + t * p2.a,
            b: (1.0 - t) * p1.b + t * p2.b)
    }
}

/// 剖面加载/匹配/插值（actor——懒加载 + 按 maker 索引缓存；Sendable）。
public actor NoiseProfileStore {

    /// 解析后的全量档：key = (maker, model)，value = ISO 升序档列（skip 已剔）。
    private var table: [MakerModel: [NoiseProfile]] = [:]
    private var loaded = false

    /// JSON maker 串列表（子串匹配用；保留 JSON 原串——dt `strstr` 语义）。
    private var makerKeys: [String] = []

    private struct MakerModel: Hashable {
        var maker: String
        var model: String
    }

    private struct BundleJSON: Decodable {
        var version: Int
        var noiseprofiles: [MakerEntry]
        struct MakerEntry: Decodable {
            var maker: String
            var models: [ModelEntry]
        }
        struct ModelEntry: Decodable {
            var model: String
            var comment: String?
            var profiles: [ProfileEntry]
        }
        struct ProfileEntry: Decodable {
            var name: String
            var iso: Double
            var a: [Double]
            var b: [Double]
            var skip: Bool?
        }
    }

    public init() {}

    /// 测试 seam：从内存 JSON 数据加载（与 bundle 文件同 schema）。
    public func loadForTests(_ data: Data) throws {
        try load(data: data)
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }
        // Tuist/Xcode 资源相位把 noiseprofiles.json 拍平进 bundle 根
        // （无 NoiseProfiles 子目录）——直查文件名。
        guard let url = Bundle.module.url(
            forResource: "noiseprofiles", withExtension: "json")
        else {
            throw AppError.decodeFailed("NoiseProfileStore: bundle 缺 noiseprofiles.json")
        }
        try load(data: Data(contentsOf: url))
    }

    private func load(data: Data) throws {
        let decoded = try JSONDecoder().decode(BundleJSON.self, from: data)
        var next: [MakerModel: [NoiseProfile]] = [:]
        var makers: [String] = []
        for makerEntry in decoded.noiseprofiles {
            makers.append(makerEntry.maker)
            for model in makerEntry.models {
                var profiles: [NoiseProfile] = []
                for p in model.profiles {
                    guard p.skip != true else { continue } // dt: skip 档跳过
                    guard p.a.count == 3, p.b.count == 3 else { continue }
                    profiles.append(NoiseProfile(
                        maker: makerEntry.maker, model: model.model,
                        name: p.name, iso: p.iso,
                        a: SIMD3<Double>(p.a[0], p.a[1], p.a[2]),
                        b: SIMD3<Double>(p.b[0], p.b[1], p.b[2])))
                }
                profiles.sort { $0.iso < $1.iso }
                next[MakerModel(maker: makerEntry.maker, model: model.model)] = profiles
            }
        }
        self.table = next
        self.makerKeys = makers
        self.loaded = true
    }

    /// dt `dt_noiseprofile_get_matching` 直译：maker 子串包含（大小写敏感，
    /// EXIF Make ∋ JSON maker 串）+ model 精确相等 → 该 model 的 ISO 升序档列。
    /// 无命中 → 空数组（调用方回落 generic）。
    public func matchingProfiles(maker: String?, model: String?) throws -> [NoiseProfile] {
        try ensureLoaded()
        guard let maker, let model else { return [] }
        for jsonMaker in makerKeys where maker.contains(jsonMaker) {
            if let profiles = table[MakerModel(maker: jsonMaker, model: model)] {
                return profiles
            }
        }
        return []
    }

    /// 给定 EXIF 三元组的剖面：匹配 → ISO 括弧两档线性插值（档外 clamp 首末档）；
    /// miss → generic。name 保留命中档信息（插值档 name = "interpolated…"）。
    public func profile(maker: String?, model: String?, iso: Double) throws -> NoiseProfile {
        let profiles = try matchingProfiles(maker: maker, model: model)
        guard !profiles.isEmpty else { return .generic }
        if iso <= profiles.first!.iso { return profiles.first! }
        if iso >= profiles.last!.iso { return profiles.last! }
        for i in 0..<(profiles.count - 1) {
            let lo = profiles[i], hi = profiles[i + 1]
            if iso >= lo.iso && iso <= hi.iso {
                if iso == lo.iso { return lo }
                if iso == hi.iso { return hi }
                return NoiseProfile.interpolate(lo, hi, iso: iso)
            }
        }
        return profiles.last!
    }
}
