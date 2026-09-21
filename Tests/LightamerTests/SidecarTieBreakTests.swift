import LightamerCore
import LightamerIOP
import XCTest

/// SidecarTieBreakTests (Plan 05-03-T4) — 28.5 共槽 tie-break 回归：
/// 同槽多实例 history → effectiveInstances 确定性（opName tertiary）。
/// channelmixerrgb 是 02-05 机制的第一个真实消费者。
final class SidecarTieBreakTests: XCTestCase {

    func testCoSlotTieBreakIsDeterministic() {
        // 同一 channelmixerrgb 实例的不同 params 世代 → 最新胜出。
        var stack = HistoryStack()
        let first = ModuleInstance(
            module: ChannelMixerRGBModule.self,
            params: ChannelMixerRGBModule.Params())
        stack.commit(first, label: "cmr first")
        var tweak = first
        try! tweak.setParams(
            ChannelMixerRGBModule.Params(
                red: SIMD4<Float>(1.1, -0.05, -0.05, 0),
                green: SIMD4<Float>(-0.1, 1.2, -0.1, 0),
                blue: SIMD4<Float>(0, -0.1, 1.1, 0)),
            as: ChannelMixerRGBModule.self)
        stack.commit(tweak, label: "cmr tweak")
        let effective = stack.effectiveInstances()
        XCTAssertEqual(effective.count, 1)
        XCTAssertEqual(effective.first?.paramsHash, tweak.paramsHash)
    }

    func testSameOpMultiPriorityKeepsBoth() {
        // 同 op 不同 multiPriority = 不同实例（dt multi-instance）。
        var stack = HistoryStack()
        stack.commit(
            ModuleInstance(
                module: ChannelMixerRGBModule.self, multiPriority: 0,
                params: ChannelMixerRGBModule.Params()),
            label: "cmr prio 0")
        stack.commit(
            ModuleInstance(
                module: ChannelMixerRGBModule.self, multiPriority: 1,
                params: ChannelMixerRGBModule.Params()),
            label: "cmr prio 1")
        let effective = stack.effectiveInstances()
        XCTAssertEqual(effective.count, 2)
        XCTAssertEqual(effective[0].multiPriority, 0)
        XCTAssertEqual(effective[1].multiPriority, 1)
    }

    func testSlotOrderColorinBeforeChannelMixerRGB() {
        // 槽位序：colorin (28.0) 在 channelmixerrgb (28.5) 之前；同槽
        // tie-break 按 (iopOrder, multiPriority, opName) 确定。
        var stack = HistoryStack()
        stack.commit(
            ModuleInstance(
                module: ChannelMixerRGBModule.self,
                params: ChannelMixerRGBModule.Params()),
            label: "cmr")
        stack.commit(
            ModuleInstance(module: ColorInModule.self, params: .init()),
            label: "colorin")
        let effective = stack.effectiveInstances()
        XCTAssertEqual(effective.map(\.opName), ["colorin", "channelmixerrgb"])
    }
}
