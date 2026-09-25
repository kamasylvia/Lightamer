import CoreImage
import Metal
import XCTest
@testable import LightamerCore

/// GUI-22 复验 note-1 回归：input-plane memo 键必须含尺寸维度——
/// 全幅腿（FULL）与 longEdge 腿（PREVIEW/THUMBNAIL）同 content 指纹
/// 但不同目标尺寸时，交替请求不得同键互踩（互踩会驱逐/重渲染并
/// 重开 CIRAW speckle 变体窗口）。39dd005 修复的键级回归。
final class CIContextPoolMemoKeyTests: XCTestCase {

    private func makePool() throws -> CIContextPool {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        return CIContextPool(device: device, commandQueue: queue)
    }

    /// 两条腿对同一内容不同目标尺寸：第二次请求不得命中第一次的
    /// 平面（尺寸入键后必然 MISS 并各自渲染）。
    func testFullAndLongEdgeLegsDoNotCollide() async throws {
        let pool = try makePool()
        let color = CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0.3))
            .cropped(to: CGRect(x: 0, y: 0, width: 512, height: 384))
        let key: UInt64 = 0xABCD_1234

        let full = try await pool.renderToTexture(color, dedupeKey: key)
        XCTAssertEqual(full.texture.width, 512)
        XCTAssertEqual(full.texture.height, 384)

        let scaled = try await pool.renderToTexture(color, longEdge: 256, dedupeKey: key)
        XCTAssertEqual(scaled.texture.width, 256)
        XCTAssertEqual(scaled.texture.height, 192)

        // 回到全幅腿：必须仍命中原全幅平面（512×384），而非被 256 覆盖
        let fullAgain = try await pool.renderToTexture(color, dedupeKey: key)
        XCTAssertEqual(fullAgain.texture.width, 512)
        XCTAssertEqual(fullAgain.texture.height, 384)
    }

    /// 同腿同键重复请求：命中冻结平面（字节恒等——GUI-22 核心承诺）。
    func testSameLegRepeatedRequestIsFrozen() async throws {
        let pool = try makePool()
        let color = CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0.3))
            .cropped(to: CGRect(x: 0, y: 0, width: 128, height: 96))
        let key: UInt64 = 0xDEAD_BEEF

        let a = try await pool.renderToTexture(color, longEdge: 128, dedupeKey: key)
        let b = try await pool.renderToTexture(color, longEdge: 128, dedupeKey: key)
        XCTAssertEqual(a.texture.width, b.texture.width)
        XCTAssertEqual(a.texture.height, b.texture.height)
        // 同一纹理对象 = memo 命中（未重执行 CIRAW）
        XCTAssertTrue(a.texture === b.texture, "same-key repeat must return the frozen memo plane")
    }
}
