import CoreVideo
import XCTest
@testable import LightamerCore

/// 07-1 验收 P1 回归：maskPlane(from:) 必须支持层 B
/// （GenerateIterativeSegmentationRequest）真实输出格式 'L00h'
/// （0x4C303068，LE UInt16 采样）。该格式在测试宿主的层 B 推理腿
/// 不可达（entitlement 阻断下载），故用合成 CVPixelBuffer 直接钉
/// 格式臂——防同盲区复发（07-1 验收报告 P1）。
final class AIMaskPlaneFormatTests: XCTestCase {

    /// 合成指定格式的单通道 CVPixelBuffer（层 B 实测 bpr = 2·width）。
    private func makeL00hBuffer(width: Int, height: Int, pixel: UInt16) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            OSType(0x4C303068) /* 'L00h' */, nil, &pb)
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = try XCTUnwrap(pb)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let row = base.assumingMemoryBound(to: UInt16.self)
        let bpr = CVPixelBufferGetBytesPerRow(buffer) / 2
        for y in 0..<height {
            for x in 0..<width {
                row[y * bpr + x] = pixel
            }
        }
        return buffer
    }

    /// 'L00h' UInt16 / 65535 归一化臂：0xFEFE（65278）→ ~0.9966。
    func testL00hUInt16Normalization() throws {
        let buffer = try makeL00hBuffer(width: 4, height: 4, pixel: 0xFEFE)
        let plane = try AIMaskService.maskPlane(from: buffer)
        XCTAssertEqual(plane.width, 4)
        XCTAssertEqual(plane.height, 4)
        XCTAssertEqual(plane.floats.count, 16)
        for f in plane.floats {
            XCTAssertEqual(Float(0xFEFE) / 65535.0, f, accuracy: 1e-6)
        }
    }

    /// 'L00h' 零值臂：0x0000 → 0.0。
    func testL00hZeroBackground() throws {
        let buffer = try makeL00hBuffer(width: 4, height: 4, pixel: 0x0000)
        let plane = try AIMaskService.maskPlane(from: buffer)
        for f in plane.floats {
            XCTAssertEqual(f, 0.0, accuracy: 1e-6)
        }
    }

    /// bpr = 2·width + padding 的行距口径（实测层 B bpr 含行尾 padding）。
    func testL00hRespectsBytesPerRow() throws {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 3, 2, OSType(0x4C303068), nil, &pb)
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = try XCTUnwrap(pb)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let row = base.assumingMemoryBound(to: UInt16.self)
        // 行距口径：按 bpr/2 步进（非 width），padding 单元不参与归一化
        for y in 0..<2 {
            for x in 0..<3 {
                row[y * (bpr / 2) + x] = UInt16(1000 * (y * 3 + x + 1))
            }
        }
        let plane = try AIMaskService.maskPlane(from: buffer)
        XCTAssertEqual(plane.floats.count, 6)
        XCTAssertEqual(plane.floats[0], Float(1000) / 65535.0, accuracy: 1e-6)
        XCTAssertEqual(plane.floats[5], Float(6000) / 65535.0, accuracy: 1e-6)
    }
}
