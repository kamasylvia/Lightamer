import Foundation
import LightamerCore
import os

/// ExportFileWriter (Plan 11-04 T3) — the App-layer FILESYSTEM face of the
/// export landing zone.
///
/// The naming (`ExportNamer`), the atomic tmp→final promotion (L009 —
/// same-directory rename inside the encoder), and the failure-halves-stay-
///-unpromoted discipline ALL live in Core (the 11-02/11-03 renderer +
/// encoder chain, golden-covered there — the 02-05 App-layer-untestable
/// red line keeps THIS file to the pure FS decisions):
///
///   • WHERE exports land: the session's `Output/` by default (the 9-1
///     takeover constant `SessionLayout.outputDirectory(for:)` — EXP-08's
///     恒落 Session/Output/), or a user-picked directory (the panel's
///     NSOpenPanel result; validated writable here).
///   • WHAT names are taken: the occupancy snapshot the queue's
///     `occupiedNamesProvider` enumerates at DEQUEUE time (the default
///     provider lives in Core; this file offers the same read for the
///     panel's pre-flight counters).
enum ExportFileWriter {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "export-writer")

    /// The EXP-08 default landing zone: the session's `Output/`.
    static func defaultDestination(for sessionURL: URL) -> URL {
        SessionLayout.outputDirectory(for: sessionURL)
    }

    /// Ensure the landing directory exists + is writable (the default
    /// Output/ is created by `SessionLayout.ensureDirectories` at session
    /// open; a CUSTOM pick needs its own guarantee — create it rather than
    /// fail the batch at the first encode).
    static func ensureDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw AppError.invalidParameter(
                "export destination is not a directory: \(directory.path)")
        }
        logger.debug("export destination ensured: \(directory.path, privacy: .public)")
    }

    /// The occupancy read for the panel's pre-flight face (the same
    /// enumeration the queue performs per dequeue — names only, all
    /// entries).
    static func occupiedNames(in directory: URL) -> Set<String> {
        ExportQueue.defaultOccupiedNames(in: directory)
    }
}
