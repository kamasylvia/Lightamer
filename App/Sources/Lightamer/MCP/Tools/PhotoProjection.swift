import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-3 T1: the list_photos projection + input mapping layer.
//
// THREE responsibilities, all pure:
//   ① the 25-column MCP projection of `SessionIndexRow` (research
//      §RQ-14-7③ 终表 — the checker M-2 corrected count: expose 25, hide 9;
//      the plan body's "22" is a planning typo, the RESEARCH table is the
//      frozen正本). ONE assembly site — every list_photos row dict comes
//      from `rowDict(from:)`.
//   ② the FilterPredicateGroup JSON input face: the group decodes DIRECTLY
//      (zero new translation layer — 12 移交③), legality is the EXISTING
//      `legalOps`/`legalValueKinds` matrix; every failure maps to the typed
//      `invalidFilter` code.
//   ③ the keyset-cursor codec: base64(JSON) carrying the sort key's last
//      value + path; the tuple predicate is spelled HERE and handed to
//      `SessionIndexStore.query(extraPredicate:)` — the caller-side append
//      point. FilterSQL untouched.
//
// Plus the tiny McpJSON → JSON-Data serializer the text outputs use.
// ─────────────────────────────────────────────────────────────────────────────

/// The frozen exposed-column spellings (the v2 schema names — the SAME
/// literals as `SessionIndexSchema.imagesColumns`). Keys ALWAYS ride every
/// row dict; a NULL column is `McpJSON.null` (a stable row shape — clients
/// key by name, never by presence).
enum McpPhotoProjection {

    /// The 25 exposed columns in projection order (path first — the tool
    /// interconnect key; geometry next to it for the get_detail_crop
    /// coordinate loop).
    static let exposedColumns: [String] = [
        "path", "dir", "filename",
        "file_size", "file_mtime",
        "has_edits",
        "layer_count", "layer_summary",
        "orientation", "width", "height",
        "capture_date",
        "thumb_state",
        "rating", "color_label", "keywords", "flag", "note",
        "camera_make", "camera_model", "lens_model",
        "iso", "focal_length", "aperture", "exposure",
    ]

    /// The NEVER-exposed columns (the audit half of the 终表 — the snapshot
    /// test greps these out of every row dict).
    static let hiddenColumns: [String] = [
        "scan_epoch", "imageID",
        "sidecar_present", "sidecar_mtime",
        "params_hash",
        "thumb_path", "thumb_params_hash",
        "orphan_sidecar", "dirty",
    ]

    /// SessionIndexRow → the MCP dict (the ONE assembly site).
    static func rowDict(from row: SessionIndexRow) -> [String: McpJSON] {
        var dict: [String: McpJSON] = [:]
        dict["path"] = .string(row.path)
        dict["dir"] = row.dir.map { .string($0) } ?? .null
        dict["filename"] = row.filename.map { .string($0) } ?? .null
        dict["file_size"] = row.fileSize.map { .int(Int($0)) } ?? .null
        dict["file_mtime"] = row.fileMtime.map { .double($0) } ?? .null
        dict["has_edits"] = row.hasEdits.map { .int(Int($0)) } ?? .null
        dict["layer_count"] = row.layerCount.map { .int(Int($0)) } ?? .null
        dict["layer_summary"] = row.layerSummary.map { .string($0) } ?? .null
        dict["orientation"] = row.orientation.map { .int(Int($0)) } ?? .null
        dict["width"] = row.width.map { .int(Int($0)) } ?? .null
        dict["height"] = row.height.map { .int(Int($0)) } ?? .null
        dict["capture_date"] = row.captureDate.map { .double($0) } ?? .null
        dict["thumb_state"] = row.thumbState.map { .int(Int($0)) } ?? .null
        dict["rating"] = row.rating.map { .int(Int($0)) } ?? .null
        dict["color_label"] = row.colorLabel.map { .int(Int($0)) } ?? .null
        dict["keywords"] = row.keywords.map { .string($0) } ?? .null
        dict["flag"] = row.flag.map { .int(Int($0)) } ?? .null
        dict["note"] = row.note.map { .string($0) } ?? .null
        dict["camera_make"] = row.cameraMake.map { .string($0) } ?? .null
        dict["camera_model"] = row.cameraModel.map { .string($0) } ?? .null
        dict["lens_model"] = row.lensModel.map { .string($0) } ?? .null
        dict["iso"] = row.iso.map { .int(Int($0)) } ?? .null
        dict["focal_length"] = row.focalLength.map { .double($0) } ?? .null
        dict["aperture"] = row.aperture.map { .double($0) } ?? .null
        dict["exposure"] = row.exposure.map { .double($0) } ?? .null
        return dict
    }

    // MARK: - Input mapping (filter / sort / limit)

    /// Decode the optional `filter` argument: a FilterPredicateGroup JSON
    /// object VERBATIM (`{schemaVersion, match, rules:[{field, op, value}]}`).
    /// Every failure — unparsable JSON, unknown field/op/kind, an illegal
    /// field×op×value combo — is the typed `invalidFilter`.
    static func decodeFilter(
        _ arguments: [String: McpJSON]
    ) throws -> FilterPredicateGroup? {
        guard let filterArg = arguments["filter"], !filterArg.isNull else { return nil }
        let data = McpJSONSerialization.data(from: filterArg)
        let group: FilterPredicateGroup
        do {
            group = try JSONDecoder().decode(FilterPredicateGroup.self, from: data)
        } catch let error as DecodingError {
            throw McpToolError.invalidFilter(
                "filter is not a FilterPredicateGroup JSON object: "
                    + "\(decodeFailureDetail(error))")
        } catch {
            throw McpToolError.invalidFilter("filter decode failed: \(error)")
        }
        // The legality matrix is the EXISTING model face — no second table.
        do {
            try group.validating()
        } catch let violation as FilterPredicateError {
            throw McpToolError.invalidFilter(describe(violation))
        } catch {
            throw McpToolError.invalidFilter("\(error)")
        }
        return group
    }

    /// Decode the optional `sort` argument (`{key, ascending}` — the
    /// FilterSortKey whitelist's raw spellings; ascending defaults true).
    static func decodeSort(
        _ arguments: [String: McpJSON]
    ) throws -> FilterSort? {
        guard let sortArg = arguments["sort"], !sortArg.isNull else { return nil }
        guard case .object(let members) = sortArg else {
            throw McpToolError.invalidParams("sort must be an object {key, ascending}")
        }
        guard let keyRaw = members["key"]?.stringValue,
            let key = FilterSortKey(rawValue: keyRaw)
        else {
            throw McpToolError.invalidParams(
                "sort.key must be one of \(FilterSortKey.allCases.map(\.rawValue))")
        }
        var ascending = true
        if let flag = members["ascending"] {
            guard case .bool(let value) = flag else {
                throw McpToolError.invalidParams("sort.ascending must be a boolean")
            }
            ascending = value
        }
        return FilterSort(key: key, ascending: ascending)
    }

    /// Decode `limit` (default 200, cap 1000 — the research §RQ-14-7① face).
    static func decodeLimit(_ arguments: [String: McpJSON]) throws -> Int {
        guard let limitArg = arguments["limit"], !limitArg.isNull else { return 200 }
        guard let limit = limitArg.intValue, limit >= 1, limit <= 1000 else {
            throw McpToolError.invalidParams("limit must be an integer in 1...1000")
        }
        return limit
    }

    private static func describe(_ violation: FilterPredicateError) -> String {
        switch violation {
        case .unknownField(let raw): "unknown filter field '\(raw)'"
        case .unknownOp(let raw): "unknown filter op '\(raw)'"
        case .unknownValueKind(let raw): "unknown filter value kind '\(raw)'"
        case .illegalFieldOperator(let field, let op):
            "op '\(op.rawValue)' is not legal for field '\(field.rawValue)'"
        case .illegalValueKind(let field, let op, let kind):
            "value kind '\(kind)' does not fit \(field.rawValue) \(op.rawValue)"
        case .invalidInterval(let field):
            "\(field.rawValue) between-interval has lower > upper"
        }
    }

    private static func decodeFailureDetail(_ error: DecodingError) -> String {
        if case .dataCorrupted(let context) = error { return context.debugDescription }
        if case .typeMismatch(_, let context) = error { return context.debugDescription }
        if case .valueNotFound(_, let context) = error { return context.debugDescription }
        if case .keyNotFound(_, let context) = error { return context.debugDescription }
        return "unparsable"
    }

    // MARK: - Keyset cursor

    /// The cursor's sort-key value (JSON-exact kinds only).
    enum CursorValue: Equatable, Sendable {
        case text(String)
        case int(Int)
        case double(Double)
        /// The NULL-key class (unrated / never shot rows sort last; the
        /// continuation predicate is the `(k IS NULL AND path > ?)` shape).
        case null
    }

    struct Cursor: Equatable, Sendable {
        var sortKey: FilterSortKey
        var ascending: Bool
        var path: String
        var value: CursorValue
    }

    /// Encode a cursor: base64(sortedKeys JSON). The payload carries its
    /// own sort key + direction so a mismatched reuse is REJECTED (the
    /// 换排序键游标失效 negative).
    static func encodeCursor(_ cursor: Cursor) -> String {
        struct Payload: Codable {
            var k: String
            var d: String
            var p: String
            var v: CursorValuePayload?
        }
        struct CursorValuePayload: Codable {
            var kind: String
            var text: String?
            var int: Int?
            var double: Double?
        }
        let value: CursorValuePayload
        switch cursor.value {
        case .text(let text):
            value = .init(kind: "text", text: text, int: nil, double: nil)
        case .int(let int):
            value = .init(kind: "int", text: nil, int: int, double: nil)
        case .double(let double):
            value = .init(kind: "double", text: nil, int: nil, double: double)
        case .null:
            value = .init(kind: "null", text: nil, int: nil, double: nil)
        }
        let payload = Payload(
            k: cursor.sortKey.rawValue,
            d: cursor.ascending ? "asc" : "desc",
            p: cursor.path,
            v: value)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = (try? encoder.encode(payload)) ?? Data()
        return json.base64EncodedString()
    }

    /// Decode a cursor (typed `invalidParams` on garbage — a cursor is not
    /// user-authored filter semantics, it is OUR token).
    static func decodeCursor(_ raw: String) throws -> Cursor {
        struct Payload: Codable {
            var k: String
            var d: String
            var p: String
            var v: CursorValuePayload?
        }
        struct CursorValuePayload: Codable {
            var kind: String
            var text: String?
            var int: Int?
            var double: Double?
        }
        guard let outer = Data(base64Encoded: raw),
            let payload = try? JSONDecoder().decode(Payload.self, from: outer),
            let key = FilterSortKey(rawValue: payload.k)
        else {
            throw McpToolError.invalidParams("cursor is not a valid list_photos token")
        }
        let value: CursorValue
        switch payload.v?.kind {
        case "text": value = payload.v?.text.map { .text($0) } ?? .null
        case "int": value = payload.v?.int.map { .int($0) } ?? .null
        case "double": value = payload.v?.double.map { .double($0) } ?? .null
        default: value = .null
        }
        return Cursor(
            sortKey: key, ascending: payload.d != "desc",
            path: payload.p, value: value)
    }

    /// The tuple predicate for a cursor — spelled at THIS call site (the
    /// `path` tiebreaker is ASC in both directions per
    /// `FilterSort.orderBySQL`, so the second tuple leg is always `path > ?`).
    /// The NULL-key continuation is the separate NULL-class shape.
    static func cursorPredicate(_ cursor: Cursor) -> SessionIndexStore.ExtraPredicate {
        let column = cursor.sortKey.column
        switch cursor.value {
        case .null:
            return SessionIndexStore.ExtraPredicate(
                sql: "(\(column) IS NULL AND path > ?)",
                binds: [.text(cursor.path)])
        case .text(let value):
            let op = cursor.ascending ? ">" : "<"
            return SessionIndexStore.ExtraPredicate(
                sql: "((\(column) \(op) ?) OR (\(column) = ? AND path > ?))",
                binds: [.text(value), .text(value), .text(cursor.path)])
        case .int(let value):
            let op = cursor.ascending ? ">" : "<"
            return SessionIndexStore.ExtraPredicate(
                sql: "((\(column) \(op) ?) OR (\(column) = ? AND path > ?))",
                binds: [.int(Int64(value)), .int(Int64(value)), .text(cursor.path)])
        case .double(let value):
            let op = cursor.ascending ? ">" : "<"
            return SessionIndexStore.ExtraPredicate(
                sql: "((\(column) \(op) ?) OR (\(column) = ? AND path > ?))",
                binds: [.double(value), .double(value), .text(cursor.path)])
        }
    }

    /// Validate a cursor against the CURRENT request's sort (the mismatch
    /// negative) and build its predicate.
    static func cursorPredicate(
        _ raw: String, sort: FilterSort?
    ) throws -> SessionIndexStore.ExtraPredicate {
        let cursor = try decodeCursor(raw)
        let effectiveSort = sort ?? FilterSort(key: .filename, ascending: true)
        guard cursor.sortKey == effectiveSort.key, cursor.ascending == effectiveSort.ascending else {
            throw McpToolError.invalidParams(
                "cursor was issued for sort \(cursor.sortKey.rawValue)/"
                    + "\(cursor.ascending ? "asc" : "desc") — pass the same sort "
                    + "or drop the cursor to restart paging")
        }
        return cursorPredicate(cursor)
    }

    /// The cursor value a row carries for `sortKey` (the nextCursor source).
    static func cursorValue(
        for sortKey: FilterSortKey, row: SessionIndexRow
    ) -> CursorValue {
        switch sortKey {
        case .filename: return row.filename.map { .text($0) } ?? .null
        case .rating: return row.rating.map { .int(Int($0)) } ?? .null
        case .captureDate: return row.captureDate.map { .double($0) } ?? .null
        case .iso: return row.iso.map { .int(Int($0)) } ?? .null
        case .focalLength: return row.focalLength.map { .double($0) } ?? .null
        case .scanEpoch: return .null  // internal epoch — never a cursor face
        }
    }

    /// Build the nextCursor token from the page's last row (or nil when the
    /// page is short — the exhaustion signal the agent senses instead of a
    /// total count).
    static func nextCursor(
        rows: [SessionIndexRow], sort: FilterSort?, limit: Int
    ) -> String? {
        guard rows.count == limit, let last = rows.last else { return nil }
        let key = sort?.key ?? .filename
        let ascending = sort?.ascending ?? true
        return encodeCursor(
            Cursor(
                sortKey: key, ascending: ascending, path: last.path,
                value: cursorValue(for: key, row: last)))
    }
}

/// The McpJSON → JSON-Data face for tool outputs (JSONSerialization does the
/// string escaping; Int/Double/Bool map to NSNumber, null to NSNull).
enum McpJSONSerialization {

    static func data(from value: McpJSON) -> Data {
        let any = anyValue(from: value)
        return (try? JSONSerialization.data(withJSONObject: any, options: [.sortedKeys]))
            ?? Data("{}".utf8)
    }

    static func dataWithoutSorting(from value: McpJSON) -> Data {
        let any = anyValue(from: value)
        return (try? JSONSerialization.data(withJSONObject: any, options: []))
            ?? Data("{}".utf8)
    }

    static func text(from value: McpJSON) -> String {
        String(data: data(from: value), encoding: .utf8) ?? "{}"
    }

    private static func anyValue(from value: McpJSON) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let b): return NSNumber(value: b)
        case .int(let i): return NSNumber(value: i)
        case .double(let d): return NSNumber(value: d)
        case .string(let s): return NSString(string: s)
        case .array(let items): return items.map { anyValue(from: $0) }
        case .object(let members):
            var dict: [String: Any] = [:]
            for (key, member) in members { dict[key] = anyValue(from: member) }
            return dict
        }
    }
}

extension McpJSON {
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var arrayValue: [McpJSON]? {
        if case .array(let items) = self { return items }
        return nil
    }

    var objectValue: [String: McpJSON]? {
        if case .object(let members) = self { return members }
        return nil
    }
}
