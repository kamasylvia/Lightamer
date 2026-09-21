@testable import LightamerIOP
import XCTest

/// NoiseProfileStoreTests (Plan 05-01-T4) — 手算向量 + 匹配边界 + generic 链。
///
/// 手算值表（ILCE-9M3 ISO 125/160 相邻档，dt data/noiseprofiles.json 原值，
/// Double 精算；mid ISO 140，t = 15/35）：
/// - 125 档 a = [7.65705497686894e-06, 1.54601975602981e-06, 2.30077680147848e-06]
///          b = [2.00608030560566e-09, 3.03636277807135e-09, 4.74823179066283e-09]
/// - 160 档 a = [6.3182183632213e-06, 1.88249557294803e-06, 2.85361575615022e-06]
///          b = [8.1206859365105e-09, 4.47155583563907e-09, 6.75275798557236e-09]
/// - ISO 140 期望 a = [7.083267856734237e-06, 1.69022367756619e-06, 2.537707782052083e-06]
///                  b = [4.626625575993448e-09, 3.651445517028944e-09, 5.607314445624057e-09]
///
/// 防空转：全部含真实比较循环（逐通道/逐档比较）+ `compared > 0`。
final class NoiseProfileStoreTests: XCTestCase {

    /// 内嵌迷你 bundle（与真实 schema 同形，含 skip 档 + 大小写 maker 陷阱）。
    private var miniJSON: Data {
        """
        {"version": 0, "noiseprofiles": [
          {"maker": "Sony", "models": [
            {"model": "ILCE-9M3", "comment": "test", "profiles": [
              {"name": "ILCE-9M3 iso 125", "iso": 125,
               "a": [7.65705497686894e-06, 1.54601975602981e-06, 2.30077680147848e-06],
               "b": [2.00608030560566e-09, 3.03636277807135e-09, 4.74823179066283e-09]},
              {"name": "ILCE-9M3 iso 160 skip", "iso": 140, "skip": true,
               "a": [9.0e-06, 9.0e-06, 9.0e-06], "b": [9.0e-09, 9.0e-09, 9.0e-09]},
              {"name": "ILCE-9M3 iso 160", "iso": 160,
               "a": [6.3182183632213e-06, 1.88249557294803e-06, 2.85361575615022e-06],
               "b": [8.1206859365105e-09, 4.47155583563907e-09, 6.75275798557236e-09]}
            ]}
          ]},
          {"maker": "Canon", "models": [
            {"model": "EOS R5", "comment": "", "profiles": [
              {"name": "EOS R5 iso 100", "iso": 100,
               "a": [1.0e-06, 2.0e-06, 3.0e-06], "b": [1.0e-09, 2.0e-09, 3.0e-09]}
            ]}
          ]}
        ]}
        """.data(using: .utf8)!
    }

    private func makeStore() async throws -> NoiseProfileStore {
        let store = NoiseProfileStore()
        try await store.loadForTests(miniJSON)
        return store
    }

    // MARK: - 插值手算向量

    /// ISO 140（skip 档 140 被跳过后，括弧档仍为 125/160）→ 手算期望逐通道。
    func testMidISOInterpolatesHandComputedVector() async throws {
        let store = try await makeStore()
        let got = try await store.profile(maker: "Sony", model: "ILCE-9M3", iso: 140)
        let wantA = SIMD3<Double>(7.083267856734237e-06, 1.69022367756619e-06, 2.537707782052083e-06)
        let wantB = SIMD3<Double>(4.626625575993448e-09, 3.651445517028944e-09, 5.607314445624057e-09)
        XCTAssertEqual(got.iso, 140, accuracy: 1e-12)
        var compared = 0
        for i in 0..<3 {
            compared += 1
            XCTAssertEqual(got.a[i], wantA[i], accuracy: 1e-21, "a[\(i)]")
            XCTAssertEqual(got.b[i], wantB[i], accuracy: 1e-24, "b[\(i)]")
        }
        XCTAssertGreaterThan(compared, 0)
    }

    /// 档位精确命中 + 档外 clamp 首末档。
    func testExactHitAndOutOfRangeClamp() async throws {
        let store = try await makeStore()
        let exact = try await store.profile(maker: "Sony", model: "ILCE-9M3", iso: 125)
        XCTAssertEqual(exact.name, "ILCE-9M3 iso 125")
        var compared = 0
        for i in 0..<3 {
            compared += 1
            XCTAssertEqual(exact.a[i], [7.65705497686894e-06, 1.54601975602981e-06, 2.30077680147848e-06][i], accuracy: 1e-21, "a[\(i)]")
            XCTAssertEqual(exact.b[i], [2.00608030560566e-09, 3.03636277807135e-09, 4.74823179066283e-09][i], accuracy: 1e-24, "b[\(i)]")
        }
        let below = try await store.profile(maker: "Sony", model: "ILCE-9M3", iso: 50)
        XCTAssertEqual(below.name, "ILCE-9M3 iso 125", "档下 clamp 首档")
        let above = try await store.profile(maker: "Sony", model: "ILCE-9M3", iso: 6400)
        XCTAssertEqual(above.name, "ILCE-9M3 iso 160", "档上 clamp 末档")
        XCTAssertGreaterThan(compared, 0)
    }

    // MARK: - 匹配边界（dt strstr/strcmp 语义钉死）

    func testMakerSubstringAndModelExact() async throws {
        let store = try await makeStore()
        // maker 子串：EXIF Make 含 JSON maker 串即命中（"SONY Corp" 含 "Sony"? 不——
        // 大小写敏感，"SONY Corp" 不含 "Sony"；"ILCE Sony" 含 "Sony" 命中）。
        let hit = try await store.matchingProfiles(maker: "ILCE Sony", model: "ILCE-9M3")
        XCTAssertEqual(hit.count, 2, "skip 档剔除后 2 档")
        let missCase = try await store.matchingProfiles(maker: "SONY", model: "ILCE-9M3")
        XCTAssertEqual(missCase.count, 0, "大小写敏感：SONY ≠ Sony（dt strstr 直译）")
        // model 必须精确：近似 model 不命中。
        let missModel = try await store.matchingProfiles(maker: "Sony", model: "ILCE-9M")
        XCTAssertEqual(missModel.count, 0, "model 精确匹配（dt strcmp）")
        // skip 档跳过后取邻档：ISO 140 无 skip 档可取（skip 已剔除）。
        var compared = 0
        for p in hit {
            compared += 1
            XCTAssertFalse(p.name.contains("skip"), "skip 档不得出现")
        }
        XCTAssertGreaterThan(compared, 0)
    }

    // MARK: - generic 链

    /// 未知 maker/model → generic 逐值（a=1e-4×3, b=0）。
    func testUnknownMakerModelFallsBackToGeneric() async throws {
        let store = try await makeStore()
        let got = try await store.profile(maker: "Unknown", model: "Nope", iso: 400)
        XCTAssertEqual(got.name, "generic poissonian")
        var compared = 0
        for i in 0..<3 {
            compared += 1
            XCTAssertEqual(got.a[i], 1e-4, accuracy: 0)
            XCTAssertEqual(got.b[i], 0, accuracy: 0)
        }
        XCTAssertGreaterThan(compared, 0)
        // nil EXIF 同样 generic（不崩）。
        let nilGot = try await store.profile(maker: nil, model: nil, iso: 400)
        XCTAssertEqual(nilGot, got)
    }

    // MARK: - 加载性能 smoke + 缓存

    /// 真实 bundle 首次解析 <1s；二问同实例（缓存路径不断言计时，只断言同值）。
    func testRealBundleLoadsUnderOneSecond() async throws {
        let store = NoiseProfileStore()
        let start = Date()
        let sony = try await store.profile(maker: "Sony", model: "ILCE-9M3", iso: 140)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "首次解析 <1s（CI 安全上限）")
        let again = try await store.profile(maker: "Sony", model: "ILCE-9M3", iso: 140)
        XCTAssertEqual(sony, again, "二问走缓存同值")
        // 真实 bundle 手算交叉：与本文件头值表一致（bundle 规范化无损）。
        XCTAssertEqual(sony.a[0], 7.083267856734237e-06, accuracy: 1e-21)
        XCTAssertEqual(sony.b[2], 5.607314445624057e-09, accuracy: 1e-24)
    }
}
