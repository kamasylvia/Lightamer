import CoreImage
import LightamerCore
import Metal
@testable import LightamerCore
@testable import LightamerIOP
import XCTest

/// Plan 11-03 — the EXPORT pipe-leg suite.
///
/// T1 queue infrastructure (this file, `testQueueInfrastructure*`):
/// `exportCommandQueue` is a NEW property (D-15's letter — never a
/// reassignment) and the TaskLocal route (`MetalContext.$routesToExportQueue`)
/// flips the single acquisition point (`makeCommandBuffer`) to it, with the
/// editor path byte-identical when unwrapped.
///
/// T2 (export chain assembly), T3 (.export activation) and the renderer E2E
/// live in the later sections / `ExportRendererE2ETests`.
final class ExportPipeTests: XCTestCase {

    private var metal: MetalContext!

    override func setUpWithError() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
    }

    // MARK: - T1: queue infrastructure (SC#2 基建)

    /// D-15's letter: the export queue is a NEW property — a distinct
    /// instance, never a reassignment of the editor queue.
    func testQueueInfrastructureExportQueueIsNewProperty() throws {
        XCTAssertFalse(
            metal.commandQueue === metal.exportCommandQueue,
            "exportCommandQueue must be a distinct queue instance (D-15: NEW property)")
        // Both queues are live: each can mint a buffer.
        XCTAssertNotNil(metal.commandQueue.makeCommandBuffer())
        XCTAssertNotNil(metal.exportCommandQueue.makeCommandBuffer())
    }

    /// The TaskLocal route flips the single acquisition point: wrapped, the
    /// acquired buffer's queue IS the export queue (R8's precondition — the
    /// exit leg's fence only orders export writes if it hangs on the queue
    /// the pipe wrote through).
    func testQueueInfrastructureTaskLocalRoutesToExportQueue() throws {
        // Unwrapped: the editor queue (today's behavior, byte-identical).
        let editorBuffer = try metal.makeRoutedCommandBuffer()
        XCTAssertTrue(editorBuffer.commandQueue === metal.commandQueue)

        // Wrapped: the export queue.
        let exportBuffer = try MetalContext.$routesToExportQueue.withValue(true) {
            try metal.makeRoutedCommandBuffer()
        }
        XCTAssertTrue(
            exportBuffer.commandQueue === metal.exportCommandQueue,
            "a routed acquisition must come from exportCommandQueue")

        // After the scope exits the route is off again (no leakage).
        let afterBuffer = try metal.makeRoutedCommandBuffer()
        XCTAssertTrue(afterBuffer.commandQueue === metal.commandQueue)
    }

    /// The route propagates down the STRUCTURED task tree — the 11-04 export
    /// job runner wraps its whole render task in `withValue(true)`, and iop
    /// dispatches inside child tasks must land on the export queue without
    /// touching a single iop call site. (`Task {}` inherits task-locals;
    /// `Task.detached` deliberately does not — the render tree is structured.)
    func testQueueInfrastructureRoutePropagatesIntoChildTasks() async throws {
        let metal = self.metal!
        let routed: Bool = await MetalContext.$routesToExportQueue.withValue(true) {
            await Task(priority: .utility) {
                MetalContext.routesToExportQueue
            }.value
        }
        XCTAssertTrue(routed, "TaskLocal route must cross structured child tasks")

        // And a child-task acquisition inside the wrap lands on the export
        // queue (the exact shape the export render uses).
        let isExport = try await MetalContext.$routesToExportQueue.withValue(true) {
            try await Task(priority: .utility) {
                let buffer = try metal.makeRoutedCommandBuffer()
                return buffer.commandQueue === metal.exportCommandQueue
            }.value
        }
        XCTAssertTrue(isExport)

        // The editor's unwrapped tree stays on the editor queue.
        let editorIsEditor = try await Task(priority: .userInitiated) {
            let buffer = try metal.makeRoutedCommandBuffer()
            return buffer.commandQueue === metal.commandQueue
        }.value
        XCTAssertTrue(editorIsEditor, "the unwrapped path must stay on the editor queue")
    }
}
