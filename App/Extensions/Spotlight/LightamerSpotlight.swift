import Cocoa
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
// LightamerSpotlight — the Spotlight importer app extension SHELL (Plan 13-1
// T5). ZERO business logic: session-root location, the read-only lindex row
// read and the standard-attribute mapping all live in LightamerCore
// (`SpotlightAttributeMapper`); this file is the mdimporter protocol glue.
//
// SDK shape (macOS 27, execution decision): the old Swift-only `ImportPlugin`
// protocol is GONE from the macOS 27 SDK — the importer principal class
// subclasses the ObjC `CSImportExtension` (CSImportExtension.h, macOS 12+)
// and implements `update(attributes:forFileAt:)` (the ObjC
// `updateAttributes:forFileAtURL:error:` out-param imported as `throws`).
//
// READ-ONLY discipline (the cross-process red line): this process never
// writes sidecar, lindex or thumbs — it only PROJECTS metadata out.
// ─────────────────────────────────────────────────────────────────────────────

final class ImportPlugin: CSImportExtension {

    func update(
        attributes: CSSearchableItemAttributeSet, forFileAt contentURL: URL
    ) throws {
        // Wired to SpotlightAttributeMapper in Plan 13-1 T5.
    }
}
